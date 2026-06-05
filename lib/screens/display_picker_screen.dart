import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import 'display_screen.dart';

class DisplayPickerScreen extends StatefulWidget {
  const DisplayPickerScreen({super.key});

  @override
  State<DisplayPickerScreen> createState() => _DisplayPickerScreenState();
}

class _DisplayPickerScreenState extends State<DisplayPickerScreen> {
  static const _pollInterval = Duration(seconds: 15);

  List<TvDisplay> _displays = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _apiHost;
  String? _configHost;
  bool _activating = false;
  DateTime? _lastSync;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    ConfigService.apiHost().then((h) {
      if (mounted) setState(() => _configHost = h);
    });
    _refresh(showInitialSpinner: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _refresh(showInitialSpinner: false);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    super.dispose();
  }

  bool _handleKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isControlPressed) {
      _refresh(showInitialSpinner: false, manual: true);
      return true;
    }

    return false;
  }

  Future<List<TvDisplay>> _fetchDisplays() async {
    if (await ConfigService.usesCentralDiscovery()) {
      final central = await ConfigService.centralHost();
      if (central == null || central.isEmpty) {
        throw Exception('Central host não configurado');
      }
      final host = await ApiService.resolveReachableHost(central);
      _apiHost = host;
      return ApiService(host).getScreensFromCentral(host);
    }

    final host = await ApiService.resolveReachableHost();
    _apiHost = host;
    return ApiService(host).getDisplays();
  }

  Future<void> _refresh({required bool showInitialSpinner, bool manual = false}) async {
    if (_activating) return;

    if (mounted) {
      setState(() {
        if (showInitialSpinner && _displays.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        if (manual) _error = null;
      });
    }

    try {
      final list = await _fetchDisplays();
      if (!mounted) return;
      setState(() {
        _displays = list;
        _loading = false;
        _refreshing = false;
        _error = null;
        _lastSync = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_displays.isEmpty || manual) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  Future<void> _select(TvDisplay display) async {
    if (_activating) return;
    setState(() => _activating = true);

    try {
      final host = display.apiHost.isNotEmpty
          ? await ApiService.resolveReachableHost(display.apiHost)
          : await ApiService.resolveReachableHost();
      final api = ApiService(host);
      final result = await api.activate(display.id);
      final tenantHost = result.apiHost.isNotEmpty
          ? await ApiService.resolveReachableHost(result.apiHost)
          : host;
      final session = ActivateResult(
        displayId: result.displayId,
        displayName: result.displayName,
        branchId: result.branchId,
        templateId: result.templateId,
        token: result.token,
        tenantId: result.tenantId,
        apiHost: tenantHost,
        reverb: result.reverb,
      );
      await StorageService.saveSession(session);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DisplayScreen(session: session),
        ),
      );
    } catch (e) {
      setState(() {
        _activating = false;
        final detail = e.toString().replaceFirst('Exception: ', '');
        _error = detail.contains('HTTP') || detail.contains('Ecrã')
            ? detail
            : 'Falha ao activar ecrã';
      });
    }
  }

  String _syncLabel() {
    if (_refreshing) return 'A actualizar lista…';
    if (_lastSync == null) return 'Ctrl+R — actualizar agora';
    final time = DateFormat.Hm().format(_lastSync!);
    return '${_displays.length} ecrã(s) · actualizado $time · Ctrl+R';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QueueTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('QueueFlow TV',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: QueueTheme.textPrimary)),
                        const SizedBox(height: 8),
                        Text('Seleccione o ecrã desta sala',
                            style: QueueTheme.body.copyWith(fontSize: 18)),
                      ],
                    ),
                  ),
                  if (_refreshing)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: QueueTheme.amber,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _syncLabel(),
                style: QueueTheme.label.copyWith(
                  color: QueueTheme.textMuted,
                  fontSize: 13,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: QueueTheme.red)),
              ],
              const SizedBox(height: 32),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: QueueTheme.amber),
      );
    }

    if (_displays.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sem ligação ao servidor', style: QueueTheme.heading),
            const SizedBox(height: 12),
            Text(
              'A procurar ecrãs automaticamente a cada ${_pollInterval.inSeconds}s',
              style: QueueTheme.body.copyWith(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_apiHost != null)
              Text('API: $_apiHost', style: QueueTheme.body.copyWith(fontSize: 14))
            else if (_configHost != null)
              Text('Config: $_configHost',
                  style: QueueTheme.body.copyWith(fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: QueueTheme.label.copyWith(
                color: QueueTheme.textMuted,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _refresh(showInitialSpinner: true, manual: true),
              child: const Text('Tentar agora (Ctrl+R)'),
            ),
          ],
        ),
      );
    }

    if (_displays.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nenhum ecrã encontrado', style: QueueTheme.body),
            const SizedBox(height: 8),
            Text(
              'A procurar… Ctrl+R para actualizar',
              style: QueueTheme.label.copyWith(color: QueueTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.4,
      ),
      itemCount: _displays.length,
      itemBuilder: (_, i) => _DisplayCard(
        display: _displays[i],
        loading: _activating,
        onTap: () => _select(_displays[i]),
      ),
    );
  }
}

class _DisplayCard extends StatelessWidget {
  final TvDisplay display;
  final bool loading;
  final VoidCallback onTap;

  const _DisplayCard({
    required this.display,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: QueueTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: QueueTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(display.name,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: QueueTheme.textPrimary)),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: display.isOnline ? QueueTheme.green : QueueTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                display.tenantName.isNotEmpty
                    ? display.tenantName
                    : (display.description.isNotEmpty
                        ? display.description
                        : 'Sem descrição'),
                style: QueueTheme.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text('${display.activeTickets} tickets activos',
                  style: QueueTheme.label.copyWith(color: QueueTheme.blue)),
            ],
          ),
        ),
      ),
    );
  }
}
