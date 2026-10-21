import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/require_sign_in.dart';
import '../catalog/catalog_cubit.dart';
import '../components/components.dart';
import '../components/core/play_mode.dart';
import '../core/api/api_client.dart';
import '../pages/round_format.dart';
import 'bets_api.dart';

/// "Top wins / My bets": the games players have won the most on, and your own latest bets (5 rows each).
/// Refreshes by itself while it is on screen.
class BetsFeed extends StatefulWidget {
  const BetsFeed({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  State<BetsFeed> createState() => _BetsFeedState();
}

class _BetsFeedState extends State<BetsFeed> {
  late final BetsApi _api = BetsApi(context.read<ApiClient>());
  BetsKind _kind = BetsKind.top;
  List<BetRow> _rows = const [];
  List<TopGame> _top = const [];
  bool _loaded = false;
  bool _failed = false;
  Timer? _timer;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    PlayMode.live.addListener(_reload);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    PlayMode.live.removeListener(_reload);
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() => _loaded = false);
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    final signedIn = context.read<AuthBloc>().state.isAuthenticated;
    if (_kind == BetsKind.mine && !signedIn) {
      if (mounted) setState(() {
        _rows = const [];
        _loaded = true;
      });
      return;
    }
    final ticket = ++_ticket;
    try {
      final live = PlayMode.isLive;
      final rows = _kind == BetsKind.mine ? await _api.mine(live: live) : const <BetRow>[];
      final top = _kind == BetsKind.top ? await _api.top(live: live) : const <TopGame>[];
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _rows = rows.take(5).toList();
        _top = top.take(5).toList();
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || ticket != _ticket) return;
      if (!quiet || !_loaded) setState(() => _failed = true);
    }
  }

  void _pick(BetsKind k) {
    if (k == _kind) return;
    if (k == BetsKind.mine && !requireSignIn(context)) return;
    AppSound.play(Sfx.tap);
    setState(() {
      _kind = k;
      _loaded = false;
      _failed = false;
      _rows = const [];
      _top = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          SectionHeader(title: 'Live bets', icon: Icons.bolt_rounded, iconColor: AppColors.gold, padding: EdgeInsets.zero),
          const SizedBox(height: 12),
        ],
        Row(children: [
          for (final k in BetsKind.values) ...[
            Expanded(child: _Tab(label: k == BetsKind.top ? 'Top wins' : 'My bets', on: _kind == k, onTap: () => _pick(k))),
            if (k != BetsKind.values.last) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
          child: _body(_rows, catalog),
        ),
      ],
    );
  }

  Widget _body(List<BetRow> rows, CatalogState catalog) {
    if (_failed && rows.isEmpty && _top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text("Couldn't load the bets.", style: AppText.body(13, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          AppButton(label: 'Try again', variant: AppButtonVariant.outline, height: 40, fontSize: 13, expanded: false, onPressed: () => _reload()),
        ]),
      );
    }
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Center(child: AppLoader()));
    }
    if (_kind == BetsKind.top) {
      if (_top.isEmpty) {
        return Padding(padding: const EdgeInsets.all(22), child: Center(child: Text('No big wins yet. Be the first.', style: AppText.body(13, color: AppColors.textMuted))));
      }
      return Column(children: [
        for (var i = 0; i < _top.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.line),
          _TopTile(rank: i + 1, game: _top[i], gameName: catalog.byId(_top[i].game)?.name ?? _top[i].game),
        ],
      ]);
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(22),
        child: Center(child: Text('Your bets will show here.', style: AppText.body(13, color: AppColors.textMuted))),
      );
    }
    return Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: AppColors.line),
        _BetTile(row: rows[i], gameName: catalog.byId(rows[i].game)?.name ?? rows[i].game),
      ],
    ]);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.text.withValues(alpha: .1) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppColors.text.withValues(alpha: .5) : AppColors.line),
        ),
        child: Text(label, style: AppText.body(12, weight: FontWeight.w700, color: on ? AppColors.text : AppColors.textMuted)),
      ),
    );
  }
}

class _TopTile extends StatelessWidget {
  const _TopTile({required this.rank, required this.game, required this.gameName});

  final int rank;
  final TopGame game;
  final String gameName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        SizedBox(width: 26, child: Text('$rank', style: AppText.number(15, color: rank == 1 ? AppColors.gold : AppColors.textDim))),
        Expanded(child: Text(gameName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14, weight: FontWeight.w700))),
        const SizedBox(width: 10),
        Text(PlayMode.amount(game.won, decimals: 0), style: AppText.number(14, color: AppColors.green)),
      ]),
    );
  }
}

class _BetTile extends StatelessWidget {
  const _BetTile({required this.row, required this.gameName});

  final BetRow row;
  final String gameName;

  @override
  Widget build(BuildContext context) {
    final color = row.win ? AppColors.green : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gameName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${row.name}${row.at == null ? '' : '  ·  ${timeAgo(row.at!)}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(11, color: AppColors.textDim)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(row.win ? '+${formatCredits(row.payout - row.bet, decimals: 0)}' : '-${formatCredits(row.bet - row.payout, decimals: 0)}', style: AppText.number(14, color: color)),
          const SizedBox(height: 2),
          Text('${formatCredits(row.bet, decimals: 0)}  ·  ${formatMultiplier(row.multiplier, trim: true)}', style: AppText.body(11, color: AppColors.textDim)),
        ]),
      ]),
    );
  }
}

/// The full list, opened from "View all".
class BetsPage extends StatelessWidget {
  const BetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.gold,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Live bets', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const BetsFeed(showHeader: false),
        ],
      ),
    );
  }
}
