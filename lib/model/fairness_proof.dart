import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Commit and reveal data for one round (the "Verify a round" screen).
///
/// Before the round the server publishes only [serverSeedHash]. After it settles the
/// server reveals [serverSeed], and anyone can hash it and compare.
class FairnessProof extends Equatable {
  const FairnessProof({
    required this.serverSeedHash,
    this.serverSeed,
    this.clientSeed = '',
    this.nonce = 0,
  });

  final String serverSeedHash;

  /// `null` until the round is settled.
  final String? serverSeed;
  final String clientSeed;
  final int nonce;

  bool get isRevealed => serverSeed != null && serverSeed!.isNotEmpty;

  factory FairnessProof.fromJson(Json json) => FairnessProof(
        serverSeedHash: parseString(json['serverSeedHash']) ?? '',
        serverSeed: parseString(json['serverSeed']),
        clientSeed: parseString(json['clientSeed']) ?? '',
        nonce: parseInt(json['nonce']),
      );

  Json toJson() => {
        'serverSeedHash': serverSeedHash,
        'serverSeed': serverSeed,
        'clientSeed': clientSeed,
        'nonce': nonce,
      };

  @override
  List<Object?> get props => [serverSeedHash, serverSeed, clientSeed, nonce];
}
