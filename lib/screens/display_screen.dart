import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layouts/web_display_layout.dart';
import '../models/models.dart';
import '../services/announce_service.dart';
import '../services/reverb_service.dart';
import '../services/services.dart';
import '../theme.dart';
import 'display_picker_screen.dart';

/// Display screen — same data flow as qf_screen (config + state + Reverb + API TTS).
class DisplayScreen extends StatefulWidget {
  final ActivateResult session;

  const DisplayScreen({super.key, required this.session});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  late ApiService _api;
  late String _token;
  AnnounceService? _announce;
  ReverbService? _reverb;

  DisplayConfig? _config;
  String? _displayCode;
  String? _serviceName;
  String? _counterName;
  bool _isCalling = false;
  List<QueueTicket> _waiting = [];
  List<QueueTicket> _serving = [];
  int _totalWaiting = 0;

  ReverbConnectionState _reverbState = ReverbConnectionState.disconnected;
  bool _connected = false;
  bool _loading = true;
  String? _errorMessage;
  String? _lastAnnouncedCode;
  int _refreshGeneration = 0;
  Timer? _refreshDebounce;
  Timer? _pollTimer;

  bool _ctrlPPressed = false;
  DateTime? _ctrlPAt;

  bool get _wsConnected => _reverbState == ReverbConnectionState.connected;

  @override
  void initState() {
    super.initState();
    _token = widget.session.token;
    HardwareKeyboard.instance.addHandler(_handleUnlockSequence);
    _bootstrap();
  }

  bool _handleUnlockSequence(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyP &&
        HardwareKeyboard.instance.isControlPressed) {
      _ctrlPPressed = true;
      _ctrlPAt = DateTime.now();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyP &&
        HardwareKeyboard.instance.isAltPressed &&
        _ctrlPPressed &&
        _ctrlPAt != null &&
        DateTime.now().difference(_ctrlPAt!) < const Duration(seconds: 2)) {
      _goToPicker();
      return true;
    }

    if (_ctrlPAt != null &&
        DateTime.now().difference(_ctrlPAt!) > const Duration(seconds: 2)) {
      _ctrlPPressed = false;
      _ctrlPAt = null;
    }

    return false;
  }

  Future<void> _goToPicker() async {
    _pollTimer?.cancel();
    await _announce?.dispose();
    _reverb?.dispose();
    await StorageService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DisplayPickerScreen()),
    );
  }

  Future<void> _bootstrap() async {
    try {
      final host = await ApiService.resolveTenantApiHost(
        preferred: widget.session.apiHost.isNotEmpty ? widget.session.apiHost : null,
        displayId: widget.session.displayId,
      );
      final api = ApiService(host);
      _api = api;
      _announce = AnnounceService(api: api, token: _token);
      await _announce!.init();

      final config = await api.getDisplayConfig(_token);
      final state = await api.getDisplayState(_token);

      if (!mounted) return;

      _applyState(state);
      setState(() {
        _config = config;
        _connected = true;
        _errorMessage = null;
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshState());

      final branchIds = config.effectiveBranchIds.isNotEmpty
          ? config.effectiveBranchIds
          : widget.session.effectiveBranchIds;

      _reverb = ReverbService(
        config: config.reverb.key.isNotEmpty ? config.reverb : widget.session.reverb,
        tenantId: config.tenantId.isNotEmpty ? config.tenantId : widget.session.tenantId,
        branchIds: branchIds,
        onEvent: _handleReverbEvent,
        onStateChange: (state) {
          if (mounted) setState(() => _reverbState = state);
        },
      );
      _reverb!.connect();
    } catch (e, st) {
      debugPrint('qf_tv bootstrap failed: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _handleReverbEvent(String event, Map<String, dynamic>? payload) {
    if (event == 'ticket.called' && payload != null) {
      final code = payload['display_code']?.toString() ??
          payload['ticket_number']?.toString() ??
          '';
      final svc = payload['service_name']?.toString() ?? '';
      final ctr = payload['counter_name']?.toString();
      final ctrNum = AnnounceService.counterNumberFromPayload(payload);

      if (mounted) {
        setState(() {
          _displayCode = code.isNotEmpty ? code : _displayCode;
          _serviceName = svc.isNotEmpty ? svc : _serviceName;
          _counterName = ctr != null && ctr.isNotEmpty && ctr != 'Guichet' ? ctr : _counterName;
          _isCalling = code.isNotEmpty;
          _connected = true;
        });
      }

      if (code.isNotEmpty && (_config?.ttsEnabled ?? true)) {
        _announceTicket(code, counterNumber: ctrNum, counterName: ctr);
      }
    } else if (event == 'ticket.served' || event == 'ticket.completed') {
      if (mounted) setState(() => _isCalling = false);
    }

    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _refreshState();
    });
  }

  Future<void> _refreshState() async {
    final generation = ++_refreshGeneration;
    try {
      final state = await _api.getDisplayState(_token);
      if (!mounted || generation != _refreshGeneration) return;

      final prevCalling = _displayCode;
      _applyState(state);

      setState(() {
        _connected = true;
        _errorMessage = null;
      });

      final calling = state.nowCalling;
      if (calling != null &&
          calling.ticketCode.isNotEmpty &&
          calling.ticketCode != prevCalling &&
          calling.ticketCode != _lastAnnouncedCode &&
          (_config?.ttsEnabled ?? true)) {
        _announceTicket(
          calling.ticketCode,
          counterNumber: AnnounceService.counterNumberFromName(calling.counterName),
          counterName: calling.counterName,
        );
      }
    } catch (e, st) {
      debugPrint('qf_tv state refresh failed: $e\n$st');
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _connected = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applyState(DisplayState state) {
    final calling = state.nowCalling;
    if (calling != null) {
      _displayCode = calling.ticketCode;
      _serviceName = calling.serviceType;
      _counterName = calling.counterName.isNotEmpty && calling.counterName != 'Guichet'
          ? calling.counterName
          : null;
      _isCalling = true;
    } else {
      _displayCode = null;
      _serviceName = null;
      _counterName = null;
      _isCalling = false;
    }
    _waiting = state.waitingNext;
    _serving = state.nowServing;
    _totalWaiting = state.totalWaiting;
  }

  void _announceTicket(
    String code, {
    int? counterNumber,
    String? counterName,
  }) {
    if (code.isEmpty || code == _lastAnnouncedCode) return;
    _lastAnnouncedCode = code;
    _announce?.announceTicket(
      code,
      counterNumber: counterNumber,
      counterLabel: AnnounceService.counterPhrase(counterName),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Scaffold(
        backgroundColor: QueueTheme.bg,
        body: Center(
          child: CircularProgressIndicator(color: QueueTheme.amber),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          WebDisplayLayout(
            config: _config!,
            displayCode: _displayCode,
            serviceName: _serviceName,
            counterName: _counterName,
            isCalling: _isCalling,
            waiting: _waiting,
            serving: _serving,
            totalWaiting: _totalWaiting,
            connected: _connected,
            wsConnected: _wsConnected,
          ),
          if (_errorMessage != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 72,
              child: Material(
                color: QueueTheme.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: QueueTheme.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleUnlockSequence);
    _announce?.dispose();
    _reverb?.dispose();
    super.dispose();
  }
}
