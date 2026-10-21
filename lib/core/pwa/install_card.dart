import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../games/game_support.dart' show showToast;
import 'pwa_install.dart';

/// "Add REV GAMES to your home screen". Only appears in a browser tab, never inside the installed app.
class InstallCard extends StatelessWidget {
  const InstallCard({super.key});

  Future<void> _tap(BuildContext context) async {
    if (PwaInstall.canPrompt) {
      final ok = await PwaInstall.prompt();
      if (ok && context.mounted) showToast(context, 'REV GAMES was added to your home screen.');
      return;
    }
    if (!context.mounted) return;
    final steps = PwaInstall.isIos
        ? 'Tap the Share button in Safari, then choose "Add to Home Screen".'
        : 'Open your browser menu, then choose "Install app" or "Add to Home screen".';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add to your home screen', style: AppText.body(18, weight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(steps, style: AppText.body(14, color: AppColors.textDim)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PwaInstall.canOffer) return const SizedBox.shrink();
    return PressScale(
      onTap: () => _tap(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          Icon(Icons.install_mobile_rounded, size: 28, color: AppColors.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Get the app on your home screen', style: AppText.body(15, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Opens full screen, like an app.', style: AppText.body(13, color: AppColors.textDim)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }
}
