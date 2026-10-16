import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'slots_models.dart';
import 'slots_theme.dart';

const _svgSeven =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><path d="M12 10H52V18L31 56H17L37 18H12Z" fill="#D62839" stroke="#7A0F1C" stroke-width="3" stroke-linejoin="round"/><path d="M17 14H46" stroke="#FF9AA3" stroke-width="3" stroke-linecap="round"/></svg>';
const _svgBar =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><rect x="6" y="18" width="52" height="28" rx="6" fill="#1B1B1F" stroke="#FFC83D" stroke-width="3"/></svg>';
const _svgBell =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><path d="M32 8a3 3 0 0 0-3 3v1.5C21.5 14.5 17 20.5 17 29v9l-5 7v3h40v-3l-5-7v-9c0-8.5-4.5-14.5-12-16.5V11a3 3 0 0 0-3-3z" fill="#FFC83D" stroke="#9A6A00" stroke-width="3" stroke-linejoin="round"/><path d="M26 51a6 6 0 0 0 12 0z" fill="#FFC83D" stroke="#9A6A00" stroke-width="3" stroke-linejoin="round"/><path d="M24 22c-3 3-4 7-4 11" stroke="#FFF0B3" stroke-width="3" stroke-linecap="round" fill="none"/></svg>';
const _svgCherry =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><path d="M22 44C24 30 30 18 42 10M44 46C44 30 42 20 42 10" stroke="#2E7D32" stroke-width="3" fill="none" stroke-linecap="round"/><circle cx="20" cy="46" r="11" fill="#D62839" stroke="#7A0F1C" stroke-width="3"/><circle cx="44" cy="48" r="11" fill="#D62839" stroke="#7A0F1C" stroke-width="3"/><path d="M42 10c6-2 11 0 14 4-6 2-11 1-14-4z" fill="#3DAA4A" stroke="#1F6B2A" stroke-width="2"/><circle cx="16" cy="42" r="3" fill="#FF9AA3"/><circle cx="40" cy="44" r="3" fill="#FF9AA3"/></svg>';
const _svgDiamond =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><path d="M16 12H48L58 26L32 56L6 26Z" fill="#2E9BFF" stroke="#14508F" stroke-width="3" stroke-linejoin="round"/><path d="M6 26H58M16 12L24 26L32 56M48 12L40 26L32 56M24 26L32 12L40 26" stroke="#FFFFFF" stroke-opacity="0.65" stroke-width="2" fill="none" stroke-linejoin="round"/></svg>';

const _svgFor = {
  SlotSymbol.seven: _svgSeven,
  SlotSymbol.bar: _svgBar,
  SlotSymbol.bell: _svgBell,
  SlotSymbol.cherry: _svgCherry,
  SlotSymbol.diamond: _svgDiamond,
};

class SymbolView extends StatelessWidget {
  const SymbolView(this.symbol, {super.key, this.size = 64});
  final SlotSymbol symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = size / 64;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SvgPicture.string(_svgFor[symbol]!, width: size, height: size),
        if (symbol == SlotSymbol.bar)
          Text('BAR',
              style: GoogleFonts.inter(
                  fontSize: 16 * k, fontWeight: FontWeight.w900, letterSpacing: 2 * k, color: kGold, height: 1)),
      ]),
    );
  }
}
