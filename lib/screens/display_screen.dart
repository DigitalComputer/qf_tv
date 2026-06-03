import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../renderer/template_renderer.dart';
import '../services/announce_service.dart';
import '../services/reverb_service.dart';
import '../services/services.dart';
import '../theme.dart';
import 'display_picker_screen.dart';

class DisplayScreen extends StatefulWidget {
  final ActivateResult session;

  const DisplayScreen({super.key, required this.session});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  late ApiService _api;
  ReverbService? _reverb;
  final AnnounceService _announce = AnnounceService();
  DisplayTemplate _template = DisplayTemplate.fallback;
  QueueState _queueState = QueueState.empty('');
  ReverbConnectionState _reverbState = ReverbConnectionState.disconnected;
  bool _loading = true;
  String? _errorMessage;
  String? _lastAnnouncedCode;

  bool _ctrlPPressed = false;
  DateTime? _ctrlPAt;

  bool get _wsConnected => _reverbState == ReverbConnectionState.connected;

  @override
  void initState() {
    super.initState();
    _queueState = QueueState.empty(widget.session.displayName);
    HardwareKeyboard.instance.addHandler(_handleUnlockSequence);
    _announce.init();
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
    await _announce.stop();
    _reverb?.dispose();
    await StorageService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DisplayPickerScreen()),
    );
  }

  Future<void> _bootstrap() async {
    try {
      final host = await ApiService.resolveReachableHost(
        widget.session.apiHost.isNotEmpty ? widget.session.apiHost : null,
      );
      final api = ApiService(host);
      _api = api;

      final boot = await api.bootstrap(widget.session.token);
      if (!mounted) return;
      setState(() {
        _template = boot.template;
        _queueState = boot.queue;
        _errorMessage = null;
      });

      await _refreshQueue();
      _maybeAnnounce(_queueState.nowCalling);

      _reverb = ReverbService(
        config: boot.reverb,
        tenantId: boot.tenantId,
        branchId: boot.branchId,
        onEvent: (_) => _refreshQueue(),
        onStateChange: (state) {
          if (mounted) setState(() => _reverbState = state);
        },
      );
      _reverb!.connect();
    } catch (e, st) {
      debugPrint('qf_tv bootstrap failed: $e\n$st');
      if (mounted) {
        setState(() {
          _reverbState = ReverbConnectionState.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshQueue() async {
    try {
      final state = await _api.getQueue(
        widget.session.displayId,
        widget.session.token,
      );
      if (!mounted) return;
      setState(() {
        _queueState = state;
        _errorMessage = null;
      });
      _maybeAnnounce(state.nowCalling);
    } catch (e, st) {
      debugPrint('qf_tv queue refresh failed: $e\n$st');
      if (mounted) {
        setState(() {
          _reverbState = ReverbConnectionState.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _maybeAnnounce(QueueTicket? ticket) {
    if (ticket == null) return;
    final code = ticket.ticketCode;
    if (code.isEmpty || code == _lastAnnouncedCode) return;
    _lastAnnouncedCode = code;
    _announce.announceTicket(
      code,
      counterLabel: AnnounceService.counterPhrase(ticket.counterName),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: QueueTheme.bg,
        body: Center(
          child: CircularProgressIndicator(color: QueueTheme.amber),
        ),
      );
    }

    return Scaffold(
      backgroundColor: QueueTheme.bg,
      body: Stack(
        children: [
          TemplateRenderer(
            template: _template,
            queueState: _queueState,
            wsConnected: _wsConnected,
          ),
          if (_errorMessage != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 16,
              child: Material(
                color: QueueTheme.red.withOpacity(0.15),
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
    HardwareKeyboard.instance.removeHandler(_handleUnlockSequence);
    _announce.stop();
    _reverb?.dispose();
    super.dispose();
  }
}
