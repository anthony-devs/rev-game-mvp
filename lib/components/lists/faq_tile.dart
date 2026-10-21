import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Expandable question and answer (Help).
///
/// ```dart
/// FaqTile(question: 'Is this real money?', answer: 'No. Coins are virtual.')
/// ```
class FaqTile extends StatelessWidget {
  const FaqTile({super.key, required this.question, required this.answer, this.initiallyExpanded = false});

  final String question;
  final String answer;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      // ExpansionTile draws ink; give it its own transparent Material so a coloured parent doesn't hide it.
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.centerLeft,
        iconColor: AppColors.text,
        collapsedIconColor: AppColors.textDim,
        trailing: const Icon(Icons.expand_more_rounded, size: 18),
        title: Text(question, style: AppText.body(15, weight: FontWeight.w600)),
        children: [Text(answer, style: AppText.body(13, color: AppColors.textMuted, height: 1.55))],
        ),
      ),
    );
  }
}
