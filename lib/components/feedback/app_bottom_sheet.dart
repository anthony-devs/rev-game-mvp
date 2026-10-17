import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Opens a dark bottom sheet with a drag handle and optional title.
///
/// ```dart
/// showAppBottomSheet(context, title: 'Paytable', child: PaytableList());
/// ```
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    builder: (_) => AppBottomSheet(title: title, child: child),
  );
}

/// The sheet body itself. Use directly when you need an inline sheet.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.handle, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(title!, style: AppText.body(20, weight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}
