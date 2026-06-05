import 'dart:async';
import 'dart:convert';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

typedef ReverbEventCallback = void Function(Map<String, dynamic>? payload);

enum ReverbConnectionState { disconnected, connecting, connected, error }

/// Laravel Reverb — branch calls + branch queues channels.
class ReverbService {
  ReverbService({
    required this.config,
    required this.tenantId,
    required this.branchId,
    required this.onEvent,
    required this.onStateChange,
  });

  final ReverbConfig config;
  final String tenantId;
  final String branchId;
  final ReverbEventCallback onEvent;
  final void Function(ReverbConnectionState state) onStateChange;

  PusherChannelsClient? _client;
  StreamSubscription? _connectedSub;
  final List<StreamSubscription> _eventSubs = [];
  Timer? _pollTimer;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  static const _pollInterval = Duration(seconds: 3);
  static const _connectedPollInterval = Duration(seconds: 8);

  String get _callsChannel => 'tenant.$tenantId.branch.$branchId.calls';
  String get _queuesChannel => 'tenant.$tenantId.branch.$branchId.queues';

  void connect() {
    if (_disposed || tenantId.isEmpty || branchId.isEmpty || config.key.isEmpty) {
      _startPollFallback();
      return;
    }

    _connectWebSocket();
  }

  void _connectWebSocket() {
    _disposeClient(keepPoll: true);
    onStateChange(ReverbConnectionState.connecting);

    final scheme = config.useTls ? 'wss' : 'ws';
    final hostOptions = PusherChannelsOptions.fromHost(
      scheme: scheme,
      host: config.host,
      key: config.key,
      port: config.port,
      shouldSupplyMetadataQueries: true,
      metadata: PusherChannelsOptionsMetadata.byDefault(),
    );

    final client = PusherChannelsClient.websocket(
      options: hostOptions,
      connectionErrorHandler: (exception, trace, refresh) {
        debugPrint('qf_tv Reverb error: $exception');
        onStateChange(ReverbConnectionState.error);
        _startPollFallback();
        _scheduleReconnect(refresh);
      },
    );

    _client = client;
    final calls = client.publicChannel(_callsChannel);
    final queues = client.publicChannel(_queuesChannel);

    void bind(Channel channel, String event) {
      _eventSubs.add(channel.bind(event).listen((e) => _emitPayload(e.data)));
    }

    void bindAny(Channel channel, List<String> events) {
      for (final event in events) {
        bind(channel, event);
      }
    }

    bindAny(calls, ['ticket.called', 'ticket.issued', 'ticket.served', 'ticket.completed']);
    bindAny(queues, ['QueueUpdated', 'queue.updated']);

    _connectedSub = client.onConnectionEstablished.listen((_) {
      _reconnectAttempt = 0;
      onStateChange(ReverbConnectionState.connected);
      calls.subscribe();
      queues.subscribe();
      _startConnectedPoll();
      debugPrint('qf_tv Reverb connected — $_callsChannel + $_queuesChannel');
    });

    client.connect();
  }

  void _emitPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        onEvent(decoded);
      } else if (decoded is Map) {
        onEvent(Map<String, dynamic>.from(decoded));
      } else {
        onEvent(null);
      }
    } catch (_) {
      onEvent(null);
    }
  }

  void _scheduleReconnect(void Function() refresh) {
    if (_disposed) return;
    final delay = Duration(seconds: (2 << _reconnectAttempt.clamp(0, 4)).clamp(2, 32));
    _reconnectAttempt++;
    Future.delayed(delay, () {
      if (!_disposed) refresh();
    });
  }

  void _startPollFallback() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) onEvent(null);
    });
  }

  /// Safety net while WS connected — issue/call events can be missed or race HTTP refresh.
  void _startConnectedPoll() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_connectedPollInterval, (_) {
      if (!_disposed) onEvent(null);
    });
  }

  void _disposeClient({bool keepPoll = false}) {
    _connectedSub?.cancel();
    _connectedSub = null;
    for (final sub in _eventSubs) {
      sub.cancel();
    }
    _eventSubs.clear();
    try {
      _client?.dispose();
    } catch (_) {}
    _client = null;
    if (!keepPoll && !_disposed) {
      onStateChange(ReverbConnectionState.disconnected);
    }
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _disposeClient();
    onStateChange(ReverbConnectionState.disconnected);
  }
}
