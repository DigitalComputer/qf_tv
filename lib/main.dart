import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';

import 'models/models.dart';
import 'screens/display_picker_screen.dart';
import 'screens/display_screen.dart';
import 'services/services.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt', null);

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    fullScreen: true,
    backgroundColor: QueueTheme.bg,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'QueueFlow TV',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true);
  });

  runApp(const QfTvApp());
}

class QfTvApp extends StatelessWidget {
  const QfTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QueueFlow TV',
      debugShowCheckedModeBanner: false,
      theme: QueueTheme.theme,
      home: const _BootScreen(),
    );
  }
}

class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> {
  late Future<Widget> _home;

  @override
  void initState() {
    super.initState();
    _home = _resolveHome();
  }

  Future<Widget> _resolveHome() async {
    final session = await StorageService.getSession();
    final displayId = session['display_id'];
    final token = session['token'];
    final displayName = session['display_name'];
    final apiHost = session['api_host'];

    if (displayId == null || token == null || displayName == null) {
      return const DisplayPickerScreen();
    }

    final host = await ApiService.resolveTenantApiHost(
      preferred: apiHost,
      displayId: displayId,
    );
    final api = ApiService(host);

    try {
      final boot = await api.bootstrap(token);
      final resolvedHost = boot.apiHost.isNotEmpty
          ? await ApiService.resolveReachableHost(boot.apiHost)
          : host;
      return DisplayScreen(
        session: ActivateResult(
          displayId: boot.displayId.isNotEmpty ? boot.displayId : displayId,
          displayName: displayName,
          branchId: boot.branchId,
          templateId: boot.template.id,
          token: token,
          tenantId: boot.tenantId,
          apiHost: resolvedHost,
          reverb: boot.reverb,
        ),
      );
    } catch (_) {
      return DisplayScreen(
        session: ActivateResult(
          displayId: displayId,
          displayName: displayName,
          branchId: session['branch_id'] ?? '',
          templateId: session['template_id'] ?? '',
          token: token,
          tenantId: session['tenant_id'] ?? '',
          apiHost: host,
          reverb: ReverbConfig(
            key: '',
            host: 'localhost',
            port: 8080,
            scheme: 'http',
            useTls: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _home,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: QueueTheme.bg,
            body: Center(
              child: CircularProgressIndicator(color: QueueTheme.amber),
            ),
          );
        }
        return snap.data!;
      },
    );
  }
}
