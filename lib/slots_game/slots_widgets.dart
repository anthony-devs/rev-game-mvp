import 'package:flutter/material.dart';

import 'slots_theme.dart';

/// Digital readout on the machine's wood panel (WIN, BET).
/// Everything else (buttons, sheets, press effect) now comes from /components.
class Led extends StatelessWidget {
  const Led({super.key, required this.label, required this.value, required this.color, this.glow});

  final String label, value;
  final Color color;
  final Shadow? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0A08),
        borderRadius: BorderRadius.circular(10),
        border: const Border(bottom: BorderSide(color: Color(0x29FFEBBE))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: slotsInter(10, FontWeight.w800, color: const Color(0xFFC9A064), ls: 1.6, height: 1.2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: slotsOrbitron(25, color, shadows: glow == null ? null : [glow!])),
          ),
        ],
      ),
    );
  }
}

/// Small engraved plate under the reels that shows the last result.
class ResultPlate extends StatelessWidget {
  const ResultPlate({super.key, required this.text, this.win = false});

  final String text;
  final bool win;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF120D08), Color(0xFF22190E)],
        ),
        border: const Border(bottom: BorderSide(color: Color(0x73FFEBBE))),
      ),
      child: Text(
        text.toUpperCase(),
        style: slotsInter(11.5, FontWeight.w800, color: win ? const Color(0xFFFFD36B) : const Color(0xFFC9A064), ls: 1.4),
      ),
    );
  }
}
