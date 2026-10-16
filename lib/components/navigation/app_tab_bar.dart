import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';
import '../core/press_scale.dart';

class AppTabItem {
  const AppTabItem({required this.label, required this.icon, this.activeIcon});
  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

/// Floating pill tab bar. Place it in `AppScaffold.bottomBar`.
///
/// ```dart
/// AppTabBar(
///   currentIndex: tab,
///   onTap: (i) => setState(() => tab = i),
///   items: const [
///     AppTabItem(label: 'Browse', icon: Icons.search_rounded),
///     AppTabItem(label: 'Casino', icon: Icons.casino_outlined),
///     AppTabItem(label: 'Slots', icon: Icons.grid_view_rounded),
///     AppTabItem(label: 'Settings', icon: Icons.settings_outlined),
///   ],
/// )
/// ```
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = 68,
  });

  final List<AppTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(child: _Tab(item: items[i], active: i == currentIndex, onTap: () => onTap(i))),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});
  final AppTabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = active ? Colors.white : AppColors.textDim;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: PressScale(
        onTap: onTap,
        scale: .94,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(active ? (item.activeIcon ?? item.icon) : item.icon, size: 24, color: c),
                const SizedBox(height: 4),
                Text(item.label, style: AppText.body(11, weight: FontWeight.w600, color: c, height: 1)),
              ],
            ),
            Positioned(
              bottom: 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 22 : 0,
                height: 3,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
