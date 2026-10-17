import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'fairness_page.dart';
import 'round_format.dart';
import 'system_pages.dart';

/// W3. Every round the player has played, newest first.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _filters = <String, GameType?>{
    'All': null,
    'Slots': GameType.slots,
    'Roulette': GameType.roulette,
    'Blackjack': GameType.blackjack,
    'Dice': GameType.dice,
    'Crash': GameType.crash,
  };

  int _filter = 0;

  /// Stacks the player has opened, keyed by "yyyy-m-d|game".
  final Set<String> _open = {};
  Stream<List<GameRound>>? _stream;
  String _uid = '';

  @override
  Widget build(BuildContext context) {
    final uid = context.select((ProfileCubit c) => c.state.dataId);
    if (uid != _uid) {
      _uid = uid;
      _stream = uid.isEmpty ? null : context.read<UserRepository>().watchRounds(uid, limit: 50);
    }
    final labels = _filters.keys.toList();
    final game = _filters[labels[_filter]];

    return AppScaffold(
      glowColor: AppColors.purple,
      body: Column(
        children: [
          SubPageBar(title: 'Game history', onBack: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 4),
          FilterChipRow(labels: labels, selectedIndex: _filter, onSelected: (i) => setState(() => _filter = i)),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<GameRound>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return OfflineView(onRetry: () => setState(() => _uid = ''));
                }
                if (!snap.hasData) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [for (var i = 0; i < 7; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonBox(height: 66, radius: 16))],
                  );
                }
                final rounds = [for (final r in snap.data!) if (game == null || r.game == game) r];
                if (rounds.isEmpty) {
                  return StatusView(
                    icon: Icons.history_rounded,
                    title: game == null ? 'No rounds yet' : 'No ${labels[_filter]} rounds yet',
                    message: 'Your results will show up here after you play.',
                  );
                }
                final days = _groupByDay(rounds);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: days.length,
                  itemBuilder: (_, i) => _DaySection(
                    day: days[i],
                    expanded: _open,
                    onToggle: (key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.round, this.compact = false});
  final GameRound round;

  /// Inside an opened stack: show the clock time, the game is already known.
  final bool compact;

  static String _clock(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final r = round;
    return PressScale(
      onTap: () => pushPage<void>(context, FairnessPage(roundId: r.id)),
      scale: .99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.handle.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
              child: Text(r.game.abbr, style: AppText.body(13, weight: FontWeight.w800, color: AppColors.textSoft)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(compact ? r.summary : r.game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(15, weight: FontWeight.w600)),
                  Text('${compact ? _clock(r.createdAt) : timeAgo(r.createdAt)} · Bet ${formatCredits(r.bet, decimals: 0)}', style: AppText.body(12, color: AppColors.textDim)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatSigned(r.net), style: AppText.number(15, color: r.tone)),
                Text(r.returned > 0 ? formatMultiplier(r.returned, trim: true) : '-', style: AppText.body(12, color: AppColors.textDim)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// ------------------------------------------------------------------ grouping

class _GameStack {
  _GameStack(this.key, this.game, this.rounds);
  final String key;
  final GameType game;
  final List<GameRound> rounds; // newest first

  double get net => rounds.fold(0.0, (a, r) => a + r.net);
  double get bet => rounds.fold(0.0, (a, r) => a + r.bet);
  int get wins => rounds.where((r) => r.net > 0).length;
}

class _Day {
  _Day(this.date, this.stacks);
  final DateTime date;
  final List<_GameStack> stacks;

  int get count => stacks.fold(0, (a, s) => a + s.rounds.length);
  double get net => stacks.fold(0.0, (a, s) => a + s.net);
}

/// Rounds (newest first) into days, and each day into one stack per game.
List<_Day> _groupByDay(List<GameRound> rounds) {
  final byDay = <String, List<GameRound>>{};
  for (final r in rounds) {
    final t = r.createdAt.toLocal();
    byDay.putIfAbsent('${t.year}-${t.month}-${t.day}', () => []).add(r);
  }
  final days = <_Day>[];
  byDay.forEach((dayKey, list) {
    final byGame = <GameType, List<GameRound>>{};
    for (final r in list) {
      byGame.putIfAbsent(r.game, () => []).add(r);
    }
    final t = list.first.createdAt.toLocal();
    days.add(_Day(DateTime(t.year, t.month, t.day), [
      for (final e in byGame.entries) _GameStack('$dayKey|${e.key.name}', e.key, e.value),
    ]));
  });
  return days;
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final base = '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

Color _toneOf(double net) => net > 0 ? AppColors.green : (net < 0 ? AppColors.loss : AppColors.textMuted);

// ------------------------------------------------------------------- widgets

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.expanded, required this.onToggle});

  final _Day day;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
          child: Row(
            children: [
              Text(_dayLabel(day.date).toUpperCase(), style: AppText.label()),
              const SizedBox(width: 8),
              Text('${day.count} ${day.count == 1 ? 'round' : 'rounds'}', style: AppText.body(11, color: AppColors.textFaint)),
              const Spacer(),
              Text(formatSigned(day.net), style: AppText.number(13, color: _toneOf(day.net))),
            ],
          ),
        ),
        for (final s in day.stacks) ...[
          s.rounds.length == 1
              ? _RoundTile(round: s.rounds.first)
              : _StackCard(stack: s, open: expanded.contains(s.key), onToggle: () => onToggle(s.key)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// All of one game's rounds on one day. Collapsed it looks like a stack of cards.
class _StackCard extends StatelessWidget {
  const _StackCard({required this.stack, required this.open, required this.onToggle});

  final _GameStack stack;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = stack;
    final n = s.rounds.length;

    final header = PressScale(
      onTap: () {
        AppSound.play(Sfx.tap, volume: .4);
        onToggle();
      },
      scale: .99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: open ? AppColors.lineStrong : AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.handle.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
              child: Text(s.game.abbr, style: AppText.body(13, weight: FontWeight.w800, color: AppColors.textSoft)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(s.game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(15, weight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.handle.withValues(alpha: .7), borderRadius: BorderRadius.circular(10)),
                        child: Text('$n', style: AppText.body(11, weight: FontWeight.w800, color: AppColors.textSoft)),
                      ),
                    ],
                  ),
                  Text('${s.wins} won · Bet ${formatCredits(s.bet, decimals: 0)}', style: AppText.body(12, color: AppColors.textDim)),
                ],
              ),
            ),
            Text(formatSigned(s.net), style: AppText.number(15, color: _toneOf(s.net))),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: open
          ? Column(
              children: [
                header,
                Padding(
                  padding: const EdgeInsets.only(left: 14, top: 8),
                  child: Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.lineStrong, width: 2))),
                    child: Column(
                      children: [
                        for (var i = 0; i < n; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _RoundTile(round: s.rounds[i], compact: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: EdgeInsets.only(bottom: n > 2 ? 10 : 5),
              child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The two cards peeking out behind make it read as a stack.
                if (n > 2) Positioned(left: 20, right: 20, bottom: -10, child: _Layer(opacity: .45)),
                Positioned(left: 10, right: 10, bottom: -5, child: _Layer(opacity: .75)),
                header,
              ],
            )),
    );
  }
}

class _Layer extends StatelessWidget {
  const _Layer({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line.withValues(alpha: opacity)),
        ),
      );
}
