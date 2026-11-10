import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal in-process Home Assistant WebSocket server for tests. Implements
/// auth, todo/item/subscribe (full snapshots), the todo add/update/remove
/// services and ping, following HA's message shapes.
class FakeHomeAssistant {
  final String token;
  final String entityId;
  final items = <Map<String, dynamic>>[];
  final serviceCalls = <Map<String, dynamic>>[];
  final _subscriptions = <WebSocket, int>{};
  final _sockets = <WebSocket>[];
  late HttpServer _server;
  int _nextUid = 1;

  FakeHomeAssistant({
    this.token = 'good-token',
    this.entityId = 'todo.shopping_list',
  });

  String get url => 'http://127.0.0.1:${_server.port}';
  int get connectionCount => _sockets.length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      if (request.uri.path != '/api/websocket') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(request);
      _sockets.add(ws);
      ws.add(jsonEncode({'type': 'auth_required', 'ha_version': '2026.10.0'}));
      ws.listen(
        (raw) => _handle(ws, jsonDecode(raw as String) as Map<String, dynamic>),
        onDone: () => _subscriptions.remove(ws),
      );
    });
  }

  Future<void> stop() async {
    for (final ws in _sockets) {
      await ws.close();
    }
    await _server.close(force: true);
  }

  /// Drop every open connection (simulates a network blip).
  Future<void> dropConnections() async {
    for (final ws in List.of(_sockets)) {
      await ws.close();
    }
    _subscriptions.clear();
  }

  // --- Changes made "in Home Assistant" by someone else ---

  String addRemote(String summary, {String status = 'needs_action'}) {
    final uid = 'uid-${_nextUid++}';
    items.add({'uid': uid, 'summary': summary, 'status': status});
    _broadcast();
    return uid;
  }

  void updateRemote(String uid, {String? summary, String? status}) {
    final item = items.firstWhere((i) => i['uid'] == uid);
    if (summary != null) item['summary'] = summary;
    if (status != null) item['status'] = status;
    _broadcast();
  }

  void removeRemote(String uid) {
    items.removeWhere((i) => i['uid'] == uid);
    _broadcast();
  }

  void _send(WebSocket ws, Map<String, dynamic> msg) => ws.add(jsonEncode(msg));

  void _result(WebSocket ws, int id, {bool success = true, String? error}) {
    _send(ws, {
      'id': id,
      'type': 'result',
      'success': success,
      'result': null,
      if (error != null)
        'error': {'code': 'service_validation_error', 'message': error},
    });
  }

  void _broadcast() {
    _subscriptions.forEach((ws, id) {
      _send(ws, {
        'id': id,
        'type': 'event',
        'event': {
          'items': items.map((i) => Map<String, dynamic>.from(i)).toList(),
        },
      });
    });
  }

  void _handle(WebSocket ws, Map<String, dynamic> msg) {
    final id = msg['id'] as int?;
    switch (msg['type']) {
      case 'auth':
        if (msg['access_token'] == token) {
          _send(ws, {'type': 'auth_ok', 'ha_version': '2026.10.0'});
        } else {
          _send(ws, {
            'type': 'auth_invalid',
            'message': 'Invalid access token or password',
          });
          ws.close();
        }
      case 'ping':
        _send(ws, {'id': id, 'type': 'pong'});
      case 'todo/item/subscribe':
        if (msg['entity_id'] != entityId) {
          _result(ws, id!, success: false, error: 'Entity not found');
          return;
        }
        _subscriptions[ws] = id!;
        _result(ws, id);
        _broadcast();
      case 'call_service':
        serviceCalls.add(msg);
        final data = Map<String, dynamic>.from(msg['service_data'] as Map);
        switch (msg['service']) {
          case 'add_item':
            items.add({
              'uid': 'uid-${_nextUid++}',
              'summary': data['item'],
              'status': 'needs_action',
            });
          case 'update_item':
            final match = items.where(
              (i) => i['uid'] == data['item'] || i['summary'] == data['item'],
            );
            if (match.isEmpty) {
              _result(
                ws,
                id!,
                success: false,
                error: 'Unable to find to-do list item',
              );
              return;
            }
            if (data.containsKey('description')) {
              // Like the built-in shopping list, which has no descriptions.
              _result(
                ws,
                id!,
                success: false,
                error: 'Entity does not support setting field: description',
              );
              return;
            }
            final item = match.first;
            if (data['rename'] != null) item['summary'] = data['rename'];
            if (data['status'] != null) item['status'] = data['status'];
          case 'remove_item':
            final uids = (data['item'] as List).cast<String>();
            items.removeWhere((i) => uids.contains(i['uid']));
        }
        _result(ws, id!);
        _broadcast();
    }
  }
}

/// Poll [condition] until it holds or [timeout] passes.
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 6),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
