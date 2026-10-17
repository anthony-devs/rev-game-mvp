import 'package:flutter/material.dart';

import '../components/core/play_mode.dart';
import '../pages/get_credits_sheet.dart';
import 'deposit_sheet.dart';

/// The "+" button: free demo credits on demo, a real deposit on live.
Future<void> openAddFunds(BuildContext context) => PlayMode.isLive ? showDepositSheet(context) : showGetCredits(context);
