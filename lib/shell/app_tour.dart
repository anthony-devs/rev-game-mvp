import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/components.dart';

/// The first-run walk-through of the home screen. Shown once per account on a device, and again from
/// Settings > "Take the app tour".
class AppTour {
  AppTour._();

  static String _key(String uid) => 'tour.home.v1.$uid';

  static List<CoachStep> _steps() => [
        const CoachStep(
          targetId: 'balance',
          title: 'Your balance',
          message: 'This is what you can play with. Tap it to switch between your Coins and Live wallets.',
          radius: 30,
        ),
        const CoachStep(
          targetId: 'add',
          title: 'Add money',
          message: 'Top up your Live wallet from here whenever you like.',
          radius: 30,
          padding: 4,
        ),
        const CoachStep(
          targetId: 'rounds',
          title: 'Your rounds',
          message: 'Free rounds refill over time. Tap to see when more arrive, or add extra rounds.',
          radius: 24,
        ),
        CoachStep(
          targetId: 'tabs',
          title: 'Find your way around',
          message: 'Browse all games, jump into the Casino, spin Slots, or open Settings for limits, history and help.',
          radius: 24,
          padding: 4,
        ),
        const CoachStep(
          targetId: 'support',
          title: 'Need a hand?',
          message: 'Chat with our support team any time. Replies show up here.',
          radius: 16,
        ),
      ];

  /// Shows the tour the first time this account opens the home screen.
  static Future<void> maybeShow(BuildContext context, {required String uid}) async {
    if (uid.isEmpty) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_key(uid)) ?? false) return;
    } catch (_) {
      return; // can't remember it was shown, so don't risk showing it every launch
    }
    if (!context.mounted) return;
    show(context, onDone: () {
      try {
        prefs?.setBool(_key(uid), true);
      } catch (_) {}
    });
  }

  /// Starts the tour now.
  static void show(BuildContext context, {VoidCallback? onDone}) {
    CoachTour.show(context, _steps(), onFinished: onDone);
  }
}
