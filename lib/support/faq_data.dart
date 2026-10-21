import 'package:flutter/material.dart';

import '../model/model.dart';

/// Sections of the Help Centre.
enum FaqCategory { start, coins, fairness, slots, roulette, blackjack, dice, plinko, crash, mines, baccarat, wheel, keno, hilo, account, support }

extension FaqCategoryX on FaqCategory {
  String get label {
    switch (this) {
      case FaqCategory.start:
        return 'Getting started';
      case FaqCategory.coins:
        return 'Coins';
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
      case FaqCategory.mines:
        return 'Mines';
      case FaqCategory.baccarat:
        return 'Baccarat';
      case FaqCategory.wheel:
        return 'Lucky Wheel';
      case FaqCategory.keno:
        return 'Keno';
      case FaqCategory.hilo:
        return 'Hi-Lo';
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
      case FaqCategory.coins:
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
      case FaqCategory.mines:
        return Icons.grid_view_rounded;
      case FaqCategory.baccarat:
        return Icons.style_rounded;
      case FaqCategory.wheel:
        return Icons.data_usage_rounded;
      case FaqCategory.keno:
        return Icons.apps_rounded;
      case FaqCategory.hilo:
        return Icons.swap_vert_rounded;
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
    case GameType.mines:
      return FaqCategory.mines;
    case GameType.baccarat:
      return FaqCategory.baccarat;
    case GameType.wheel:
      return FaqCategory.wheel;
    case GameType.keno:
      return FaqCategory.keno;
    case GameType.hilo:
      return FaqCategory.hilo;
    default:
      return FaqCategory.start;
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
  Faq(FaqCategory.start, 'What is the difference between Coins and Live play?',
      'Coins are free to play with (each coin is worth ₦5, shown for reference only): they have no cash value and cannot be cashed out. Your live balance is used for real-money play. You can switch between them from the balance at the top.'),
  Faq(FaqCategory.start, 'Which games can I play?',
      'Golden Reels and Lucky Sevens (slots), Euro Roulette, Blackjack, Baccarat, Dice, Dash Crash, Plinko, Mines, Lucky Wheel, Keno and Hi-Lo. Every game has a How to play guide: open the game and tap the question mark.'),
  Faq(FaqCategory.start, 'Is my progress saved?',
      'Yes. Your balance, level and history are stored in your account, so they follow you to a new phone when you sign in. Guest accounts are only saved on that sign-in, so link an email to keep them safe.'),
  Faq(FaqCategory.start, 'The app says it cannot reach the server',
      'Check your connection and try again. Your coins are safe, because they live on our server and not on your phone. If it keeps happening, message support from Help.'),

  // ---- coins
  Faq(FaqCategory.coins, 'How do rounds work?',
      'Every round you play, in any game, uses one round. You get 14 free rounds, shared by all games, and they come back 6 hours after the first round of each period. Tap the lightning-bolt counter at the top of any screen to see how many you have left and when more free rounds arrive. Coins and live money each have their own rounds.'),
  Faq(FaqCategory.coins, 'Can I buy more rounds?',
      'Yes. When you run out, open the rounds counter and choose a pack. Each extra round costs 2 coins (or ₦50 in live), taken from your balance. Extra rounds never expire and are used after your free rounds. Every round uses our servers and storage, and the fee helps us keep the games running. Purchases cannot be refunded once made.'),
  Faq(FaqCategory.coins, 'How do I get more coins?',
      'Open the wallet and tap Get free coins. You can claim a daily reward every 24 hours. Claim on consecutive days to build a streak: days 1 to 7 pay 20, 20, 30, 40, 50, 60 and 200 coins. You can also reset your balance back to 200 coins at any time.'),
  Faq(FaqCategory.coins, 'How does the daily streak work?',
      'Claim again within 48 hours of your last claim and the streak grows by one day. Miss that window and it starts again from day 1.'),
  Faq(FaqCategory.coins, 'My balance looks wrong',
      'The server holds your real balance. During a round the app keeps the number steady while the animation plays, then updates it. If it still looks wrong, close and reopen the app. If it is still wrong, open a support ticket and attach a screenshot of your History.'),
  Faq(FaqCategory.coins, 'Why are free coins paused?',
      'Free coins (daily reward, top up, reset) are paused while an account has a restriction, and for a while after a suspension or restriction ends. The banner on the home screen shows when they come back.'),
  Faq(FaqCategory.coins, 'What is the bet cap on probation?',
      'After a suspension or restriction ends, your account is on probation for a short time. You can play, but each bet is capped and free coins stay paused. Everything returns to normal on its own when probation finishes.'),

  // ---- fairness
  Faq(FaqCategory.fairness, 'How are results decided?',
      'Every result is decided on our server before you see it, using a secure random number generator, and it is sealed before you play. The app only shows the result, it never decides it.'),
  Faq(FaqCategory.fairness, 'How do I verify a round?',
      'Open Game history and tap a round, or tap the shield icon in a game. The check confirms the result is the one that was sealed before you bet and that it has not been changed.',
      id: 'fair-verify'),
  Faq(FaqCategory.fairness, 'Why does a round say "pending"?',
      'Some rounds need one extra step before they can be checked. Open the round and tap Complete check.'),
  Faq(FaqCategory.fairness, 'What does RTP mean?',
      'Return to player. A 96% RTP means that over a very long time the game pays back 96 coins for every 100 bet. A single session can be far above or below that.'),

  // ---- slots
  Faq(FaqCategory.slots, 'How do I win on Golden Reels?',
      'Golden Reels has 3 reels and 1 payline. Pick a bet and spin. If the symbols on the line match a winning combination you are paid straight away. Open the Paytable to see every combination. The return to player is 96%.'),
  Faq(FaqCategory.slots, 'What are the bet sizes?',
      'You can bet 10, 20, 50, 100, 200 or 500 per spin (coins in demo, naira in live).'),

  // ---- roulette
  Faq(FaqCategory.roulette, 'Which roulette is it?',
      'European roulette with a single zero (0 to 36). The house edge is 2.70%, which is a return to player of 97.30%.'),
  Faq(FaqCategory.roulette, 'What do the bets pay?',
      'A single number pays 35 to 1. Dozens pay 2 to 1. Red or black, odd or even and low or high pay 1 to 1. When the ball lands on 0, all outside bets lose.'),
  Faq(FaqCategory.roulette, 'How much can I bet?',
      'At least 10 coins per chip and up to 5,000 in total on one spin.'),

  // ---- blackjack
  Faq(FaqCategory.blackjack, 'What are the blackjack rules?',
      'Get closer to 21 than the dealer without going over. Blackjack (an ace and a ten-value card) pays 3 to 2. The dealer stands on every 17. You can double on your first two cards, and split a pair of the same rank once.'),
  Faq(FaqCategory.blackjack, 'How does splitting work?',
      'When your first two cards are the same rank, tap Split. A second bet equal to your first is placed and each card becomes its own hand, played one after the other. You can split once. Split aces get one card each. A 21 after a split pays 1 to 1, not 3 to 2.'),
  Faq(FaqCategory.blackjack, 'I left in the middle of a hand',
      'Your hand is saved on the server. Open Blackjack again and you will be asked to carry on with it. You cannot start a new hand until it is finished.'),

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

  // ---- mines
  Faq(FaqCategory.mines, 'How does Mines work?',
      'Choose your bet and how many mines hide on the 5 by 5 board, then open tiles. Every safe tile raises your multiplier. Cash out any time to collect your bet times the multiplier. If you open a mine, the round ends and the bet is lost.'),
  Faq(FaqCategory.mines, 'How is the multiplier worked out?',
      'It follows the real chance of getting this far. More mines means each safe tile is rarer, so the multiplier climbs faster. The return to player is 96%, and the multiplier for your next tile is shown on screen.'),
  Faq(FaqCategory.mines, 'I left in the middle of a round',
      'Your round is saved on the server. Open Mines again and you will carry on where you stopped. You cannot start a new round until it is finished.'),

  // ---- baccarat
  Faq(FaqCategory.baccarat, 'How does Baccarat work?',
      'Bet on Player, Banker or Tie. Two cards are dealt to each side and a third card may follow by fixed rules. The hand closest to 9 wins. Aces count 1, tens and face cards count 0, and only the last digit of the total counts.'),
  Faq(FaqCategory.baccarat, 'What do the bets pay?',
      'Player pays 1 to 1. Banker pays 1 to 1 minus a 5% commission, because the Banker wins slightly more often. Tie pays 8 to 1. If the round ties, Player and Banker bets are returned.'),

  // ---- lucky wheel
  Faq(FaqCategory.wheel, 'How does the Lucky Wheel work?',
      'Choose a risk level and your bet, then spin. The wheel has 20 equal segments and the one it stops on pays its multiplier on your bet. Low risk has many small wins. High risk has mostly empty segments and a few big ones. The return to player is 96%.'),

  // ---- keno
  Faq(FaqCategory.keno, 'How does Keno work?',
      'Pick 1 to 10 numbers from 1 to 40, set your bet and play. Ten numbers are drawn. The more of your picks are drawn, the bigger the multiplier. The pay table for your number of picks is shown on screen. The return to player is 96%.'),
  Faq(FaqCategory.keno, 'How many numbers should I pick?',
      'Fewer picks win more often but pay less. More picks win rarely but pay a lot more when most of them hit. Every choice has the same return to player.'),

  // ---- hi-lo
  Faq(FaqCategory.hilo, 'How does Hi-Lo work?',
      'A card is shown. Guess whether the next card is higher or lower. Aces are low and kings are high, and the same rank counts as a win for both guesses. Every right guess raises your multiplier by the real chance of that guess. Cash out any time. A wrong guess loses the bet.'),
  Faq(FaqCategory.hilo, 'I left in the middle of a round',
      'Your round is saved on the server. Open Hi-Lo again and you will carry on where you stopped. You cannot start a new round until it is finished.'),

  // ---- account
  Faq(FaqCategory.account, 'How do play limits work?',
      'In Settings, open Play limits. You can turn on reality check reminders, a loss limit per session, a highest bet, or take a break. These are set by you, and they apply to every game.'),
  Faq(FaqCategory.account, 'How do I delete my account?',
      'Open Settings, then your profile, then Delete account. This permanently removes your profile, coins, level, history and support messages. It is not possible while your account has an open restriction or probation.'),
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
