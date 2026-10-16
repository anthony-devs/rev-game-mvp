import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../model/model.dart';
import '../../model/model_json.dart';
import '../../support/support_models.dart';

/// A server seed that was revealed after the player rotated.
class RevealedSeedDoc {
  const RevealedSeedDoc({
    required this.serverSeedHash,
    required this.serverSeed,
    required this.clientSeed,
    required this.nonceEnd,
    this.revealedAt,
  });

  final String serverSeedHash;
  final String serverSeed;
  final String clientSeed;
  final int nonceEnd;
  final DateTime? revealedAt;
}

/// The profile document: who the player is plus the settings they control.
class UserProfile {
  const UserProfile({required this.user, required this.settings, required this.limits});

  final AppUser user;
  final UserSettings settings;
  final PlayLimits limits;
}

/// Everything the app stores about a player in Firestore.
///
/// ```
/// users/{uid}                  profile + settings + limits   (player edits)
/// users/{uid}/wallet/current   balance, daily claim           (server owns)
/// users/{uid}/progress/current level, xp, streak              (server owns)
/// ```
/// Wallet and progress are read only for the app. The rules (firestore.rules)
/// let the app create them once; after that only the game server changes them.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  /// Credits every new player starts with. Must match firestore.rules.
  static const double startingBalance = 10000;

  final FirebaseFirestore _db;

  DocumentReference<Json> _user(String uid) => _db.collection('users').doc(uid);
  DocumentReference<Json> _wallet(String uid) => _user(uid).collection('wallet').doc('current');
  DocumentReference<Json> _progress(String uid) => _user(uid).collection('progress').doc('current');
  CollectionReference<Json> _rounds(String uid) => _user(uid).collection('rounds');

  // ---- Live data -----------------------------------------------------------

  /// Emits `null` until the profile document exists.
  Stream<UserProfile?> watchProfile(String uid) {
    return _user(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return UserProfile(
        user: AppUser.fromFirestore(uid, data),
        settings: UserSettings.fromFirestore(parseMap(data['settings'])),
        limits: PlayLimits.fromFirestore(parseMap(data['limits'])),
      );
    });
  }

  Stream<Wallet?> watchWallet(String uid) {
    return _wallet(uid).snapshots().map((snap) {
      final data = snap.data();
      return data == null ? null : Wallet.fromFirestore(uid, data);
    });
  }

  Stream<PlayerProgress?> watchProgress(String uid) {
    return _progress(uid).snapshots().map((snap) {
      final data = snap.data();
      return data == null ? null : PlayerProgress.fromFirestore(data);
    });
  }

  /// Bans, suspensions, restrictions and investigations. Live, so a staff action
  /// reaches the open app within a second. Empty (good standing) if none.
  Stream<AccountStanding> watchStanding(String uid) {
    return _db.collection('users').doc(uid).collection('account').doc('standing').snapshots().map((snap) {
      final data = snap.data();
      return data == null ? AccountStanding.good : AccountStanding.fromFirestore(data);
    });
  }

  /// The player's support tickets, newest activity first. Live.
  Stream<List<Ticket>> watchTickets(String uid) {
    // Sorted in memory so no composite Firestore index is needed.
    return _db.collection('users').doc(uid).collection('tickets').snapshots().map((s) {
      final list = [for (final d in s.docs) Ticket.fromFirestore(d.id, d.data())];
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  /// One conversation, oldest first. Live, so a reply from support appears on its own.
  Stream<List<TicketMessage>> watchTicketMessages(String uid, String ticketId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('tickets')
        .doc(ticketId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => [for (final d in s.docs) TicketMessage.fromFirestore(d.id, d.data())]);
  }

  /// Newest rounds first. Filter by game with [game].
  Stream<List<GameRound>> watchRounds(String uid, {GameType? game, int limit = 100}) {
    // Filtered in memory so no composite Firestore index is needed.
    return _rounds(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                if (game == null || d.data()['game'] == game.name) GameRound.fromFirestore(d.id, d.data()),
            ]);
  }

  /// One round, for the details sheet.
  Future<GameRound?> round(String uid, String id) async {
    final snap = await _rounds(uid).doc(id).get();
    final data = snap.data();
    return data == null ? null : GameRound.fromFirestore(id, data);
  }

  /// Server seeds revealed after a rotate, newest first.
  Stream<List<RevealedSeedDoc>> watchSeedHistory(String uid) {
    return _user(uid)
        .collection('seed_history')
        .orderBy('revealedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((s) => [
              for (final d in s.docs)
                RevealedSeedDoc(
                  serverSeedHash: parseString(d.data()['serverSeedHash']) ?? d.id,
                  serverSeed: parseString(d.data()['serverSeed']) ?? '',
                  clientSeed: parseString(d.data()['clientSeed']) ?? '',
                  nonceEnd: parseInt(d.data()['nonceEnd']),
                  revealedAt: parseDate(d.data()['revealedAt']),
                ),
            ]);
  }

  /// The game catalog. Emits the built-in list if the collection is empty or unreachable.
  Stream<List<GameInfo>> watchGames() {
    return _db.collection('games').snapshots().map((s) => [
          for (final d in s.docs) GameInfo.fromFirestore(d.id, d.data()),
        ]);
  }

  // ---- First sign in -------------------------------------------------------

  /// Creates the player's documents if they are missing and stamps the login
  /// time. Safe to call on every sign in. Never throws, because the app must
  /// stay usable offline; it simply tries again next launch.
  Future<void> ensureDocs(AppUser auth) async {
    try {
      final userRef = _user(auth.id);
      final walletRef = _wallet(auth.id);
      final progressRef = _progress(auth.id);

      await _db.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        final walletSnap = await tx.get(walletRef);
        final progressSnap = await tx.get(progressRef);

        if (userSnap.exists) {
          tx.update(userRef, {'lastLoginAt': FieldValue.serverTimestamp()});
        } else {
          tx.set(userRef, {
            'displayName': auth.displayName,
            'email': auth.email,
            'photoUrl': auth.photoUrl,
            'isAnonymous': auth.isAnonymous,
            'ageConfirmed': false,
            'status': UserStatus.active.name,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'settings': UserSettings.defaults.toFirestore(),
            'limits': PlayLimits.defaults.toFirestore(),
          });
        }

        if (!walletSnap.exists) {
          tx.set(walletRef, {
            'balance': startingBalance,
            'lastDailyClaimAt': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (!progressSnap.exists) {
          tx.set(progressRef, PlayerProgress.initial.toFirestore());
        }
      }).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  // ---- Player edits --------------------------------------------------------

  Future<void> saveSettings(String uid, UserSettings settings) {
    return _user(uid).update({'settings': settings.toFirestore()});
  }

  Future<void> saveLimits(String uid, PlayLimits limits) {
    return _user(uid).update({'limits': limits.toFirestore()});
  }

  Future<void> rename(String uid, String displayName) {
    return _user(uid).update({'displayName': displayName.trim()});
  }

  Future<void> confirmAge(String uid) {
    return _user(uid).update({'ageConfirmed': true});
  }
}
