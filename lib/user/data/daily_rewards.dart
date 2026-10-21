import '../../model/model.dart';

/// Coins for each day of the 7 day streak. Must match the server (config.py).
const List<int> kDailyRewards = [20, 20, 30, 40, 50, 60, 200];

/// A streak survives if the player claims again within this time.
const Duration kStreakGrace = Duration(hours: 48);

/// What the next daily claim will pay.
class DailyPreview {
  const DailyPreview({required this.day, required this.amount, required this.secondsLeft, required this.streakAfter});

  /// 1 to 7: which day of the streak the next claim is.
  final int day;
  final int amount;

  /// 0 when ready to claim.
  final int secondsLeft;
  final int streakAfter;

  bool get ready => secondsLeft <= 0;
}

DailyPreview previewDaily(Wallet wallet, PlayerProgress progress, DateTime now) {
  final last = wallet.lastDailyClaimAt;
  final keeps = last != null && now.difference(last) <= kStreakGrace;
  final streak = keeps ? progress.streakDays + 1 : 1;
  final day = ((streak - 1) % kDailyRewards.length) + 1;
  return DailyPreview(
    day: day,
    amount: kDailyRewards[day - 1],
    secondsLeft: wallet.secondsUntilDaily(now),
    streakAfter: streak,
  );
}

/// Days of the current streak that are already claimed (0 to 7), for the dots.
int claimedDotsToday(Wallet wallet, PlayerProgress progress, DateTime now) {
  final last = wallet.lastDailyClaimAt;
  if (last == null || now.difference(last) > kStreakGrace) return 0;
  final s = progress.streakDays;
  if (s <= 0) return 0;
  return ((s - 1) % kDailyRewards.length) + 1;
}
