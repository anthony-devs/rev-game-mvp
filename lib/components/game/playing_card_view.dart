import 'package:flutter/material.dart';

import '../core/app_text.dart';

enum CardSuit { spades, hearts, diamonds, clubs }

extension CardSuitX on CardSuit {
  /// \uFE0E forces the plain text glyph, so iOS does not swap in a colour emoji.
  String get symbol => const {
        CardSuit.spades: '\u2660\uFE0E',
        CardSuit.hearts: '\u2665\uFE0E',
        CardSuit.diamonds: '\u2666\uFE0E',
        CardSuit.clubs: '\u2663\uFE0E',
      }[this]!;

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;
}

/// One playing card. Set [faceDown] for the dealer's hidden card.
///
/// ```dart
/// PlayingCardView(rank: 'A', suit: CardSuit.spades)
/// PlayingCardView(rank: '', suit: CardSuit.spades, faceDown: true)
/// ```
class PlayingCardView extends StatelessWidget {
  const PlayingCardView({super.key, required this.rank, required this.suit, this.faceDown = false, this.width = 64});

  final String rank;
  final CardSuit suit;
  final bool faceDown;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final ink = suit.isRed ? const Color(0xFFE5383B) : const Color(0xFF111111);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * .14),
        color: faceDown ? const Color(0xFF2A1A4A) : Colors.white,
        border: Border.all(color: faceDown ? const Color(0xFFB26BFF) : Colors.black12, width: faceDown ? 2 : 1),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: faceDown
          ? Center(child: Container(width: width * .5, height: width * .5, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFB26BFF), width: 2))))
          : Stack(
              children: [
                Positioned(
                  left: width * .12,
                  top: width * .08,
                  child: Column(children: [
                    Text(rank, style: AppText.body(width * .30, weight: FontWeight.w800, color: ink, height: 1)),
                    Text(suit.symbol, style: TextStyle(fontSize: width * .24, color: ink, height: 1)),
                  ]),
                ),
                Center(child: Text(suit.symbol, style: TextStyle(fontSize: width * .5, color: ink, height: 1))),
              ],
            ),
    );
  }
}

/// Overlapping row of cards.
///
/// ```dart
/// CardHand(cards: [CardData('K', CardSuit.hearts), CardData('7', CardSuit.clubs)], label: 'YOU', total: 17)
/// ```
class CardData {
  const CardData(this.rank, this.suit, {this.faceDown = false});
  final String rank;
  final CardSuit suit;
  final bool faceDown;
}

class CardHand extends StatelessWidget {
  const CardHand({super.key, required this.cards, this.label, this.total, this.cardWidth = 64, this.overlap = .45});

  final List<CardData> cards;
  final String? label;
  final int? total;
  final double cardWidth;

  /// Fraction of each card that is covered by the next one.
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * (1 - overlap);
    final w = cards.isEmpty ? 0.0 : step * (cards.length - 1) + cardWidth;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(total == null ? label! : '$label  |  $total', style: AppText.label()),
          ),
        SizedBox(
          width: w,
          height: cardWidth * 1.4,
          child: Stack(
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  left: step * i,
                  child: PlayingCardView(rank: cards[i].rank, suit: cards[i].suit, faceDown: cards[i].faceDown, width: cardWidth),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
