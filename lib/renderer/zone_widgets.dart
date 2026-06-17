import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../theme.dart';

class CallingZone extends StatelessWidget {
  final TemplateZone zone;
  final QueueTicket? ticket;
  final Animation<double> flashAnim;
  final Animation<double> pulseAnim;

  const CallingZone({
    super.key,
    required this.zone,
    required this.ticket,
    required this.flashAnim,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final s = zone.style;
    return Container(
      color: s.backgroundColor ?? QueueTheme.bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: crossAlign(s.alignment),
        children: [
          if (s.showLabel && zone.label.isNotEmpty)
            zoneLabel(zone.label, s.accentColor),
          const SizedBox(height: 32),
          if (ticket != null) ...[
            _ticketCard(ticket!, s),
            if (s.showCounter) ...[
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: mainAlign(s.alignment),
                children: [
                  Icon(Icons.desk, color: QueueTheme.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    ticket!.counterName.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: QueueTheme.blue,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
            if (s.showService) ...[
              const SizedBox(height: 8),
              Text(
                ticket!.serviceType,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: s.fontSize,
                  color: s.textColor.withOpacity(0.7),
                ),
                textAlign: txtAlign(s.alignment),
              ),
            ],
          ] else
            _emptyState(s),
        ],
      ),
    );
  }

  Widget _ticketCard(QueueTicket t, ZoneStyle s) => AnimatedBuilder(
        animation: flashAnim,
        builder: (_, __) => AnimatedBuilder(
          animation: pulseAnim,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 28),
            decoration: BoxDecoration(
              color: s.accentColor.withOpacity(0.06 + pulseAnim.value * 0.04),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: s.accentColor.withOpacity(0.25 + flashAnim.value * 0.75),
                width: 2,
              ),
              boxShadow: s.glowEffect
                  ? [
                      BoxShadow(
                        color: s.accentColor
                            .withOpacity(0.04 + flashAnim.value * 0.22),
                        blurRadius: 64,
                        spreadRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.ticketCode,
                  style: GoogleFonts.spaceMono(
                    fontSize: s.ticketFontSize,
                    fontWeight: FontWeight.w700,
                    color: s.accentColor,
                    letterSpacing: 8,
                    height: 1.0,
                  ),
                ),
                if (t.branchName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.branchName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: (s.fontSize * 0.55).clamp(14, 20).toDouble(),
                      color: s.textColor.withOpacity(0.55),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _emptyState(ZoneStyle s) => Column(
        children: [
          Icon(Icons.hourglass_empty_rounded,
              size: 72, color: s.textColor.withOpacity(0.15)),
          const SizedBox(height: 20),
          Text(
            'SEM CHAMADAS',
            style: GoogleFonts.spaceMono(
              fontSize: 28,
              color: s.textColor.withOpacity(0.3),
              letterSpacing: 4,
            ),
          ),
        ],
      );
}

class ServingListZone extends StatelessWidget {
  final TemplateZone zone;
  final List<QueueTicket> tickets;

  const ServingListZone({super.key, required this.zone, required this.tickets});

  @override
  Widget build(BuildContext context) {
    final s = zone.style;
    final items = tickets.take(s.maxItems).toList();
    return Container(
      color: s.backgroundColor,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.showLabel && zone.label.isNotEmpty) ...[
            sectionHeader(zone.label, s.accentColor),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text('—',
                        style: GoogleFonts.spaceMono(
                            color: s.textColor.withOpacity(0.2), fontSize: 24)))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => TicketRow(
                      ticket: items[i],
                      accentColor: s.accentColor,
                      textColor: s.textColor,
                      showService: s.showService,
                      showCounter: s.showCounter,
                      fontSize: s.fontSize,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class WaitingListZone extends StatelessWidget {
  final TemplateZone zone;
  final List<QueueTicket> tickets;

  const WaitingListZone({super.key, required this.zone, required this.tickets});

  @override
  Widget build(BuildContext context) {
    final s = zone.style;
    final items = tickets.take(s.maxItems).toList();
    return Container(
      color: s.backgroundColor ?? QueueTheme.bgCard.withOpacity(0.5),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.showLabel && zone.label.isNotEmpty) ...[
            sectionHeader(zone.label, s.accentColor),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text('Fila vazia',
                        style: GoogleFonts.spaceGrotesk(
                            color: s.textColor.withOpacity(0.3))))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => TicketRow(
                      ticket: items[i],
                      accentColor: s.accentColor,
                      textColor: s.textColor.withOpacity(s.dim ? 0.55 : 1),
                      showService: s.showService,
                      showCounter: s.showCounter,
                      position: s.showPosition ? i + 1 : null,
                      fontSize: s.fontSize,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TotalWaitingZone extends StatelessWidget {
  final TemplateZone zone;
  final int total;

  const TotalWaitingZone({super.key, required this.zone, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = zone.style;
    return Container(
      color: s.backgroundColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (s.showLabel && zone.label.isNotEmpty)
            zoneLabel(zone.label, s.accentColor),
          const SizedBox(height: 12),
          Text(
            '$total',
            style: GoogleFonts.spaceMono(
              fontSize: s.ticketFontSize * 0.7,
              fontWeight: FontWeight.w700,
              color: s.accentColor,
            ),
          ),
          Text(
            'aguardando',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              color: s.textColor.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class AnnouncementZone extends StatelessWidget {
  final TemplateZone zone;

  const AnnouncementZone({super.key, required this.zone});

  @override
  Widget build(BuildContext context) {
    final s = zone.style;
    return Container(
      color: s.backgroundColor ?? s.accentColor.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      alignment: Alignment.center,
      child: Text(
        zone.label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: s.fontSize,
          fontWeight: FontWeight.w600,
          color: s.textColor,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
      ),
    );
  }
}

class TicketRow extends StatelessWidget {
  final QueueTicket ticket;
  final Color accentColor;
  final Color textColor;
  final bool showService;
  final bool showCounter;
  final int? position;
  final double fontSize;

  const TicketRow({
    super.key,
    required this.ticket,
    required this.accentColor,
    required this.textColor,
    required this.showService,
    required this.showCounter,
    required this.fontSize,
    this.position,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (position != null) ...[
                  SizedBox(
                    width: 22,
                    child: Text('$position.',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, color: textColor.withOpacity(0.4))),
                  ),
                  const SizedBox(width: 4),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.ticketCode,
                      style: GoogleFonts.spaceMono(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        letterSpacing: 2,
                      ),
                    ),
                    if (ticket.branchName.isNotEmpty)
                      Text(
                        ticket.branchName,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: textColor.withOpacity(0.45),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showCounter)
                  Text(ticket.counterName,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                          letterSpacing: 0.5)),
                if (showService)
                  Text(ticket.serviceType,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: textColor.withOpacity(0.4))),
              ],
            ),
          ],
        ),
      );
}

Widget zoneLabel(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        '▶  $text',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 2,
        ),
      ),
    );

Widget sectionHeader(String text, Color color) => Row(
      children: [
        Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color.withOpacity(0.8),
            letterSpacing: 2,
          ),
        ),
      ],
    );

CrossAxisAlignment crossAlign(String a) => switch (a) {
      'start' => CrossAxisAlignment.start,
      'end' => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };

MainAxisAlignment mainAlign(String a) => switch (a) {
      'start' => MainAxisAlignment.start,
      'end' => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

TextAlign txtAlign(String a) => switch (a) {
      'start' => TextAlign.left,
      'end' => TextAlign.right,
      _ => TextAlign.center,
    };
