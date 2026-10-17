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
            const SizedBox(height: 12),
            Row(
              children: [
                _CloseButton(onTap: () => _close(context)),
                if (title != null) ...[
                  const SizedBox(width: 14),
                  Expanded(child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(20, weight: FontWeight.w700))),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

/// Closes this sheet, once. A second tap while the sheet is still sliding away must never pop the
/// page underneath it (that left the app on a black screen).
void _close(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop();
}

/// Round close button at the top left of every sheet, so people don't have to know to swipe down.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Close',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            child: Icon(Icons.close_rounded, size: 20, color: AppColors.text),
          ),
        ),
      );
}
