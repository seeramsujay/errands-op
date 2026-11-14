import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/constants.dart';

enum HaConnectionState {
  notConfigured, // No URL/token yet: the app works fully offline
  disconnected,
  connecting,
  authenticating,
  connected,
  error,
}

/// A to-do item as Home Assistant reports it (todo/item/subscribe).
class HaTodoItem {
  final String uid;
  final String summary;
  final String status; // 'needs_action' | 'completed'
  final String? description;

  const HaTodoItem({
    required this.uid,
    required this.summary,
    this.status = 'needs_action',
    this.description,
  });

  factory HaTodoItem.fromJson(Map<String, dynamic> json) {
    return HaTodoItem(
      uid: json['uid'] as String,
      summary: (json['summary'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'needs_action',
      description: json['description'] as String?,
    );
  }
}

/// Result of a call over the socket.
class HaResult {
  final bool success;
  final String? error;
  final Object? result;
  const HaResult({required this.success, this.error, this.result});
}

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

/// Home Assistant WebSocket API client over /api/websocket
class HomeAssistantWsClient {
  String _baseUrl;
  String _accessToken;
  String _entityId;
  final WebSocketConnector _connector;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  int _messageId = 1;
  int? _subscriptionId;
  bool _wantConnected = false;
  final Map<int, Completer<HaResult>> _pendingRequests = {};

  HaConnectionState _state = HaConnectionState.notConfigured;
  String? _lastError;
  final _stateController = StreamController<HaConnectionState>.broadcast();
  final _itemsController = StreamController<List<HaTodoItem>>.broadcast();

  HomeAssistantWsClient({
    this._baseUrl = '',
    this._accessToken = '',
    this._entityId = AppConstants.defaultHaEntityId,
    WebSocketConnector? connector,
  }) : _connector = connector ?? WebSocketChannel.connect {
    _state = isConfigured
        ? HaConnectionState.disconnected
        : HaConnectionState.notConfigured;
  }

  String get baseUrl => _baseUrl;
  String get entityId => _entityId;
  bool get hasToken => _accessToken.isNotEmpty;
  bool get isConfigured =>
      _baseUrl.trim().isNotEmpty && _accessToken.isNotEmpty;
  bool get isConnected => _state == HaConnectionState.connected;
  HaConnectionState get state => _state;
  String? get lastError => _lastError;
  Stream<HaConnectionState> get stateStream => _stateController.stream;

  /// Full item list of the entity, emitted on subscribe and on every change.
  Stream<List<HaTodoItem>> get itemsStream => _itemsController.stream;

  /// Derive ws(s)://host[:port]/api/websocket from what users usually paste:
  /// "homeassistant.local:8123", "http://192.168.1.5:8123", "https://x.ui.nabu.casa".
  static Uri websocketUri(String baseUrl) {
    var raw = baseUrl.trim();
    final hadScheme = raw.contains('://');
    if (!hadScheme) raw = 'http://$raw';
    final parsed = Uri.parse(raw);
    final secure = parsed.scheme == 'https' || parsed.scheme == 'wss';
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: parsed.host,
      port: parsed.hasPort
          ? parsed.port
          : (hadScheme ? null : AppConstants.defaultWsPort),
      path: '/api/websocket',
    );
  }

  void _setState(HaConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// Change connection settings; reconnects if a connection was wanted.
  Future<void> configure({
    required String baseUrl,
    required String accessToken,
    required String entityId,
  }) async {
    final wasWanted = _wantConnected;
    disconnect();
    _baseUrl = baseUrl.trim();
    _accessToken = accessToken.trim();
    _entityId = entityId.trim().isEmpty
        ? AppConstants.defaultHaEntityId
        : entityId.trim();
    _lastError = null;
    _setState(
      isConfigured
          ? HaConnectionState.disconnected
          : HaConnectionState.notConfigured,
    );
    if (wasWanted && isConfigured) await connect();
  }

  /// Connect to Home Assistant WebSocket
  Future<void> connect() async {
    if (!isConfigured) {
      _setState(HaConnectionState.notConfigured);
      return;
    }
    _wantConnected = true;
    if (_state == HaConnectionState.connecting ||
        _state == HaConnectionState.connected ||
        _state == HaConnectionState.authenticating) {
      return;
    }

    _setState(HaConnectionState.connecting);
    try {
      final channel = _connector(websocketUri(_baseUrl));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessageReceived,
        onError: _onError,
        onDone: _onDisconnected,
        cancelOnError: true,
      );
    } catch (e) {
      _onError(e);
    }
  }

  void _onMessageReceived(dynamic message) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(message as String) as Map<String, dynamic>;
    } catch (_) {
      return; // Not JSON; ignore.
    }
    final type = data['type'] as String?;

    switch (type) {
      case 'auth_required':
        _setState(HaConnectionState.authenticating);
        _sendRaw({'type': 'auth', 'access_token': _accessToken});
        return;
      case 'auth_ok':
        _reconnectAttempts = 0;
        _lastError = null;
        _setState(HaConnectionState.connected);
        _subscribeToTodo();
        _startPing();
        return;
      case 'auth_invalid':
        _lastError = (data['message'] as String?) ?? 'Invalid access token';
        _wantConnected = false; // Retrying with the same token won't help.
        _teardown();
        _setState(HaConnectionState.error);
        return;
      case 'event':
        if (data['id'] == _subscriptionId) {
          final event = data['event'] as Map<String, dynamic>?;
          final items = event?['items'] as List?;
          if (items != null && !_itemsController.isClosed) {
            _itemsController.add(
              items
                  .map(
                    (i) => HaTodoItem.fromJson(
                      Map<String, dynamic>.from(i as Map),
                    ),
                  )
                  .toList(),
            );
          }
        }
        return;
      case 'result':
      case 'pong':
        final id = data['id'] as int?;
        final completer = id == null ? null : _pendingRequests.remove(id);
        if (completer == null) return;
        if (type == 'pong' || data['success'] == true) {
          completer.complete(HaResult(success: true, result: data['result']));
        } else {
          final error = data['error'] as Map?;
          completer.complete(
            HaResult(
              success: false,
              error: (error?['message'] ?? error?['code'] ?? 'request failed')
                  .toString(),
            ),
          );
        }
        return;
    }
  }

  Future<void> _subscribeToTodo() async {
    // Events for this subscription carry the id of the subscribe request.
    _subscriptionId = _messageId;
    final res = await sendMessage({
      'type': 'todo/item/subscribe',
      'entity_id': _entityId,
    });
    if (!res.success && _state == HaConnectionState.connected) {
      _lastError = 'Could not subscribe to $_entityId: ${res.error}';
      _setState(HaConnectionState.error);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final res = await sendMessage({
        'type': 'ping',
      }, timeout: const Duration(seconds: 10));
      if (!res.success && _state == HaConnectionState.connected) {
        _onError('ping timeout');
      }
    });
  }

  /// Send message and await its result
  Future<HaResult> sendMessage(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_channel == null) {
      return Future.value(
        const HaResult(success: false, error: 'not connected'),
      );
    }

    final id = _messageId++;
    final completer = Completer<HaResult>();
    _pendingRequests[id] = completer;
    _sendRaw({...payload, 'id': id});

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        return const HaResult(success: false, error: 'timeout');
      },
    );
  }

  void _sendRaw(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {
      // Sink closed underneath us; onDone/onError will handle reconnecting.
    }
  }

  Future<HaResult> _callTodoService(
    String service,
    Map<String, dynamic> serviceData,
  ) {
    return sendMessage({
      'type': 'call_service',
      'domain': 'todo',
      'service': service,
      'service_data': serviceData,
      'target': {'entity_id': _entityId},
    });
  }

  /// Update an existing item. Only the given fields are sent: some to-do
  /// integrations (e.g. the built-in shopping list) reject a description.
  Future<HaResult> updateItem({
    required String uid,
    String? rename,
    String? status,
    String? description,
  }) {
    return _callTodoService('update_item', {
      'item': uid,
      'rename': ?rename,
      'status': ?status,
      'description': ?description,
    });
  }

  /// HA assigns the uid; it arrives with the next subscription snapshot.
  Future<HaResult> addItem({required String summary}) {
    return _callTodoService('add_item', {'item': summary});
  }

  Future<HaResult> removeItem({required String uid}) {
    return _callTodoService('remove_item', {
      'item': [uid],
    });
  }

  void _onError(dynamic error) {
    _lastError = error.toString();
    _teardown();
    _setState(HaConnectionState.error);
    _scheduleReconnect();
  }

  void _onDisconnected() {
    _teardown();
    _setState(HaConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _subscriptionId = null;
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.complete(const HaResult(success: false, error: 'disconnected'));
      }
    }
    _pendingRequests.clear();
  }

  /// Exponential backoff with jitter:
  /// T_retry = min(T_max, T_base * 2^attempt + rand(0, 1000ms))
  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    final base = AppConstants.baseRetryDelayMs;
    final expDelay = base * pow(2, min(_reconnectAttempts, 6)).toInt();
    final jitter = Random().nextInt(1000);
    final delayMs = min(AppConstants.maxRetryDelayMs, expDelay + jitter);

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      connect();
    });
  }

  /// Close the connection and stop reconnecting.
  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _teardown();
    _setState(
      isConfigured
          ? HaConnectionState.disconnected
          : HaConnectionState.notConfigured,
    );
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _itemsController.close();
  }
}
