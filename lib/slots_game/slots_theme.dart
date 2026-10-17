import 'package:flutter/material.dart';
import 'package:rev_game_mvp/components/components.dart';

// The slots files share the app palette. These names are kept so reel_widget,
// symbol_view and the painters did not need to change.
Color get kGold => AppColors.gold;
Color get kGreen => AppColors.green;
Color get kRed => AppColors.loss;
Color get kBg => AppColors.bg;
Color get kSurface => AppColors.sheet;
Color get kSurface2 => AppColors.surfaceAlt;
Color get kMuted => AppColors.textDim;
Color get kText2 => AppColors.textSoft;

String fmt(double v) => formatCredits(v);

TextStyle slotsInter(double size, FontWeight w, {Color? color, double? ls, double? height}) =>
    AppText.body(size, weight: w, color: color, letterSpacing: ls, height: height);

TextStyle slotsOrbitron(double size, Color color, {List<Shadow>? shadows}) => AppText.number(size, color: color, shadows: shadows);
