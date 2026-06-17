import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../widgets/tv_media_content.dart';

/// Brand tokens — match qf_screen index.css
class WebDisplayColors {
  static const brandBlack = Color(0xFF1A1A1A);
  static const brandGold = Color(0xFFD4AF37);
  static const surface = Color(0xFFF5F5F5);
  static const textSecondary = Color(0xFF757575);

  static Color serviceBg(String? code) {
    final letter = (code != null && code.isNotEmpty) ? code[0].toUpperCase() : '';
    return switch (letter) {
      'A' => const Color(0xFF1565C0),
      'B' => const Color(0xFF2E7D32),
      'C' => const Color(0xFF6A1B9A),
      'D' => const Color(0xFFE65100),
      'E' => const Color(0xFFB71C1C),
      _ => brandGold,
    };
  }

  static Color serviceText(String? code) {
    final letter = (code != null && code.isNotEmpty) ? code[0].toUpperCase() : '';
    return letter == '' || letter == 'F' || letter == 'G' ? brandBlack : Colors.white;
  }
}

class WebDisplayLayout extends StatelessWidget {
  const WebDisplayLayout({
    super.key,
    required this.config,
    required this.displayCode,
    required this.serviceName,
    required this.counterName,
    required this.isCalling,
    required this.waiting,
    required this.serving,
    required this.totalWaiting,
    required this.connected,
    this.wsConnected = false,
  });

  final DisplayConfig config;
  final String? displayCode;
  final String? serviceName;
  final String? counterName;
  final bool isCalling;
  final List<QueueTicket> waiting;
  final List<QueueTicket> serving;
  final int totalWaiting;
  final bool connected;
  final bool wsConnected;

  @override
  Widget build(BuildContext context) {
    final layout = config.layout;

    if (layout == 'full') {
      return _FullLayout(
        displayCode: displayCode,
        serviceName: serviceName,
        counterName: counterName,
        isCalling: isCalling,
        connected: connected,
      );
    }

    if (layout == 'default') {
      return _StandardLayout(
        displayCode: displayCode,
        serviceName: serviceName,
        counterName: counterName,
        isCalling: isCalling,
        waiting: waiting,
        serving: serving,
        totalWaiting: totalWaiting,
        connected: connected,
      );
    }

    return _TVGridLayout(
      displayCode: displayCode,
      serviceName: serviceName,
      counterName: counterName,
      isCalling: isCalling,
      waiting: waiting,
      serving: serving,
      totalWaiting: totalWaiting,
      mediaItems: config.mediaItems,
      tickerMessages: config.tickerMessages,
      connected: connected,
      wsConnected: wsConnected,
    );
  }
}

class _TVGridLayout extends StatelessWidget {
  const _TVGridLayout({
    required this.displayCode,
    required this.serviceName,
    required this.counterName,
    required this.isCalling,
    required this.waiting,
    required this.serving,
    required this.totalWaiting,
    required this.mediaItems,
    required this.tickerMessages,
    required this.connected,
    required this.wsConnected,
  });

  final String? displayCode;
  final String? serviceName;
  final String? counterName;
  final bool isCalling;
  final List<QueueTicket> waiting;
  final List<QueueTicket> serving;
  final int totalWaiting;
  final List<TvMediaItem> mediaItems;
  final List<TvTickerMessage> tickerMessages;
  final bool connected;
  final bool wsConnected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        const zoneDHeight = 56.0;
        final zoneAHeight = h * 0.45;
        final midHeight = h - zoneAHeight - zoneDHeight;

        return Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: zoneAHeight,
                  child: _ZoneA(
                    displayCode: displayCode,
                    serviceName: serviceName,
                    counterName: counterName,
                    isCalling: isCalling,
                  ),
                ),
                SizedBox(
                  height: midHeight,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: _ZoneB(
                          waiting: waiting,
                          serving: serving,
                          totalWaiting: totalWaiting,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _ZoneC(items: mediaItems),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: zoneDHeight,
                  child: _ZoneD(messages: tickerMessages),
                ),
              ],
            ),
            if (!connected) const _ReconnectBanner(),
            Positioned(
              right: 12,
              bottom: 64,
              child: _WsDot(connected: wsConnected),
            ),
          ],
        );
      },
    );
  }
}

class _ZoneA extends StatefulWidget {
  const _ZoneA({
    required this.displayCode,
    required this.serviceName,
    required this.counterName,
    required this.isCalling,
  });

  final String? displayCode;
  final String? serviceName;
  final String? counterName;
  final bool isCalling;

  @override
  State<_ZoneA> createState() => _ZoneAState();
}

class _ZoneAState extends State<_ZoneA> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = WebDisplayColors.serviceBg(widget.displayCode);
    final fg = WebDisplayColors.serviceText(widget.displayCode);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: bg,
      child: Stack(
        children: [
          Positioned(
            top: 24,
            right: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.serviceName != null && widget.serviceName!.isNotEmpty)
                  Text(
                    widget.serviceName!,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                if (widget.counterName != null && widget.counterName!.isNotEmpty)
                  Text(
                    'Unidade ${widget.counterName!}',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
          Center(
            child: widget.displayCode != null && widget.displayCode!.isNotEmpty
                ? AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) {
                      final glow = widget.isCalling ? 12 + _pulse.value * 12 : 0.0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: widget.isCalling
                              ? [
                                  BoxShadow(
                                    color: fg.withValues(alpha: 0.15 + _pulse.value * 0.2),
                                    blurRadius: glow,
                                    spreadRadius: glow / 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.displayCode!,
                            style: GoogleFonts.inter(
                              fontSize: 200,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              letterSpacing: -2,
                              color: fg,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Text(
                    'Aguarde a próxima chamada',
                    style: GoogleFonts.inter(
                      fontSize: 48,
                      color: fg.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          if (widget.displayCode != null && widget.isCalling)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: fg,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Aproxime-se',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: fg.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoneB extends StatelessWidget {
  const _ZoneB({
    required this.waiting,
    required this.serving,
    required this.totalWaiting,
  });

  final List<QueueTicket> waiting;
  final List<QueueTicket> serving;
  final int totalWaiting;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Column(
        children: [
          Expanded(
            child: _TicketSection(
              title: 'À espera',
              count: totalWaiting,
              items: waiting,
            ),
          ),
          Container(height: 1, color: Colors.white10),
          Expanded(
            child: _TicketSection(
              title: 'Em atendimento',
              items: serving,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketSection extends StatelessWidget {
  const _TicketSection({
    required this.title,
    required this.items,
    this.count,
  });

  final String title;
  final List<QueueTicket> items;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            count != null && count! > 0 ? '$title ($count)' : title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: Colors.white70,
            ),
          ),
        ),
        Container(height: 1, color: Colors.white10),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('—', style: TextStyle(color: Colors.white38, fontSize: 18)))
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    return Opacity(
                      opacity: (1 - i * 0.06).clamp(0.4, 1.0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.ticketCode,
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                if (t.branchName.isNotEmpty)
                                  Text(
                                    t.branchName,
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                                  ),
                              ],
                            ),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    t.serviceType,
                                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (t.counterName.isNotEmpty && t.counterName != 'Guichet')
                                    Text(
                                      t.counterName,
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ZoneC extends StatefulWidget {
  const _ZoneC({required this.items});

  final List<TvMediaItem> items;

  @override
  State<_ZoneC> createState() => _ZoneCState();
}

class _ZoneCState extends State<_ZoneC> {
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant _ZoneC oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _idx = 0;
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.items.isEmpty) return;
    final active = widget.items[_idx % widget.items.length];
    if (active.kind == 'iframe' || active.kind == 'youtube') return;

    final duration = Duration(seconds: active.durationSeconds > 0 ? active.durationSeconds : 10);
    _timer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _idx = (_idx + 1) % widget.items.length);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return ColoredBox(
        color: const Color(0xFF0A0A0A),
        child: Center(
          child: Text(
            'QueueFlow',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.24),
              fontSize: 36,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      );
    }

    final active = widget.items[_idx % widget.items.length];

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: TvMediaContent(key: ValueKey(active.id), item: active),
        ),
        if (widget.items.length > 1)
          Positioned(
            bottom: 12,
            right: 16,
            child: Row(
              children: List.generate(widget.items.length, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _idx ? Colors.white : Colors.white38,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _ZoneD extends StatefulWidget {
  const _ZoneD({required this.messages});

  final List<TvTickerMessage> messages;

  @override
  State<_ZoneD> createState() => _ZoneDState();
}

class _ZoneDState extends State<_ZoneD> with SingleTickerProviderStateMixin {
  late AnimationController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = AnimationController(vsync: this, duration: const Duration(seconds: 80))
      ..repeat();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _content() {
    final parts = <String>[];
    for (final m in widget.messages) {
      final prefix = switch (m.kind) {
        'aviso' => '⚠️',
        'cambio' => '💱',
        _ => '📢',
      };
      parts.add('$prefix  ${m.body}');
    }
    return parts.join('          ·          ');
  }

  @override
  Widget build(BuildContext context) {
    final text = _content();
    if (text.isEmpty) {
      return const ColoredBox(color: WebDisplayColors.brandBlack);
    }

    return ColoredBox(
      color: WebDisplayColors.brandBlack,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) {
            return FractionalTranslation(
              translation: Offset(1 - _scroll.value * 2, 0),
              child: child,
            );
          },
          child: Row(
            children: [
              Text(
                '$text      $text',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: WebDisplayColors.brandGold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandardLayout extends StatelessWidget {
  const _StandardLayout({
    required this.displayCode,
    required this.serviceName,
    required this.counterName,
    required this.isCalling,
    required this.waiting,
    required this.serving,
    required this.totalWaiting,
    required this.connected,
  });

  final String? displayCode;
  final String? serviceName;
  final String? counterName;
  final bool isCalling;
  final List<QueueTicket> waiting;
  final List<QueueTicket> serving;
  final int totalWaiting;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: WebDisplayColors.surface,
          child: Column(
            children: [
              Container(
                color: WebDisplayColors.brandBlack,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'QueueFlow',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      DateFormat.Hm().format(DateTime.now()),
                      style: GoogleFonts.inter(fontSize: 20, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 720),
                        padding: const EdgeInsets.all(48),
                        decoration: BoxDecoration(
                          color: isCalling ? WebDisplayColors.brandGold : const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: displayCode != null && displayCode!.isNotEmpty
                            ? Column(
                                children: [
                                  Text(
                                    '${serviceName ?? 'Serviço'}${counterName != null ? ' · $counterName' : ''}',
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      color: WebDisplayColors.brandBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    displayCode!,
                                    style: GoogleFonts.inter(
                                      fontSize: 96,
                                      fontWeight: FontWeight.w900,
                                      color: WebDisplayColors.brandBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Aproxime-se',
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      color: WebDisplayColors.brandBlack.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                'Aguarde a próxima chamada',
                                style: GoogleFonts.inter(
                                  fontSize: 36,
                                  color: WebDisplayColors.textSecondary,
                                ),
                              ),
                      ),
                      const SizedBox(height: 32),
                      _StandardQueueSection(title: 'À espera', items: waiting, count: totalWaiting),
                      const SizedBox(height: 24),
                      _StandardQueueSection(title: 'Em atendimento', items: serving),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!connected) const _ReconnectBanner(),
      ],
    );
  }
}

class _StandardQueueSection extends StatelessWidget {
  const _StandardQueueSection({
    required this.title,
    required this.items,
    this.count,
  });

  final String title;
  final List<QueueTicket> items;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count != null && count! > 0 ? '$title ($count)' : title,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 2,
              color: WebDisplayColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text('—', style: TextStyle(color: WebDisplayColors.textSecondary))
          else
            ...items.take(8).map(
                  (h) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          h.ticketCode,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(h.serviceType, style: const TextStyle(color: WebDisplayColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _FullLayout extends StatelessWidget {
  const _FullLayout({
    required this.displayCode,
    required this.serviceName,
    required this.counterName,
    required this.isCalling,
    required this.connected,
  });

  final String? displayCode;
  final String? serviceName;
  final String? counterName;
  final bool isCalling;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: WebDisplayColors.brandBlack,
          child: Stack(
            children: [
              Positioned(
                top: 24,
                right: 32,
                child: Text(
                  DateFormat.Hm().format(DateTime.now()),
                  style: GoogleFonts.inter(fontSize: 22, color: Colors.white),
                ),
              ),
              Center(
                child: displayCode != null && displayCode!.isNotEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${serviceName ?? 'Serviço'}${counterName != null ? ' · $counterName' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w500,
                              color: WebDisplayColors.brandGold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FittedBox(
                            child: Text(
                              displayCode!,
                              style: GoogleFonts.inter(
                                fontSize: 200,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Aproxime-se',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              color: WebDisplayColors.brandGold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Aguarde a próxima chamada',
                        style: GoogleFonts.inter(fontSize: 48, color: WebDisplayColors.textSecondary),
                      ),
              ),
            ],
          ),
        ),
        if (!connected) const _ReconnectBanner(),
      ],
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.red.shade700,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Text(
          'Sem ligação ao servidor — a tentar reconectar…',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}

class _WsDot extends StatelessWidget {
  const _WsDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? Colors.green : Colors.orange,
      ),
    );
  }
}
