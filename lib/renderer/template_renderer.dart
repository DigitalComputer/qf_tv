import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme.dart';
import 'zone_widgets.dart';

class TemplateRenderer extends StatefulWidget {
  final DisplayTemplate template;
  final QueueState queueState;
  final bool wsConnected;

  const TemplateRenderer({
    super.key,
    required this.template,
    required this.queueState,
    required this.wsConnected,
  });

  @override
  State<TemplateRenderer> createState() => _TemplateRendererState();
}

class _TemplateRendererState extends State<TemplateRenderer>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _flashCtrl;
  String? _prevCalling;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void didUpdateWidget(TemplateRenderer old) {
    super.didUpdateWidget(old);
    final newCode = widget.queueState.nowCalling?.ticketCode;
    if (newCode != null && newCode != _prevCalling) {
      _prevCalling = newCode;
      _flashCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tmpl = widget.template;
    return Container(
      color: tmpl.background.color,
      child: Stack(
        children: [
          if (tmpl.background.pattern != 'none')
            Positioned.fill(
              child: CustomPaint(
                painter: _BgPainter(tmpl.background.pattern),
              ),
            ),
          Column(
            children: [
              if (tmpl.topBar.show)
                _TopBar(
                  topBar: tmpl.topBar,
                  queueState: widget.queueState,
                  wsConnected: widget.wsConnected,
                ),
              Expanded(child: _buildLayout(tmpl)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayout(DisplayTemplate tmpl) => switch (tmpl.layout.type) {
        'split_vertical' => _splitVertical(tmpl),
        'split_horizontal' => _splitHorizontal(tmpl),
        'fullscreen' => _fullscreen(tmpl),
        'grid_2x2' => _grid2x2(tmpl),
        'ticker_bottom' => _tickerBottom(tmpl),
        _ => _splitVertical(tmpl),
      };

  Widget _splitVertical(DisplayTemplate tmpl) {
    final main = tmpl.zoneBySlot('main');
    final sideTop = tmpl.zoneBySlot('side_top');
    final sideBtm = tmpl.zoneBySlot('side_bottom');

    return Row(
      children: [
        Expanded(child: main != null ? _buildZone(main) : const SizedBox()),
        Container(width: 1, color: QueueTheme.border),
        SizedBox(
          width: tmpl.layout.sideWidth,
          child: Column(
            children: [
              if (sideTop != null) Expanded(flex: 3, child: _buildZone(sideTop)),
              if (sideTop != null && sideBtm != null)
                Container(height: 1, color: QueueTheme.border),
              if (sideBtm != null) Expanded(flex: 2, child: _buildZone(sideBtm)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _splitHorizontal(DisplayTemplate tmpl) {
    final main = tmpl.zoneBySlot('main');
    final sideTop = tmpl.zoneBySlot('side_top');
    final sideBtm = tmpl.zoneBySlot('side_bottom');

    return Column(
      children: [
        Expanded(child: main != null ? _buildZone(main) : const SizedBox()),
        Container(height: 1, color: QueueTheme.border),
        SizedBox(
          height: tmpl.layout.sideHeight,
          child: Row(
            children: [
              if (sideTop != null) Expanded(child: _buildZone(sideTop)),
              if (sideTop != null && sideBtm != null)
                Container(width: 1, color: QueueTheme.border),
              if (sideBtm != null) Expanded(child: _buildZone(sideBtm)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fullscreen(DisplayTemplate tmpl) {
    final main = tmpl.zoneBySlot('main');
    return main != null ? _buildZone(main) : const SizedBox();
  }

  Widget _grid2x2(DisplayTemplate tmpl) {
    Widget cell(String slot) {
      final z = tmpl.zoneBySlot(slot);
      return Expanded(child: z != null ? _buildZone(z) : const SizedBox());
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              cell('grid_tl'),
              Container(width: 1, color: QueueTheme.border),
              cell('grid_tr'),
            ],
          ),
        ),
        Container(height: 1, color: QueueTheme.border),
        Expanded(
          child: Row(
            children: [
              cell('grid_bl'),
              Container(width: 1, color: QueueTheme.border),
              cell('grid_br'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tickerBottom(DisplayTemplate tmpl) {
    final main = tmpl.zoneBySlot('main');
    final ticker = tmpl.zoneBySlot('ticker');

    return Column(
      children: [
        if (main != null) Expanded(child: _buildZone(main)),
        Container(height: 1, color: QueueTheme.border),
        if (ticker != null) SizedBox(height: 72, child: _buildZone(ticker)),
      ],
    );
  }

  Widget _buildZone(TemplateZone zone) => switch (zone.type) {
        'calling' => CallingZone(
            zone: zone,
            ticket: widget.queueState.nowCalling,
            flashAnim: _flashCtrl,
            pulseAnim: _pulseCtrl,
          ),
        'serving_list' => ServingListZone(
            zone: zone, tickets: widget.queueState.nowServing),
        'waiting_list' => WaitingListZone(
            zone: zone, tickets: widget.queueState.waitingNext),
        'total_waiting' => TotalWaitingZone(
            zone: zone, total: widget.queueState.totalWaiting),
        'announcement' => AnnouncementZone(zone: zone),
        _ => const SizedBox(),
      };

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }
}

class _TopBar extends StatefulWidget {
  final TemplateTopBar topBar;
  final QueueState queueState;
  final bool wsConnected;

  const _TopBar({
    required this.topBar,
    required this.queueState,
    required this.wsConnected,
  });

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> with SingleTickerProviderStateMixin {
  DateTime _now = DateTime.now();
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    Future.delayed(Duration.zero, _tick);
  }

  Future<void> _tick() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _now = DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tb = widget.topBar;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: tb.backgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: QueueTheme.amberDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: QueueTheme.amber),
                ),
                child: const Icon(Icons.queue, color: QueueTheme.amber, size: 18),
              ),
              const SizedBox(width: 12),
              Text('QueueFlow',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: QueueTheme.textPrimary)),
              if (tb.showRoomName) ...[
                const SizedBox(width: 16),
                Container(width: 1, height: 24, color: QueueTheme.border),
                const SizedBox(width: 16),
                Text(
                  widget.queueState.roomName.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: QueueTheme.amber,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              if (tb.showTotal)
                _pill(
                  icon: Icons.people,
                  color: QueueTheme.blue,
                  label: '${widget.queueState.totalWaiting} aguardando',
                ),
              if (tb.showTotal) const SizedBox(width: 12),
              if (tb.showStatus)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => _pill(
                    icon: widget.wsConnected ? Icons.wifi : Icons.wifi_off,
                    color: widget.wsConnected ? QueueTheme.green : QueueTheme.red,
                    label: widget.wsConnected ? 'AO VIVO' : 'RECONECTANDO...',
                    pulseFactor: _pulse.value,
                  ),
                ),
              if (tb.showStatus) const SizedBox(width: 16),
              if (tb.showClock)
                Text(
                  DateFormat('HH:mm').format(_now),
                  style: GoogleFonts.spaceMono(
                    fontSize: 18,
                    color: QueueTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required Color color,
    required String label,
    double pulseFactor = 0,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08 + pulseFactor * 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.pattern);
  final String pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = QueueTheme.border.withOpacity(0.35)
      ..strokeWidth = 0.5;
    const step = 40.0;
    if (pattern == 'dots') {
      for (double x = 0; x < size.width; x += step) {
        for (double y = 0; y < size.height; y += step) {
          canvas.drawCircle(Offset(x, y), 1, paint);
        }
      }
    } else if (pattern == 'grid') {
      for (double x = 0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
