import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/require_sign_in.dart';
import '../catalog/catalog_cubit.dart';
import '../components/components.dart';
import '../components/core/play_mode.dart';
import '../core/api/api_client.dart';
import '../games/game_launcher.dart';
import '../games/game_support.dart';
import '../components/core/formatters.dart';
import 'events_api.dart';

String _left(DateTime? t) {
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'Ended';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h left';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m left';
  return '${d.inMinutes}m left';
}

String _score(GameEvent e, double v) => e.scoreIsMultiplier ? formatMultiplier(v, trim: true) : PlayMode.amount(v, decimals: 0);

/// The Events tab: running events first, then the ones about to start and the ones that just ended.
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  late final EventsApi _api = EventsApi(context.read<ApiClient>());
  List<GameEvent> _events = const [];
  bool _loaded = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    PlayMode.live.addListener(_reload);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
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
    try {
      final e = await _api.list(live: PlayMode.isLive);
      if (!mounted) return;
      setState(() {
        _events = e;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted && (!quiet || !_loaded)) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = [for (final e in _events) if (e.running) e];
    final soon = [for (final e in _events) if (e.status == 'upcoming') e];
    final done = [for (final e in _events) if (e.finished) e];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 120),
        children: [
          Text('Events', style: AppText.heading(28, letterSpacing: -1)),
          const SizedBox(height: 4),
          Text(PlayMode.isLive ? 'Climb the leaderboard and win real prizes.' : 'Climb the leaderboard and win free coins.', style: AppText.body(13, color: AppColors.textMuted)),
          const SizedBox(height: 18),
          if (!_loaded && !_failed)
            const SkeletonList(rows: 3, rowHeight: 120, radius: 20)
          else if (_failed && _events.isEmpty)
            StatusView(icon: Icons.cloud_off_rounded, title: "Couldn't load events", message: 'Check your connection and try again.', actionLabel: 'Try again', onAction: _reload)
          else if (_events.isEmpty)
            const StatusView(icon: Icons.emoji_events_outlined, title: 'No events right now', message: 'New events start often. Check back soon.')
          else ...[
            for (final e in running) _EventCard(event: e),
            if (soon.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionHeader(title: 'Starting soon', padding: EdgeInsets.zero),
              const SizedBox(height: 10),
              for (final e in soon) _EventCard(event: e),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionHeader(title: 'Finished', padding: EdgeInsets.zero),
              const SizedBox(height: 10),
              for (final e in done) _EventCard(event: e),
            ],
          ],
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final GameEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final top = e.prizes.isEmpty ? null : e.prizes.first;
    final color = e.running ? AppColors.gold : AppColors.textDim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressScale(
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => EventPage(eventId: e.id, initial: e))),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: e.running ? AppColors.gold.withValues(alpha: .5) : AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.emoji_events_rounded, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(17, weight: FontWeight.w800))),
              Text(e.running ? _left(e.endsAt) : (e.status == 'upcoming' ? 'Soon' : 'Ended'), style: AppText.label(color: color, size: 11)),
            ]),
            const SizedBox(height: 6),
            Text(e.description.isEmpty ? e.kindName : e.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(13, color: AppColors.textMuted, height: 1.4)),
            const SizedBox(height: 12),
            Row(children: [
              _Pill(e.kindName),
              if (top != null) ...[const SizedBox(width: 8), _Pill('Top prize ${PlayMode.amount(top, decimals: 0)}', gold: true)],
              if (e.me != null) ...[const SizedBox(width: 8), _Pill('You: #${e.me!.rank}', gold: true)],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.gold = false});

  final String text;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final c = gold ? AppColors.gold : AppColors.textMuted;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(11, weight: FontWeight.w700, color: c)),
      ),
    );
  }
}

/// One event: the prizes and the leaderboard.
class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.eventId, this.initial});

  final String eventId;
  final GameEvent? initial;

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late final EventsApi _api = EventsApi(context.read<ApiClient>());
  GameEvent? _event;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _event = widget.initial;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final e = await _api.get(widget.eventId);
      if (mounted) setState(() {
        _event = e;
        _failed = false;
      });
    } catch (_) {
      if (mounted && (!quiet || _event == null)) setState(() => _failed = true);
    }
  }

  bool _claiming = false;

  Future<void> _claim(GameEvent e) async {
    if (!requireSignIn(context) || _claiming) return;
    setState(() => _claiming = true);
    try {
      await _api.claimBoost(e.id);
      if (mounted) showToast(context, '${formatMultiplier(e.boostMult!, trim: true)} bonus is on for ${e.boostMinutes} minutes.');
      await _load();
    } on ApiException catch (err) {
      if (mounted) showToast(context, err.message, error: true);
    } catch (_) {
      if (mounted) showToast(context, "Couldn't claim the bonus. Please try again.", error: true);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  void _play(GameEvent e) {
    if (!requireSignIn(context)) return;
    final catalog = context.read<CatalogCubit>().state;
    final game = e.game == null ? (catalog.playable.isEmpty ? null : catalog.playable.first) : catalog.byId(e.game!);
    if (e.game == null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      showToast(context, 'Play any game to climb the board.');
      return;
    }
    if (game != null) openGame(context, game);
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    return AppScaffold(
      glowColor: AppColors.gold,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Event', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          if (e == null && !_failed)
            Column(children: [const SkeletonBox(height: 140, radius: 20), const SizedBox(height: 12), const SkeletonList(rows: 4, rowHeight: 52, radius: 14)])
          else if (e == null)
            StatusView(icon: Icons.cloud_off_rounded, title: "Couldn't load this event", message: 'Check your connection and try again.', actionLabel: 'Try again', onAction: _load)
          else ...[
            Text(e.title, style: AppText.heading(26, letterSpacing: -.8)),
            const SizedBox(height: 6),
            Text(e.description.isEmpty ? e.kindName : e.description, style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
            const SizedBox(height: 14),
            Row(children: [
              _Pill(e.kindName),
              const SizedBox(width: 8),
              _Pill(e.running ? _left(e.endsAt) : (e.status == 'upcoming' ? 'Starts soon' : 'Finished'), gold: e.running),
              const SizedBox(width: 8),
              _Pill('${e.players} playing'),
            ]),
            if (e.minBet > 0) ...[
              const SizedBox(height: 8),
              Text('Only bets of ${PlayMode.amount(e.minBet, decimals: 0)} or more count.', style: AppText.body(12, color: AppColors.textDim)),
            ],
            if (e.boostMult != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.gold.withValues(alpha: .5))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.bolt_rounded, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Text('${formatMultiplier(e.boostMult!, trim: true)} bonus', style: AppText.body(16, weight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Claim it to multiply your daily coins and rounds for ${e.boostMinutes} minutes.', style: AppText.body(13, color: AppColors.textMuted, height: 1.45)),
                  const SizedBox(height: 12),
                  AppButton(
                    label: e.boostClaimed ? 'Claimed' : (e.running ? 'Claim bonus' : 'Opens when the event starts'),
                    variant: AppButtonVariant.gold,
                    height: 46,
                    loading: _claiming,
                    onPressed: (e.running && !e.boostClaimed) ? () => _claim(e) : null,
                  ),
                ]),
              ),
            ],
            if (e.me != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.gold.withValues(alpha: .5))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR PLACE', style: AppText.label(color: AppColors.gold)),
                    const SizedBox(height: 2),
                    Text('#${e.me!.rank}  ·  ${_score(e, e.me!.score)}', style: AppText.number(22)),
                  ])),
                  if (e.me!.prize > 0) Text(e.finished ? 'Won ${PlayMode.amount(e.me!.prize, decimals: 0)}' : 'Prize ${PlayMode.amount(e.me!.prize, decimals: 0)}', style: AppText.body(13, weight: FontWeight.w800, color: AppColors.gold)),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            SectionHeader(title: 'Leaderboard', padding: EdgeInsets.zero),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
              child: e.board.isEmpty
                  ? Padding(padding: const EdgeInsets.all(22), child: Center(child: Text('No one on the board yet. Be the first.', style: AppText.body(13, color: AppColors.textMuted))))
                  : Column(children: [
                      for (var i = 0; i < e.board.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.line),
                        _BoardTile(row: e.board[i], event: e),
                      ],
                    ]),
            ),
            if (e.running) ...[
              const SizedBox(height: 20),
              AppButton(label: 'Play now', variant: AppButtonVariant.success, onPressed: () => _play(e)),
            ],
          ],
        ],
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.row, required this.event});

  final BoardRow row;
  final GameEvent event;

  @override
  Widget build(BuildContext context) {
    final medal = row.rank == 1 ? AppColors.gold : (row.rank == 2 ? AppColors.textSoft : (row.rank == 3 ? AppColors.goldDark : AppColors.textDim));
    return Container(
      color: row.me ? AppColors.gold.withValues(alpha: .08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        SizedBox(width: 34, child: Text('${row.rank}', style: AppText.number(16, color: medal))),
        Expanded(child: Text(row.me ? 'You' : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14, weight: FontWeight.w700))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_score(event, row.score), style: AppText.number(14)),
          if (row.prize > 0) Text(PlayMode.amount(row.prize, decimals: 0), style: AppText.body(11, weight: FontWeight.w700, color: AppColors.gold)),
        ]),
      ]),
    );
  }
}
