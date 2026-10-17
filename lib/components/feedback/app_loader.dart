import 'package:flutter/material.dart';
import 'package:flutter_multiple_loaders/flutter_multiple_loaders.dart';

/// The app's loading animation (bouncing dots). Use it everywhere something is loading, so the look
/// can be changed in this one place.
///
/// ```dart
/// const Center(child: AppLoader())
/// ```
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 36});

  /// Height of the loader. It is about three times as wide.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox(width: size * 2.2, height: size, child: BounceLoader()),
    );
  }
}
