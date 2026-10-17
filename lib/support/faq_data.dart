import 'package:flutter/material.dart';

import '../model/model.dart';

/// Sections of the Help Centre.
enum FaqCategory { start, credits, fairness, slots, roulette, blackjack, dice, plinko, crash, account, support }

extension FaqCategoryX on FaqCategory {
  String get label {
    switch (this) {
      case FaqCategory.start:
        return 'Getting started';
      case FaqCategory.credits:
        return 'Credits';
      case FaqCategory.fairness:
        return 'Fairness';
      case FaqCategory.slots:
        return 'Slots';
      case FaqCategory.roulette:
        return 'Roulette';
      case FaqCategory.blackjack:
        return 'Blackjack';
      case FaqCategory.dice:
        return 'Dice';
      case FaqCategory.plinko:
        return 'Plinko';
      case FaqCategory.crash:
        return 'Crash';
      case FaqCategory.account:
        return 'Account & limits';
      case FaqCategory.support:
        return 'Bans & appeals';
    }
  }

  IconData get icon {
    switch (this) {
      case FaqCategory.start:
        return Icons.rocket_launch_outlined;
      case FaqCategory.credits:
        return Icons.toll_rounded;
      case FaqCategory.fairness:
        return Icons.verified_user_outlined;
      case FaqCategory.slots:
        return Icons.grid_view_rounded;
      case FaqCategory.roulette:
        return Icons.album_outlined;
      case FaqCategory.blackjack:
        return Icons.style_outlined;
      case FaqCategory.dice:
        return Icons.casino_outlined;
      case FaqCategory.plinko:
        return Icons.scatter_plot_rounded;
      case FaqCategory.crash:
        return Icons.show_chart_rounded;
      case FaqCategory.account:
        return Icons.tune_rounded;
      case FaqCategory.support:
        return Icons.gavel_rounded;
    }
  }
}

/// The Help Centre section for a game, so "Help" inside a game opens on its answers.
FaqCategory faqCategoryFor(GameType t) {
  switch (t) {
    case GameType.slots:
      return FaqCategory.slots;
    case GameType.roulette:
      return FaqCategory.roulette;
    case GameType.blackjack:
      return FaqCategory.blackjack;
    case GameType.dice:
      return FaqCategory.dice;
    case GameType.plinko:
      return FaqCategory.plinko;
    case GameType.crash:
      return FaqCategory.crash;
  }
}

class Faq {
  const Faq(this.category, this.q, this.a, {this.id = ''});
  final FaqCategory category;
  final String q;
  final String a;

  /// Lets another screen open one answer, e.g. `fair-verify`.
  final String id;
}

const List<Faq> kFaqs = [
  // ---- getting started
  Faq(FaqCategory.start, 'Are credits real money?',
      'No. Credits are virtual. You cannot buy, sell, deposit or withdraw them, and they have no cash value. REV GAMES is a demo for fun only.'),
  Faq(FaqCategory.start, 'Which games can I play?',
      'Golden Reels (slots), Euro Roulette, Blackjack, Dice and Dash Crash. Every game has a How to play guide: open the game and tap the question mark.'),
  Faq(FaqCategory.start, 'Is my progress saved?',
      'Yes. Your balance, level and history are stored in your account, so they follow you to a new phone when you sign in. Guest accounts are only saved on that sign-in, so link an email to keep them safe.'),
  Faq(FaqCategory.start, 'The app says it cannot reach the server',
      'Check your connection and try again. Your credits are safe, because they live on our server and not on your phone. If it keeps happening, message support from Help.'),

  // ---- credits
  Faq(FaqCategory.credits, 'How do rounds work?',
      'Every round you play, in any game, uses one round. You get 14 free rounds, shared by all games, and they come back 6 hours after the first round of each period. Tap the lightning-bolt counter at the top of any screen to see how many you have left and when more free rounds arrive. Demo credits and real money each have their own rounds.'),
  Faq(FaqCategory.credits, 'Can I buy more rounds?',
      'Yes. When you run out, open the rounds counter and choose a pack. Each extra round costs 50 (credits in demo, naira in live), taken from your balance. Extra rounds never expire and are used after your free rounds. Every round uses our servers and storage, and the fee helps us keep the games running. Purchases cannot be refunded once made.'),
  Faq(FaqCategory.credits, 'How do I get more credits?',
      'Open the wallet and tap Get demo credits. You can claim a daily reward every 24 hours. Claim on consecutive days to build a streak: days 1 to 7 pay 1,000, 1,000, 1,500, 2,000, 2,500, 3,000 and 10,000. You can also reset your balance back to 10,000 at any time.'),
  Faq(FaqCategory.credits, 'How does the daily streak work?',
      'Claim again within 48 hours of your last claim and the streak grows by one day. Miss that window and it starts again from day 1.'),
  Faq(FaqCategory.credits, 'My balance looks wrong',
      'The server holds your real balance. During a round the app keeps the number steady while the animation plays, then updates it. If it still looks wrong, close and reopen the app. If it is still wrong, open a support ticket and attach a screenshot of your History.'),
  Faq(FaqCategory.credits, 'Why are free credits paused?',
      'Free credits (daily reward, top up, reset) are paused while an account has a restriction, and for a while after a suspension or restriction ends. The banner on the home screen shows when they come back.'),
  Faq(FaqCategory.credits, 'What is the bet cap on probation?',
      'After a suspension or restriction ends, your account is on probation for a short time. You can play, but each bet is capped and free credits stay paused. Everything returns to normal on its own when probation finishes.'),

  // ---- fairness
  Faq(FaqCategory.fairness, 'How are results decided?',
      'Every result is decided on our server before you see it, using a random number generator tied to a seed we commit to in advance. The app only shows the result, it never decides it.'),
  Faq(FaqCategory.fairness, 'How do I verify a round?',
      'Open Game history and tap a round, or tap the shield icon in a game. We publish the hash of the server seed before you play. After you rotate your seed we reveal the old one, and the check hashes it and replays the round. If it matches, the result was fixed before you bet.',
      id: 'fair-verify'),
  Faq(FaqCategory.fairness, 'Why does a round say "pending"?',
      'The server seed is secret until you rotate. Rotate your seed on the Fairness screen to reveal it, then every round that used it can be verified.'),
  Faq(FaqCategory.fairness, 'What does RTP mean?',
      'Return to player. A 96% RTP means that over a very long time the game pays back 96 credits for every 100 bet. A single session can be far above or below that.'),

  // ---- slots
  Faq(FaqCategory.slots, 'How do I win on Golden Reels?',
      'Golden Reels has 3 reels and 1 payline. Pick a bet and spin. If the symbols on the line match a winning combination you are paid straight away. Open the Paytable to see every combination. The return to player is 96%.'),
  Faq(FaqCategory.slots, 'What are the bet sizes?',
      'You can bet 10, 20, 50, 100, 200, 500 or 1,000 credits per spin.'),

  // ---- roulette
  Faq(FaqCategory.roulette, 'Which roulette is it?',
      'European roulette with a single zero (0 to 36). The house edge is 2.70%, which is a return to player of 97.30%.'),
  Faq(FaqCategory.roulette, 'What do the bets pay?',
      'A single number pays 35 to 1. Dozens pay 2 to 1. Red or black, odd or even and low or high pay 1 to 1. When the ball lands on 0, all outside bets lose.'),
  Faq(FaqCategory.roulette, 'How much can I bet?',
      'At least 10 credits per chip and up to 100,000 credits in total on one spin.'),

  // ---- blackjack
  Faq(FaqCategory.blackjack, 'What are the blackjack rules?',
      'Get closer to 21 than the dealer without going over. Blackjack (an ace and a ten-value card) pays 3 to 2. The dealer stands on every 17. You can double on your first two cards.'),
  Faq(FaqCategory.blackjack, 'I left in the middle of a hand',
      'Your hand is saved on the server. Open Blackjack again and you will be asked to carry on with it. You cannot start a new hand until it is finished.'),
  Faq(FaqCategory.blackjack, 'Why can I not rotate my seed?',
      'A seed cannot change while a hand is open, because the deck for that hand was shuffled with it. Finish the hand, then rotate.'),

  // ---- dice
  Faq(FaqCategory.dice, 'How does Dice work?',
      'Choose a target and Over or Under. A number from 0 to 100 is rolled. Your target can be anywhere from 2 to 98. If it lands on your side, you win. A smaller chance pays a bigger multiplier. The house edge is 3%.'),

  // ---- plinko
  Faq(FaqCategory.plinko, 'How does Plinko work?',
      'Pick a risk level and the number of rows, then drop the ball. At every peg it goes left or right with equal chance and lands in a slot. Each slot pays a multiplier on your bet. The middle slots are the most likely and pay the least. The edges are rare and pay the most.'),
  Faq(FaqCategory.plinko, 'What do the risk levels change?',
      'Low risk has smaller, more even multipliers. High risk has very big edge multipliers but pays less than your bet in most of the middle slots. More rows give more slots and bigger edge multipliers. The return to player is shown on the screen and is the same for every setting.'),
  Faq(FaqCategory.plinko, 'Why is my maximum bet lower on some settings?',
      'A single drop can never pay more than a fixed limit, so settings with a very large top multiplier have a lower maximum bet. The maximum for the board on screen is shown under the bet.'),

  // ---- crash
  Faq(FaqCategory.crash, 'How does Crash work?',
      'The multiplier climbs from 1x. Cash out before it crashes and you win your bet times the multiplier. If it crashes first, you lose the bet. You can set an automatic cash out.'),
  Faq(FaqCategory.crash, 'I lost connection during a round',
      'The round carries on on the server. Reopen the game and, if you set an automatic cash out, it still applies. Open History to see how the round ended.'),

  // ---- account
  Faq(FaqCategory.account, 'How do play limits work?',
      'In Settings, open Play limits. You can turn on reality check reminders, a loss limit per session, a highest bet, or take a break. These are set by you, and they apply to every game.'),
  Faq(FaqCategory.account, 'How do I delete my account?',
      'Open Settings, then your profile, then Delete account. This permanently removes your profile, credits, level, history and support messages. It is not possible while your account has an open restriction or probation.'),
  Faq(FaqCategory.account, 'I cannot sign in',
      'Use Forgot password on the sign in screen to reset it by email. If you used phone sign in, check you are using the same number. If you are still stuck, message support from the Help Centre.'),

  // ---- bans & appeals
  Faq(FaqCategory.support, 'Why is my account restricted?',
      'The screen you see when you open the app shows the reason and what happens next. A ban, suspension, payout restriction or investigation stops play until it ends or is lifted.',
      id: 'restricted'),
  Faq(FaqCategory.support, 'How do I appeal?',
      'On the restriction screen tap Appeal. Explain what happened in at least 20 characters, and attach screenshots, a video or a PDF if they help (up to 5 files, 25 MB each). You can have one appeal open at a time. If it is rejected you can appeal again after 24 hours.',
      id: 'appeal'),
  Faq(FaqCategory.support, 'How long does an appeal take?',
      'Our team reviews every appeal. This screen updates by itself the moment we decide, so you do not need to keep checking.'),
  Faq(FaqCategory.support, 'Can I still contact support while restricted?',
      'Yes. Help and support always work, even when play is blocked. Open a ticket from the Help Centre.'),
];
