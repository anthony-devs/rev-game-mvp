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
  Stream<List<GameRound>>? _stream;
  String _uid = '';

  @override
  Widget build(BuildContext context) {
    final uid = context.select((ProfileCubit c) => c.state.user.id);
    if (uid != _uid) {
      _uid = uid;
      _stream = uid.isEmpty ? null : context.read<UserRepository>().watchRounds(uid, limit: 200);
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
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: rounds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RoundTile(round: rounds[i]),
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
  const _RoundTile({required this.round});
  final GameRound round;

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
                  Text(r.game.title, style: AppText.body(15, weight: FontWeight.w600)),
                  Text('${timeAgo(r.createdAt)} · Bet ${formatCredits(r.bet, decimals: 0)}', style: AppText.body(12, color: AppColors.textDim)),
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
