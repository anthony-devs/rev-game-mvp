import 'package:equatable/equatable.dart';

import 'game_type.dart';
import 'model_json.dart';

/// One entry of the server-driven game catalog. Firestore path: `games/{id}`.
/// The lobby builds its tiles from these, so a game can be switched off or reordered
/// without shipping an app update.
class GameInfo extends Equatable {
  const GameInfo({
    required this.id,
    required this.type,
    required this.name,
    this.tag = '',
    this.enabled = true,
    this.comingSoon = false,
    this.minBet = 10,
    this.maxBet = 100000,
    this.rtp = 0.96,
    this.sortOrder = 0,
  });

  final String id;
  final GameType type;
  final String name;

  /// Short label under the name, e.g. "Slots" or "Instant".
  final String tag;
  final bool enabled;
  final bool comingSoon;
  final double minBet;
  final double maxBet;

  /// Return to player, 0.0 to 1.0.
  final double rtp;
  final int sortOrder;

  bool get playable => enabled && !comingSoon;

  GameInfo copyWith({
    String? name,
    String? tag,
    bool? enabled,
    bool? comingSoon,
    double? minBet,
    double? maxBet,
    double? rtp,
    int? sortOrder,
  }) {
    return GameInfo(
      id: id,
      type: type,
      name: name ?? this.name,
      tag: tag ?? this.tag,
      enabled: enabled ?? this.enabled,
      comingSoon: comingSoon ?? this.comingSoon,
      minBet: minBet ?? this.minBet,
      maxBet: maxBet ?? this.maxBet,
      rtp: rtp ?? this.rtp,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory GameInfo.fromJson(Json json) => GameInfo(
        id: parseString(json['id']) ?? '',
        type: GameType.fromName(json['type']),
        name: parseString(json['name']) ?? '',
        tag: parseString(json['tag']) ?? '',
        enabled: parseBool(json['enabled'], true),
        comingSoon: parseBool(json['comingSoon']),
        minBet: parseDouble(json['minBet'], 10),
        maxBet: parseDouble(json['maxBet'], 100000),
        rtp: parseDouble(json['rtp'], 0.96),
        sortOrder: parseInt(json['sortOrder']),
      );

  Json toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'tag': tag,
        'enabled': enabled,
        'comingSoon': comingSoon,
        'minBet': minBet,
        'maxBet': maxBet,
        'rtp': rtp,
        'sortOrder': sortOrder,
      };

  factory GameInfo.fromFirestore(String id, Json data) => GameInfo.fromJson({...data, 'id': id});
  Json toFirestore() => toJson()..remove('id');

  @override
  List<Object?> get props => [id, type, name, tag, enabled, comingSoon, minBet, maxBet, rtp, sortOrder];
}
