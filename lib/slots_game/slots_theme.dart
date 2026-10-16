import 'package:flutter/material.dart';
import 'package:rev_game_mvp/components/components.dart';

// The slots files share the app palette. These names are kept so reel_widget,
// symbol_view and the painters did not need to change.
const kGold = AppColors.gold;
const kGreen = AppColors.green;
const kRed = AppColors.loss;
const kBg = AppColors.bg;
const kSurface = AppColors.sheet;
const kSurface2 = AppColors.surfaceAlt;
const kMuted = AppColors.textDim;
const kText2 = AppColors.textSoft;

String fmt(double v) => formatCredits(v);

TextStyle slotsInter(double size, FontWeight w, {Color color = Colors.white, double? ls, double? height}) =>
    AppText.body(size, weight: w, color: color, letterSpacing: ls, height: height);

TextStyle slotsOrbitron(double size, Color color, {List<Shadow>? shadows}) => AppText.number(size, color: color, shadows: shadows);
