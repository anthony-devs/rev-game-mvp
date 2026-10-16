import 'package:flutter/material.dart';

import '../buttons/icon_square_button.dart';
import '../core/app_text.dart';

/// Back button + centred title for inner pages (Wallet, History, Settings sub pages).
///
/// ```dart
/// SubPageBar(title: 'Wallet', onBack: () => Navigator.pop(context))
/// SubPageBar(title: 'History', trailing: IconSquareButton(...))
/// ```
class SubPageBar extends StatelessWidget {
  const SubPageBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: onBack == null
                ? null
                : IconSquareButton(icon: Icons.chevron_left_rounded, semanticLabel: 'Back', onPressed: onBack, iconSize: 26),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: AppText.body(18, weight: FontWeight.w700)),
          ),
          SizedBox(width: 44, child: trailing),
        ],
      ),
    );
  }
}
