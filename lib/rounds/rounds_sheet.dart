import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../core/api/rounds_hub.dart';
import '../live/add_funds.dart';
import '../live/live_cubit.dart';

/// Opens the Rounds sheet: how many rounds are left, when free ones come back, and extra round packs.
Future<void> showRoundsSheet(BuildContext context) =>
    showAppBottomSheet<void>(context, title: 'Rounds', child: const _RoundsBody());

/// Loads the latest numbers for the wallet being played. Safe to call any time.
Future<void> refreshRounds(ApiClient api) async {
  try {
    await api.get('/v1/rounds');
  } catch (_) {} // the counter keeps whatever it had
}

class _RoundsBody extends StatefulWidget {
  const _RoundsBody();

  @override
  State<_RoundsBody> createState() => _RoundsBodyState();
}

class _RoundsBodyState extends State<_RoundsBody> {
  Timer? _tick;
  String? _error;
  bool _poor = false;
  String? _note;
  int? _buying;
  String _key = LiveCubit.newKey(); // one per attempt: a retry can never charge twice

  @override
  void initState() {
    super.initState();
    refreshRounds(context.read<ApiClient>());
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  ValueNotifier<RoundsInfo?> get _hub => RoundsHub.of(PlayMode.isLive);

  Future<void> _buy(int size) async {
    if (_buying != null) return;
    setState(() {
      _buying = size;
      _error = null;
      _poor = false;
      _note = null;
    });
    try {
      await context.read<ApiClient>().post('/v1/rounds/buy', {'size': size, 'key': _key});
      _key = LiveCubit.newKey();
      if (mounted) setState(() => _note = '$size rounds added.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _poor = e.code == 'insufficient_credits';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  static String _wait(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${d.inMinutes.clamp(1, 59)}m';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RoundsInfo?>(
      valueListenable: _hub,
      builder: (context, info, _) {
        if (info == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonList(rows: 3, rowHeight: 52));
        final wait = info.untilRefresh;
        final low = info.available == 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${info.available}', style: AppText.heading(44, color: low ? AppColors.loss : AppColors.text)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(info.available == 1 ? 'round left' : 'rounds left', style: AppText.body(15, color: AppColors.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: info.free == 0 ? 0 : (info.freeNow / info.free).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: AppColors.line,
                valueColor: AlwaysStoppedAnimation(low ? AppColors.loss : AppColors.green),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${info.freeNow} of ${info.free} free rounds'
              '${info.extra > 0 ? '  ·  ${info.extra} extra' : ''}',
              style: AppText.body(13, color: AppColors.textSoft),
            ),
            const SizedBox(height: 4),
            Text(
              wait != null
                  ? 'More free rounds in ${_wait(wait)}.'
                  : 'You get ${info.free} free rounds every ${info.windowHours == info.windowHours.roundToDouble() ? info.windowHours.round() : info.windowHours} hours.',
              style: AppText.body(13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            Text('GET EXTRA ROUNDS', style: AppText.body(12, color: AppColors.textMuted, weight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 8),
            for (final size in info.packs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$size rounds', style: AppText.body(16, weight: FontWeight.w700)),
                          Text('${_price(info, 1)} each', style: AppText.body(12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: AppButton(
                        label: _price(info, size),
                        variant: AppButtonVariant.gold,
                        height: 46,
                        fontSize: 14,
                        loading: _buying == size,
                        onPressed: _buying == null ? () => _buy(size) : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_note!, style: AppText.body(13, color: AppColors.green))),
            if (_error != null) ...[
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: AppText.body(13, color: AppColors.loss))),
              if (_poor)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppButton(
                    label: info.live ? 'Add money' : 'Get free coins',
                    variant: AppButtonVariant.outline,
                    height: 48,
                    onPressed: () {
                      Navigator.of(context).pop();
                      openAddFunds(context);
                    },
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              'Rounds are shared by every game. Each round you play uses one, win or lose. Extra rounds never expire. '
              'Every round uses our servers and storage, and extra rounds help us keep the games running.',
              style: AppText.body(12, color: AppColors.textMuted, height: 1.5),
            ),
          ],
        );
      },
    );
  }

  String _price(RoundsInfo info, int rounds) {
    final v = info.price * rounds;
    return info.live ? PlayMode.money(v, decimals: 0) : '${formatCredits(v, decimals: 0)} cr';
  }
}
