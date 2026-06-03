import 'dart:async';
import 'dart:convert';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

typedef ReverbEventCallback = void Function(Map<String, dynamic>? payload);

enum ReverbConnectionState { disconnected, connecting, connected, error }

/// Laravel Reverb client — public channel `tenant.{id}.branch.{id}.calls`.
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
  StreamSubscription? _eventSub;
  Timer? _pollTimer;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  static const _pollInterval = Duration(seconds: 3);
  static const _channelEvent = 'ticket.called';

  String get _channelName => 'tenant.$tenantId.branch.$branchId.calls';

  bool get isConnected => _client != null && !_disposed;

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
    final channel = client.publicChannel(_channelName);

    _connectedSub = client.onConnectionEstablished.listen((_) {
      _reconnectAttempt = 0;
      _pollTimer?.cancel();
      onStateChange(ReverbConnectionState.connected);
      channel.subscribe();
      debugPrint('qf_tv Reverb connected — $_channelName');
    });

    _eventSub = channel.bind(_channelEvent).listen((event) {
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(event.data);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        } else if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        payload = null;
      }
      onEvent(payload);
    });

    client.connect();
  }

  void _scheduleReconnect(void Function() refresh) {
    if (_disposed) return;
    final delay = Duration(seconds: (2 << _reconnectAttempt.clamp(0, 4)).clamp(2, 32));
    _reconnectAttempt++;
    Future.delayed(delay, () {
      if (!_disposed) {
        refresh();
      }
    });
  }

  void _startPollFallback() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) onEvent(null);
    });
  }

  void _disposeClient({bool keepPoll = false}) {
    _connectedSub?.cancel();
    _eventSub?.cancel();
    _connectedSub = null;
    _eventSub = null;
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
