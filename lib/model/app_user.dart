import 'package:equatable/equatable.dart';

import 'model_json.dart';

enum UserStatus { active, suspended, deleted }

/// The signed-in player. Firestore path: `users/{id}`.
///
/// ```dart
/// final user = AppUser.fromFirestore(doc.id, doc.data()!);
/// emit(state.copyWith(user: user.copyWith(lastLoginAt: DateTime.now())));
/// ```
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    this.displayName = 'Player',
    this.email,
    this.photoUrl,
    this.isAnonymous = false,
    this.ageConfirmed = false,
    this.status = UserStatus.active,
    this.createdAt,
    this.lastLoginAt,
  });

  /// Signed-out placeholder for BLoC states. Check with [isEmpty].
  static const AppUser empty = AppUser(id: '');

  /// Firebase Auth uid.
  final String id;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final bool isAnonymous;

  /// The player passed the age gate.
  final bool ageConfirmed;
  final UserStatus status;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => id.isNotEmpty;
  bool get canPlay => isNotEmpty && ageConfirmed && status == UserStatus.active;

  /// First letter for avatar fallbacks.
  String get initial => displayName.isEmpty ? '?' : String.fromCharCode(displayName.runes.first).toUpperCase();

  AppUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    bool? isAnonymous,
    bool? ageConfirmed,
    UserStatus? status,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return AppUser(
      id: id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      ageConfirmed: ageConfirmed ?? this.ageConfirmed,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  factory AppUser.fromJson(Json json) => AppUser(
        id: parseString(json['id']) ?? '',
        displayName: parseString(json['displayName']) ?? 'Player',
        email: parseString(json['email']),
        photoUrl: parseString(json['photoUrl']),
        isAnonymous: parseBool(json['isAnonymous']),
        ageConfirmed: parseBool(json['ageConfirmed']),
        status: enumByName(UserStatus.values, json['status'], UserStatus.active),
        createdAt: parseDate(json['createdAt']),
        lastLoginAt: parseDate(json['lastLoginAt']),
      );

  Json toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'isAnonymous': isAnonymous,
        'ageConfirmed': ageConfirmed,
        'status': status.name,
        'createdAt': dateToMs(createdAt),
        'lastLoginAt': dateToMs(lastLoginAt),
      };

  factory AppUser.fromFirestore(String id, Json data) => AppUser.fromJson({...data, 'id': id});

  /// The document id is not stored inside the document.
  Json toFirestore() => {
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'isAnonymous': isAnonymous,
        'ageConfirmed': ageConfirmed,
        'status': status.name,
        'createdAt': createdAt,
        'lastLoginAt': lastLoginAt,
      };

  @override
  List<Object?> get props => [id, displayName, email, photoUrl, isAnonymous, ageConfirmed, status, createdAt, lastLoginAt];
}
