import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../renderer/template_renderer.dart';
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
  DisplayTemplate _template = DisplayTemplate.fallback;
  QueueState _queueState = QueueState.empty('');
  bool _connected = false;
  bool _loading = true;

  bool _ctrlPPressed = false;
  DateTime? _ctrlPAt;

  @override
  void initState() {
    super.initState();
    _queueState = QueueState.empty(widget.session.displayName);
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
      _api = ApiService(host);

      final boot = await _api.bootstrap(widget.session.token);
      _template = boot.template;
      _queueState = boot.queue;

      _reverb = ReverbService(
        config: boot.reverb,
        tenantId: boot.tenantId,
        branchId: boot.branchId,
        onEvent: _refreshQueue,
        onConnectionChange: (c) {
          if (mounted) setState(() => _connected = c);
        },
      );
      _reverb!.connect();
    } catch (_) {
      try {
        _template = await _api.getTemplate(widget.session.templateId);
        _queueState = await _api.getQueue(
          widget.session.displayId,
          widget.session.token,
        );
        _connected = false;
      } catch (_) {
        _connected = false;
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
      if (mounted) setState(() => _queueState = state);
    } catch (_) {
      if (mounted) setState(() => _connected = false);
    }
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
      body: TemplateRenderer(
        template: _template,
        queueState: _queueState,
        wsConnected: _connected,
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleUnlockSequence);
    _reverb?.dispose();
    super.dispose();
  }
}
