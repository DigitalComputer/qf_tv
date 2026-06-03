import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// One-time overlay so TTS/audio can run on Linux kiosk (user gesture).
class SoundGate extends StatelessWidget {
  final VoidCallback onActivate;

  const SoundGate({super.key, required this.onActivate});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActivate,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, __) {
            onActivate();
            return KeyEventResult.handled;
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_up_rounded,
                    size: 72, color: QueueTheme.amber),
                const SizedBox(height: 24),
                Text(
                  'Painel TV — QueueFlow',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: QueueTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Clique em qualquer lugar para activar o som',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    color: QueueTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
