import 'dart:ui';

// ── Branch (multi-unidade picker) ─────────────────────────────

class TvBranch {
  final String id;
  final String name;
  final String address;
  final List<String> serviceCodes;

  TvBranch({
    required this.id,
    required this.name,
    this.address = '',
    this.serviceCodes = const [],
  });

  factory TvBranch.fromJson(Map<String, dynamic> j) => TvBranch(
        id: j['id']?.toString() ?? '',
        name: j['name'] ?? '',
        address: j['address']?.toString() ?? '',
        serviceCodes: (j['service_codes'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

// ── Display (picker) ──────────────────────────────────────────

class TvDisplay {
  final String id;
  final String name;
  final String description;
  final int activeTickets;
  final bool isOnline;
  final String? templateId;
  final String apiHost;
  final String tenantName;

  TvDisplay({
    required this.id,
    required this.name,
    required this.description,
    required this.activeTickets,
    required this.isOnline,
    this.templateId,
    this.apiHost = '',
    this.tenantName = '',
  });

  factory TvDisplay.fromJson(Map<String, dynamic> j) => TvDisplay(
        id: j['id']?.toString() ?? '',
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        activeTickets: j['active_tickets'] ?? 0,
        isOnline: j['is_online'] ?? false,
        templateId: j['template_id']?.toString(),
        apiHost: j['api_host']?.toString() ?? '',
        tenantName: j['tenant_name']?.toString() ?? '',
      );
}

// ── Queue ─────────────────────────────────────────────────────

class QueueTicket {
  final String ticketCode;
  final String serviceType;
  final String counterName;
  final String status;
  final String branchName;

  QueueTicket({
    required this.ticketCode,
    required this.serviceType,
    required this.counterName,
    required this.status,
    this.branchName = '',
  });

  factory QueueTicket.fromJson(Map<String, dynamic> j) => QueueTicket(
        ticketCode: j['ticket_code'] ?? '',
        serviceType: j['service_type'] ?? '',
        counterName: j['counter_name'] ?? '',
        status: j['status'] ?? 'waiting',
        branchName: j['branch_name']?.toString() ?? '',
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

// ── Web display API (qf_screen parity) ──────────────────────

class TvMediaItem {
  final String id;
  final String? title;
  final String kind;
  final String? url;
  final int durationSeconds;
  final int orderIndex;

  TvMediaItem({
    required this.id,
    this.title,
    required this.kind,
    this.url,
    this.durationSeconds = 10,
    this.orderIndex = 0,
  });

  factory TvMediaItem.fromJson(Map<String, dynamic> j) => TvMediaItem(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString(),
        kind: j['kind']?.toString() ?? 'image',
        url: j['url']?.toString(),
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 10,
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
      );
}

class TvTickerMessage {
  final String id;
  final String body;
  final String kind;
  final int orderIndex;

  TvTickerMessage({
    required this.id,
    required this.body,
    required this.kind,
    this.orderIndex = 0,
  });

  factory TvTickerMessage.fromJson(Map<String, dynamic> j) => TvTickerMessage(
        id: j['id']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'custom',
        orderIndex: (j['order_index'] as num?)?.toInt() ?? 0,
      );
}

class DisplayConfig {
  final String tenantId;
  final String branchId;
  final List<String> branchIds;
  final String displayId;
  final String layout;
  final bool ttsEnabled;
  final List<TvMediaItem> mediaItems;
  final List<TvTickerMessage> tickerMessages;
  final ReverbConfig reverb;

  DisplayConfig({
    required this.tenantId,
    required this.branchId,
    this.branchIds = const [],
    required this.displayId,
    required this.layout,
    this.ttsEnabled = true,
    this.mediaItems = const [],
    this.tickerMessages = const [],
    required this.reverb,
  });

  List<String> get effectiveBranchIds =>
      branchIds.isNotEmpty ? branchIds : (branchId.isNotEmpty ? [branchId] : []);

  factory DisplayConfig.fromJson(Map<String, dynamic> j) {
    final rawIds = j['branch_ids'] as List? ?? [];
    return DisplayConfig(
      tenantId: j['tenant_id']?.toString() ?? '',
      branchId: j['branch_id']?.toString() ?? '',
      branchIds: rawIds.map((e) => e.toString()).toList(),
      displayId: j['display_id']?.toString() ?? '',
      layout: j['layout']?.toString() ?? 'split',
      ttsEnabled: j['tts_enabled'] != false,
      mediaItems: (j['media_items'] as List? ?? [])
          .map((e) => TvMediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      tickerMessages: (j['ticker_messages'] as List? ?? [])
          .map((e) => TvTickerMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      reverb: ReverbConfig.fromJson(j['reverb'] ?? {}),
    );
  }
}

class DisplayState {
  final String tenantId;
  final QueueTicket? nowCalling;
  final List<QueueTicket> nowServing;
  final List<QueueTicket> waitingNext;
  final int totalWaiting;

  DisplayState({
    required this.tenantId,
    this.nowCalling,
    required this.nowServing,
    required this.waitingNext,
    required this.totalWaiting,
  });

  factory DisplayState.fromJson(Map<String, dynamic> j) => DisplayState(
        tenantId: j['tenant_id']?.toString() ?? '',
        nowCalling: j['now_calling'] != null
            ? QueueTicket.fromJson(j['now_calling'] as Map<String, dynamic>)
            : null,
        nowServing: (j['now_serving'] as List? ?? [])
            .map((e) => QueueTicket.fromJson(e as Map<String, dynamic>))
            .toList(),
        waitingNext: (j['waiting_next'] as List? ?? [])
            .map((e) => QueueTicket.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalWaiting: (j['total_waiting'] as num?)?.toInt() ?? 0,
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
  final List<String> branchIds;
  final String templateId;
  final String token;
  final String tenantId;
  final String apiHost;
  final ReverbConfig reverb;

  ActivateResult({
    required this.displayId,
    required this.displayName,
    required this.branchId,
    this.branchIds = const [],
    required this.templateId,
    required this.token,
    required this.tenantId,
    this.apiHost = '',
    required this.reverb,
  });

  List<String> get effectiveBranchIds =>
      branchIds.isNotEmpty ? branchIds : (branchId.isNotEmpty ? [branchId] : []);

  bool get isMultiBranch => effectiveBranchIds.length > 1;

  factory ActivateResult.fromJson(Map<String, dynamic> j) {
    final rawIds = j['branch_ids'] as List? ?? [];
    final branchIds = rawIds.map((e) => e.toString()).toList();

    return ActivateResult(
      displayId: j['display_id']?.toString() ?? '',
      displayName: j['display_name'] ?? '',
      branchId: j['branch_id']?.toString() ?? '',
      branchIds: branchIds,
      templateId: j['template_id']?.toString() ?? '',
      token: j['token'] ?? '',
      tenantId: j['tenant_id']?.toString() ?? '',
      apiHost: j['api_host']?.toString() ?? '',
      reverb: ReverbConfig.fromJson(j['reverb'] ?? {}),
    );
  }
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
