import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Rounded container that stacks rows with hairline dividers, with an optional section label.
///
/// ```dart
/// ListGroup(title: 'Gameplay', children: [
///   SwitchRow(title: 'Sound', value: s, onChanged: setS),
///   ListRowTile(title: 'Limits', onTap: openLimits),
/// ])
/// ```
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(title!.toUpperCase(), style: AppText.label()),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.line, indent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
