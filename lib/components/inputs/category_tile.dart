import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// One category button: a rounded tile with an icon and a label. The chosen one gets a purple tint and border.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.text : AppColors.textSoft;
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple.withValues(alpha: .18) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.purple : AppColors.line, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: selected ? AppColors.purple : AppColors.textDim),
            const SizedBox(width: 8),
            Text(label, style: AppText.body(13, weight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Sideways-scrolling row of [CategoryTile]s.
class CategoryTileRow extends StatelessWidget {
  const CategoryTileRow({super.key, required this.labels, required this.icons, required this.selectedIndex, required this.onSelected});

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => CategoryTile(label: labels[i], icon: icons[i], selected: i == selectedIndex, onTap: () => onSelected(i)),
      ),
    );
  }
}
