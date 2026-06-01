import 'dart:ui';

// ── Display (picker) ──────────────────────────────────────────

class TvDisplay {
  final String id;
  final String name;
  final String description;
  final int activeTickets;
  final bool isOnline;
  final String? templateId;

  TvDisplay({
    required this.id,
    required this.name,
    required this.description,
    required this.activeTickets,
    required this.isOnline,
    this.templateId,
  });

  factory TvDisplay.fromJson(Map<String, dynamic> j) => TvDisplay(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        activeTickets: j['active_tickets'] ?? 0,
        isOnline: j['is_online'] ?? false,
        templateId: j['template_id'],
      );
}

// ── Queue ─────────────────────────────────────────────────────

class QueueTicket {
  final String ticketCode;
  final String serviceType;
  final String counterName;
  final String status;

  QueueTicket({
    required this.ticketCode,
    required this.serviceType,
    required this.counterName,
    required this.status,
  });

  factory QueueTicket.fromJson(Map<String, dynamic> j) => QueueTicket(
        ticketCode: j['ticket_code'] ?? '',
        serviceType: j['service_type'] ?? '',
        counterName: j['counter_name'] ?? '',
        status: j['status'] ?? 'waiting',
      );
}

class QueueState {
  final QueueTicket? nowCalling;
  final List<QueueTicket> nowServing;
  final List<QueueTicket> waitingNext;
  final int totalWaiting;
  final String roomName;
  final DateTime updatedAt;

  QueueState({
    this.nowCalling,
    required this.nowServing,
    required this.waitingNext,
    required this.totalWaiting,
    required this.roomName,
    required this.updatedAt,
  });

  factory QueueState.empty(String roomName) => QueueState(
        nowServing: [],
        waitingNext: [],
        totalWaiting: 0,
        roomName: roomName,
        updatedAt: DateTime.now(),
      );

  factory QueueState.fromJson(Map<String, dynamic> j) => QueueState(
        nowCalling: j['now_calling'] != null
            ? QueueTicket.fromJson(j['now_calling'])
            : null,
        nowServing: (j['now_serving'] as List? ?? [])
            .map((e) => QueueTicket.fromJson(e))
            .toList(),
        waitingNext: (j['waiting_next'] as List? ?? [])
            .map((e) => QueueTicket.fromJson(e))
            .toList(),
        totalWaiting: j['total_waiting'] ?? 0,
        roomName: j['room_name'] ?? '',
        updatedAt: DateTime.tryParse(j['updated_at'] ?? '') ?? DateTime.now(),
      );
}

// ── Reverb config ─────────────────────────────────────────────

class ReverbConfig {
  final String key;
  final String host;
  final int port;
  final String scheme;
  final bool useTls;

  ReverbConfig({
    required this.key,
    required this.host,
    required this.port,
    required this.scheme,
    required this.useTls,
  });

  factory ReverbConfig.fromJson(Map<String, dynamic> j) => ReverbConfig(
        key: j['key']?.toString() ?? '',
        host: j['host']?.toString() ?? 'localhost',
        port: (j['port'] as num?)?.toInt() ?? 8080,
        scheme: j['scheme']?.toString() ?? 'http',
        useTls: j['use_tls'] == true || j['scheme'] == 'https',
      );
}

class ActivateResult {
  final String displayId;
  final String displayName;
  final String branchId;
  final String templateId;
  final String token;
  final String tenantId;
  final ReverbConfig reverb;

  ActivateResult({
    required this.displayId,
    required this.displayName,
    required this.branchId,
    required this.templateId,
    required this.token,
    required this.tenantId,
    required this.reverb,
  });

  factory ActivateResult.fromJson(Map<String, dynamic> j) => ActivateResult(
        displayId: j['display_id'] ?? '',
        displayName: j['display_name'] ?? '',
        branchId: j['branch_id'] ?? '',
        templateId: j['template_id'] ?? '',
        token: j['token'] ?? '',
        tenantId: j['tenant_id']?.toString() ?? '',
        reverb: ReverbConfig.fromJson(j['reverb'] ?? {}),
      );
}

// ── Template ──────────────────────────────────────────────────

class TemplateBackground {
  final Color color;
  final String pattern;

  TemplateBackground({required this.color, required this.pattern});

  factory TemplateBackground.fromJson(Map<String, dynamic> j) =>
      TemplateBackground(
        color: _hexColor(j['color'], const Color(0xFF080C14)),
        pattern: j['pattern'] ?? 'dots',
      );

  static TemplateBackground get defaults =>
      TemplateBackground(color: const Color(0xFF080C14), pattern: 'dots');
}

class TemplateTopBar {
  final bool show;
  final bool showClock;
  final bool showTotal;
  final bool showRoomName;
  final bool showStatus;
  final Color backgroundColor;

  TemplateTopBar({
    required this.show,
    required this.showClock,
    required this.showTotal,
    required this.showRoomName,
    required this.showStatus,
    required this.backgroundColor,
  });

  factory TemplateTopBar.fromJson(Map<String, dynamic> j) => TemplateTopBar(
        show: j['show'] ?? true,
        showClock: j['showClock'] ?? true,
        showTotal: j['showTotal'] ?? true,
        showRoomName: j['showRoomName'] ?? true,
        showStatus: j['showStatus'] ?? true,
        backgroundColor:
            _hexColor(j['backgroundColor'], const Color(0xFF0D1420)),
      );

  static TemplateTopBar get defaults => TemplateTopBar(
        show: true,
        showClock: true,
        showTotal: true,
        showRoomName: true,
        showStatus: true,
        backgroundColor: const Color(0xFF0D1420),
      );
}

class TemplateLayout {
  final String type;
  final double sideWidth;
  final double sideHeight;

  TemplateLayout({
    required this.type,
    required this.sideWidth,
    required this.sideHeight,
  });

  factory TemplateLayout.fromJson(Map<String, dynamic> j) => TemplateLayout(
        type: j['type'] ?? 'split_vertical',
        sideWidth: (j['sideWidth'] as num?)?.toDouble() ?? 360,
        sideHeight: (j['sideHeight'] as num?)?.toDouble() ?? 220,
      );

  static TemplateLayout get defaults =>
      TemplateLayout(type: 'split_vertical', sideWidth: 360, sideHeight: 220);
}

class ZoneStyle {
  final Color? backgroundColor;
  final Color accentColor;
  final Color textColor;
  final double ticketFontSize;
  final bool showLabel;
  final bool showCounter;
  final bool showService;
  final bool glowEffect;
  final bool flashOnCall;
  final int maxItems;
  final bool showPosition;
  final bool dim;
  final double fontSize;
  final String alignment;

  ZoneStyle({
    this.backgroundColor,
    required this.accentColor,
    required this.textColor,
    required this.ticketFontSize,
    required this.showLabel,
    required this.showCounter,
    required this.showService,
    required this.glowEffect,
    required this.flashOnCall,
    required this.maxItems,
    required this.showPosition,
    required this.dim,
    required this.fontSize,
    required this.alignment,
  });

  factory ZoneStyle.fromJson(Map<String, dynamic> j) => ZoneStyle(
        backgroundColor: j['backgroundColor'] != null
            ? _hexColor(j['backgroundColor'], const Color(0xFF080C14))
            : null,
        accentColor: _hexColor(j['accentColor'], const Color(0xFFF5A623)),
        textColor: _hexColor(j['textColor'], const Color(0xFFF0F4F8)),
        ticketFontSize: (j['ticketFontSize'] as num?)?.toDouble() ?? 96,
        showLabel: j['showLabel'] ?? true,
        showCounter: j['showCounter'] ?? true,
        showService: j['showService'] ?? true,
        glowEffect: j['glowEffect'] ?? true,
        flashOnCall: j['flashOnCall'] ?? true,
        maxItems: j['maxItems'] ?? 6,
        showPosition: j['showPosition'] ?? false,
        dim: j['dim'] ?? false,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 22,
        alignment: j['alignment'] ?? 'center',
      );

  static ZoneStyle get defaults => ZoneStyle(
        accentColor: const Color(0xFFF5A623),
        textColor: const Color(0xFFF0F4F8),
        ticketFontSize: 96,
        showLabel: true,
        showCounter: true,
        showService: true,
        glowEffect: true,
        flashOnCall: true,
        maxItems: 6,
        showPosition: false,
        dim: false,
        fontSize: 22,
        alignment: 'center',
      );
}

class TemplateZone {
  final String id;
  final String slot;
  final String type;
  final String label;
  final ZoneStyle style;

  TemplateZone({
    required this.id,
    required this.slot,
    required this.type,
    required this.label,
    required this.style,
  });

  factory TemplateZone.fromJson(Map<String, dynamic> j) => TemplateZone(
        id: j['id'] ?? '',
        slot: j['slot'] ?? 'main',
        type: j['type'] ?? 'calling',
        label: j['label'] ?? '',
        style: j['style'] != null
            ? ZoneStyle.fromJson(j['style'])
            : ZoneStyle.defaults,
      );
}

class DisplayTemplate {
  final String id;
  final String name;
  final int version;
  final TemplateBackground background;
  final TemplateTopBar topBar;
  final TemplateLayout layout;
  final List<TemplateZone> zones;

  DisplayTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.background,
    required this.topBar,
    required this.layout,
    required this.zones,
  });

  factory DisplayTemplate.fromJson(Map<String, dynamic> j) => DisplayTemplate(
        id: j['id'] ?? 'default',
        name: j['name'] ?? 'Default',
        version: j['version'] ?? 1,
        background: j['background'] != null
            ? TemplateBackground.fromJson(j['background'])
            : TemplateBackground.defaults,
        topBar: j['topBar'] != null
            ? TemplateTopBar.fromJson(j['topBar'])
            : TemplateTopBar.defaults,
        layout: j['layout'] != null
            ? TemplateLayout.fromJson(j['layout'])
            : TemplateLayout.defaults,
        zones: (j['zones'] as List? ?? [])
            .map((z) => TemplateZone.fromJson(z))
            .toList(),
      );

  TemplateZone? zoneBySlot(String slot) {
    for (final z in zones) {
      if (z.slot == slot) return z;
    }
    return null;
  }

  static DisplayTemplate get fallback => DisplayTemplate(
        id: 'fallback',
        name: 'Fallback',
        version: 1,
        background: TemplateBackground.defaults,
        topBar: TemplateTopBar.defaults,
        layout: TemplateLayout.defaults,
        zones: [
          TemplateZone(
            id: 'main',
            slot: 'main',
            type: 'calling',
            label: 'A CHAMAR',
            style: ZoneStyle.defaults,
          ),
          TemplateZone(
            id: 'serving',
            slot: 'side_top',
            type: 'serving_list',
            label: 'EM ATENDIMENTO',
            style: ZoneStyle.fromJson({'accentColor': '#1A8FFF'}),
          ),
          TemplateZone(
            id: 'next',
            slot: 'side_bottom',
            type: 'waiting_list',
            label: 'PRÓXIMOS',
            style: ZoneStyle.fromJson({'dim': true, 'showPosition': true}),
          ),
        ],
      );
}

Color _hexColor(dynamic hex, Color fallback) {
  if (hex == null) return fallback;
  try {
    final s = hex.toString().replaceFirst('#', '');
    return Color(int.parse('FF$s', radix: 16));
  } catch (_) {
    return fallback;
  }
}
