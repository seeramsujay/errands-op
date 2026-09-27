import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants.dart';
import '../models/todo_item.dart';

enum HaConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  mockConnected,
  error,
}

/// Home Assistant WebSocket API client over /api/websocket
class HomeAssistantWsClient {
  final String host;
  final int port;
  final String accessToken;
  final String entityId;
  final bool useSsl;
  final bool mockMode;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _messageId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};

  HaConnectionState _state = HaConnectionState.disconnected;
  final _stateController = StreamController<HaConnectionState>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  HomeAssistantWsClient({
    this.host = '127.0.0.1',
    this.port = AppConstants.defaultWsPort,
    this.accessToken = '',
    this.entityId = AppConstants.defaultHaEntityId,
    this.useSsl = false,
    this.mockMode = true, // Defaults to mock mode for out-of-the-box zero-setup testability
  });

  HaConnectionState get state => _state;
  Stream<HaConnectionState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void _setState(HaConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Connect to Home Assistant WebSocket
  Future<void> connect() async {
    if (mockMode) {
      _setState(HaConnectionState.mockConnected);
      return;
    }

    if (_state == HaConnectionState.connecting ||
        _state == HaConnectionState.connected ||
        _state == HaConnectionState.authenticating) {
      return;
    }

    _setState(HaConnectionState.connecting);
    final scheme = useSsl ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://$host:$port/api/websocket');

    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: _onError,
        onDone: _onDisconnected,
      );
    } catch (e) {
      _onError(e);
    }
  }

  void _onMessageReceived(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'auth_required') {
        _setState(HaConnectionState.authenticating);
        _sendRaw({'type': 'auth', 'access_token': accessToken});
        return;
      }

      if (type == 'auth_ok') {
        _reconnectAttempts = 0;
        _setState(HaConnectionState.connected);
        _subscribeToTodo();
        return;
      }

      if (type == 'auth_invalid') {
        _setState(HaConnectionState.error);
        disconnect();
        return;
      }

      // Check request responses
      final id = data['id'] as int?;
      if (id != null && _pendingRequests.containsKey(id)) {
        _pendingRequests.remove(id)!.complete(data);
      }

      // Handle subscription events
      if (type == 'event') {
        _eventController.add(data['event'] as Map<String, dynamic>);
      }
    } catch (e) {
      // JSON decode or parse failure
    }
  }

  void _subscribeToTodo() {
    sendMessage({
      'type': 'todo/item/subscribe',
      'entity_id': entityId,
    });
  }

  /// Send message and optionally await response
  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> payload) {
    if (mockMode) {
      return Future.value({'success': true, 'id': _messageId++});
    }

    final id = _messageId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final fullPayload = Map<String, dynamic>.from(payload)..['id'] = id;
    _sendRaw(fullPayload);

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingRequests.remove(id);
        return {'success': false, 'error': 'timeout'};
      },
    );
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// Sync local mutation to Home Assistant
  Future<bool> sendTodoUpdate({
    required String itemId,
    required String summary,
    required String status,
    String? description,
  }) async {
    if (mockMode) return true;

    final res = await sendMessage({
      'type': 'call_service',
      'domain': 'todo',
      'service': 'update_item',
      'service_data': {
        'entity_id': entityId,
        'item': itemId,
        'rename': summary,
        'status': status,
        if (description != null) 'description': description,
      },
    });

    return res['success'] == true;
  }

  Future<bool> sendTodoAdd({
    required String summary,
    String? description,
  }) async {
    if (mockMode) return true;

    final res = await sendMessage({
      'type': 'call_service',
      'domain': 'todo',
      'service': 'add_item',
      'service_data': {
        'entity_id': entityId,
        'item': summary,
        if (description != null) 'description': description,
      },
    });

    return res['success'] == true;
  }

  Future<bool> sendTodoRemove({required String itemId}) async {
    if (mockMode) return true;

    final res = await sendMessage({
      'type': 'call_service',
      'domain': 'todo',
      'service': 'remove_item',
      'service_data': {
        'entity_id': entityId,
        'item': [itemId],
      },
    });

    return res['success'] == true;
  }

  void _onError(dynamic error) {
    _setState(HaConnectionState.error);
    _scheduleReconnect();
  }

  void _onDisconnected() {
    _setState(HaConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// Exponential backoff with jitter:
  /// T_retry = min(T_max, T_base * 2^attempt + rand(0, 1000ms))
  void _scheduleReconnect() {
    if (mockMode) return;
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

  /// Simulate incoming Home Assistant item event (for testing & mock mode)
  void simulateIncomingRemoteItem({
    required String summary,
    String category = 'groceries',
    bool isPerishable = false,
  }) {
    final event = {
      'type': 'todo_update',
      'action': 'add',
      'item': {
        'id': 'remote_${DateTime.now().millisecondsSinceEpoch}',
        'summary': summary,
        'category': category,
        'is_perishable': isPerishable,
        'status': 'needs_action',
      },
    };
    _eventController.add(event);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(HaConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _eventController.close();
  }
}
