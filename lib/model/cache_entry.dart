import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Wraps any cached value with the time it was saved, so a repository can decide
/// between "use the cache" and "fetch again".
///
/// ```dart
/// final entry = CacheEntry(data: games, cachedAt: DateTime.now(), ttl: const Duration(hours: 6));
/// final raw = jsonEncode(entry.toJson((list) => [for (final g in list) g.toJson()]));
/// ...
/// final back = CacheEntry.fromJson(jsonDecode(raw), (j) => [for (final g in j as List) GameInfo.fromJson(g)]);
/// if (back.isFresh) emit(GamesLoaded(back.data));   // else refetch from Firestore
/// ```
class CacheEntry<T> extends Equatable {
  const CacheEntry({required this.data, required this.cachedAt, this.ttl = const Duration(hours: 1)});

  final T data;
  final DateTime cachedAt;
  final Duration ttl;

  DateTime get expiresAt => cachedAt.add(ttl);
  bool isExpired([DateTime? now]) => !(now ?? DateTime.now()).isBefore(expiresAt);
  bool get isFresh => !isExpired();

  CacheEntry<T> copyWith({T? data, DateTime? cachedAt, Duration? ttl}) {
    return CacheEntry<T>(data: data ?? this.data, cachedAt: cachedAt ?? this.cachedAt, ttl: ttl ?? this.ttl);
  }

  /// [dataToJson] turns the payload into something JSON-encodable.
  Json toJson(Object? Function(T data) dataToJson) => {
        'data': dataToJson(data),
        'cachedAt': dateToMs(cachedAt),
        'ttlSeconds': ttl.inSeconds,
      };

  factory CacheEntry.fromJson(Json json, T Function(Object? raw) dataFromJson) => CacheEntry<T>(
        data: dataFromJson(json['data']),
        cachedAt: parseDate(json['cachedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        ttl: Duration(seconds: parseInt(json['ttlSeconds'], 3600)),
      );

  @override
  List<Object?> get props => [data, cachedAt, ttl];
}
