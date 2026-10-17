import 'package:flutter/foundation.dart';

import '../../model/model_json.dart';

/// How many rounds a player can still play, as the server last said. Rounds are shared by every game:
/// some free ones that refresh over time, plus extra ones the player bought.
class RoundsInfo {
  const RoundsInfo({
    required this.live,
    required this.free,
    required this.freeLeft,
    required this.extra,
    required this.price,
    required this.packs,
    required this.windowHours,
    this.resetsAt,
    this.enabled = true,
  });

  final bool live;
  final bool enabled;

  /// Free rounds per window, and how many are left in the current one.
  final int free;
  final int freeLeft;

  /// Bought rounds still unused. They never expire.
  final int extra;

  /// Price of one extra round (in the wallet's own money or credits).
  final double price;
  final List<int> packs;
  final double windowHours;

  /// When the free rounds come back. Null before the first round of a window.
  final DateTime? resetsAt;

  factory RoundsInfo.fromJson(Json j) => RoundsInfo(
        live: j['live'] == true,
        enabled: j['enabled'] != false,
        free: parseInt(j['free'], 14),
        freeLeft: parseInt(j['freeLeft']),
        extra: parseInt(j['extra']),
        price: parseDouble(j['price'], 50),
        packs: [for (final p in (j['packs'] is List ? j['packs'] as List : const [])) parseInt(p)].where((p) => p > 0).toList(),
        windowHours: parseDouble(j['windowHours'], 6),
        resetsAt: parseDate(j['resetsAt']),
      );

  /// What the server refused with: nothing left now, free rounds back after [seconds].
  factory RoundsInfo.refused(Json j) => RoundsInfo(
        live: j['live'] == true,
        free: 14,
        freeLeft: 0,
        extra: 0,
        price: parseDouble(j['price'], 50),
        packs: [for (final p in (j['packs'] is List ? j['packs'] as List : const [])) parseInt(p)].where((p) => p > 0).toList(),
        windowHours: 6,
        resetsAt: DateTime.now().add(Duration(seconds: parseInt(j['secondsLeft']))),
      );

  bool get _refreshed => resetsAt != null && !DateTime.now().isBefore(resetsAt!);

  /// Free rounds the player has right now (a finished window counts as full again).
  int get freeNow => _refreshed ? free : freeLeft;

  /// Everything the player can play right now.
  int get available => freeNow + extra;

  /// Time until the free rounds come back, or null when they are not waiting.
  Duration? get untilRefresh {
    if (resetsAt == null || _refreshed) return null;
    return resetsAt!.difference(DateTime.now());
  }
}

/// The latest [RoundsInfo] for each wallet. The API client feeds it from every answer that carries
/// a `rounds` block, so the counter stays right without extra requests.
class RoundsHub {
  RoundsHub._();

  static final ValueNotifier<RoundsInfo?> demo = ValueNotifier<RoundsInfo?>(null);
  static final ValueNotifier<RoundsInfo?> live = ValueNotifier<RoundsInfo?>(null);

  static ValueNotifier<RoundsInfo?> of(bool isLive) => isLive ? live : demo;

  static void apply(Json response) {
    final r = response['rounds'];
    if (r is! Map) return;
    final info = RoundsInfo.fromJson(parseMap(r));
    of(info.live).value = info;
  }

  static void applyRefusal(Json response) {
    final info = RoundsInfo.refused(response);
    of(info.live).value = info;
  }

  static void clear() {
    demo.value = null;
    live.value = null;
  }
}
