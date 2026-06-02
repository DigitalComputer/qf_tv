import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  late Future<List<TvDisplay>> _future;
  String? _error;
  String? _apiHost;
  String? _configHost;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    ConfigService.apiHost().then((h) {
      if (mounted) setState(() => _configHost = h);
    });
    _future = _loadDisplays();
  }

  Future<List<TvDisplay>> _loadDisplays() async {
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

  Future<void> _select(TvDisplay display) async {
    if (_activating) return;
    setState(() => _activating = true);

    try {
      final host = display.apiHost.isNotEmpty
          ? await ApiService.resolveReachableHost(display.apiHost)
          : await ApiService.resolveReachableHost();
      final api = ApiService(host);
      final result = await api.activate(display.id);
      final session = ActivateResult(
        displayId: result.displayId,
        displayName: result.displayName,
        branchId: result.branchId,
        templateId: result.templateId,
        token: result.token,
        tenantId: result.tenantId,
        apiHost: host,
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
        _error = 'Falha ao activar ecrã';
      });
    }
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
              Text('QueueFlow TV',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: QueueTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Seleccione o ecrã desta sala',
                  style: QueueTheme.body.copyWith(fontSize: 18)),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: QueueTheme.red)),
              ],
              const SizedBox(height: 32),
              Expanded(
                child: FutureBuilder<List<TvDisplay>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: QueueTheme.amber));
                    }
                    if (snap.hasError) {
                      final detail = snap.error.toString();
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Sem ligação ao servidor',
                                style: QueueTheme.heading),
                            const SizedBox(height: 12),
                            Text(
                              'Ping OK mas lista de ecrãs falhou — verifique API em 168',
                              style: QueueTheme.body.copyWith(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            if (_apiHost != null)
                              Text('API: $_apiHost',
                                  style: QueueTheme.body.copyWith(fontSize: 14))
                            else if (_configHost != null)
                              Text('Config: $_configHost',
                                  style: QueueTheme.body.copyWith(fontSize: 14)),
                            const SizedBox(height: 8),
                            Text(detail,
                                style: QueueTheme.label.copyWith(
                                  color: QueueTheme.textMuted,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _error = null;
                                ConfigService.clearCache();
                                _future = _loadDisplays();
                              }),
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      );
                    }

                    final displays = snap.data ?? [];
                    if (displays.isEmpty) {
                      return Center(
                        child: Text('Nenhum ecrã activo',
                            style: QueueTheme.body),
                      );
                    }

                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: displays.length,
                      itemBuilder: (_, i) => _DisplayCard(
                        display: displays[i],
                        loading: _activating,
                        onTap: () => _select(displays[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
