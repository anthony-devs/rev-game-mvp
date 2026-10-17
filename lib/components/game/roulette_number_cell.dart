import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

enum RouletteColor { red, black, green }

const Set<int> kRouletteReds = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36};

RouletteColor rouletteColorOf(int n) => n == 0 ? RouletteColor.green : (kRouletteReds.contains(n) ? RouletteColor.red : RouletteColor.black);

Color _fill(RouletteColor c) {
  switch (c) {
    case RouletteColor.red:
      return const Color(0xFFC62B2E);
    case RouletteColor.black:
      return const Color(0xFF1C1C1E);
    case RouletteColor.green:
      return AppColors.greenDark;
  }
}

/// One cell of the betting table, or the result ball number.
///
/// ```dart
/// RouletteNumberCell(number: 17, selected: picks.contains(17), chipAmount: 50, onTap: () => toggle(17))
/// ```
class RouletteNumberCell extends StatelessWidget {
  const RouletteNumberCell({super.key, required this.number, this.onTap, this.selected = false, this.chipAmount, this.size = 44});

  final int number;
  final VoidCallback? onTap;
  final bool selected;

  /// Shows a small gold stake marker when set.
  final double? chipAmount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = rouletteColorOf(number);
    return PressScale(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _fill(color),
              borderRadius: BorderRadius.circular(size * .24),
              border: Border.all(color: selected ? AppColors.gold : AppColors.line, width: selected ? 2 : 1),
            ),
            child: Text('$number', style: AppText.number(size * .36, weight: FontWeight.w700, color: Colors.white)),
          ),
          if (chipAmount != null)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                child: Text(chipAmount!.toStringAsFixed(0), style: AppText.body(9, weight: FontWeight.w800, color: AppColors.onAccent, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}
