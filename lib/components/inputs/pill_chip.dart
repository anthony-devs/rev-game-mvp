import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Single filter pill.
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.bg : AppColors.textSoft;
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(38),
          border: Border.all(color: selected ? Colors.white : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: AppText.body(13, weight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of [PillChip]s (Browse filters).
///
/// ```dart
/// FilterChipRow(labels: const ['All', 'Slots', 'Table', 'Instant'], selectedIndex: tab, onSelected: (i) => setState(() => tab = i))
/// ```
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => PillChip(label: labels[i], selected: i == selectedIndex, onTap: () => onSelected(i)),
      ),
    );
  }
}
