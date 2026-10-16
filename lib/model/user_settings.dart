import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Player preferences. Firestore path: `users/{uid}/settings/preferences`.
/// Also cache this locally so the app starts with the right sound setting offline.
class UserSettings extends Equatable {
  const UserSettings({
    this.soundEnabled = true,
    this.musicEnabled = true,
    this.hapticsEnabled = true,
    this.turboByDefault = false,
    this.reduceMotion = false,
    this.favourites = const [],
  });

  static const UserSettings defaults = UserSettings();

  final bool soundEnabled;
  final bool musicEnabled;
  final bool hapticsEnabled;
  final bool turboByDefault;
  final bool reduceMotion;

  /// Game ids the player starred.
  final List<String> favourites;

  UserSettings copyWith({
    bool? soundEnabled,
    bool? musicEnabled,
    bool? hapticsEnabled,
    bool? turboByDefault,
    bool? reduceMotion,
    List<String>? favourites,
  }) {
    return UserSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      turboByDefault: turboByDefault ?? this.turboByDefault,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      favourites: favourites ?? this.favourites,
    );
  }

  factory UserSettings.fromJson(Json json) => UserSettings(
        soundEnabled: parseBool(json['soundEnabled'], true),
        musicEnabled: parseBool(json['musicEnabled'], true),
        hapticsEnabled: parseBool(json['hapticsEnabled'], true),
        turboByDefault: parseBool(json['turboByDefault']),
        reduceMotion: parseBool(json['reduceMotion']),
        favourites: json['favourites'] is List ? [for (final f in json['favourites'] as List) f.toString()] : const [],
      );

  Json toJson() => {
        'soundEnabled': soundEnabled,
        'musicEnabled': musicEnabled,
        'hapticsEnabled': hapticsEnabled,
        'turboByDefault': turboByDefault,
        'reduceMotion': reduceMotion,
        'favourites': favourites,
      };

  factory UserSettings.fromFirestore(Json data) => UserSettings.fromJson(data);
  Json toFirestore() => toJson();

  @override
  List<Object?> get props => [soundEnabled, musicEnabled, hapticsEnabled, turboByDefault, reduceMotion, favourites];
}
