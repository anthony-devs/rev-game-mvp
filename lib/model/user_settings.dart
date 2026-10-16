import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Player preferences. Firestore path: `users/{uid}/settings/preferences`.
/// Also cache this locally so the app starts with the right sound setting offline.
class UserSettings extends Equatable {
  const UserSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.turboByDefault = false,
    this.reduceMotion = false,
  });

  static const UserSettings defaults = UserSettings();

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool turboByDefault;
  final bool reduceMotion;

  UserSettings copyWith({bool? soundEnabled, bool? hapticsEnabled, bool? turboByDefault, bool? reduceMotion}) {
    return UserSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      turboByDefault: turboByDefault ?? this.turboByDefault,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  factory UserSettings.fromJson(Json json) => UserSettings(
        soundEnabled: parseBool(json['soundEnabled'], true),
        hapticsEnabled: parseBool(json['hapticsEnabled'], true),
        turboByDefault: parseBool(json['turboByDefault']),
        reduceMotion: parseBool(json['reduceMotion']),
      );

  Json toJson() => {
        'soundEnabled': soundEnabled,
        'hapticsEnabled': hapticsEnabled,
        'turboByDefault': turboByDefault,
        'reduceMotion': reduceMotion,
      };

  factory UserSettings.fromFirestore(Json data) => UserSettings.fromJson(data);
  Json toFirestore() => toJson();

  @override
  List<Object?> get props => [soundEnabled, hapticsEnabled, turboByDefault, reduceMotion];
}
