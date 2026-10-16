import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../catalog/catalog_cubit.dart';
import '../components/components.dart';
import '../games/game_support.dart';
import '../pages/browse_page.dart';
import '../pages/get_credits_sheet.dart';
import '../pages/lobby_page.dart';
import '../pages/settings_page.dart';
import '../pages/slots_lobby_page.dart';
import '../pages/account_restricted_page.dart';
import '../pages/system_pages.dart';
import '../pages/wallet_page.dart';
import '../session/session_guard.dart';
import '../support/support_button.dart';
import '../user/bloc/profile_cubit.dart';
import 'shell_cubit.dart';

/// The signed in app: header with the one balance, four tabs, floating navbar.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => ShellCubit(), child: const _ShellView());
  }
}

class _ShellView extends StatefulWidget {
  const _ShellView();

  @override
  State<_ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<_ShellView> {
  static const _tabs = [
    AppTabItem(label: 'Browse', icon: Icons.manage_search_rounded),
    AppTabItem(label: 'Casino', icon: Icons.casino_outlined, activeIcon: Icons.casino_rounded),
    AppTabItem(label: 'Slots', icon: Icons.grid_view_rounded),
    AppTabItem(label: 'Settings', icon: Icons.hexagon_outlined, activeIcon: Icons.hexagon_rounded),
  ];

  late final CatalogCubit _catalog = context.read<CatalogCubit>();

  @override
  void initState() {
    super.initState();
    _catalog.start();
    AppSound.startMusic();
  }

  @override
  void dispose() {
    _catalog.stop();
    AppSound.stopMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.select((ShellCubit c) => c.state.tab);

    return BlocListener<SessionGuard, SessionState>(
      listenWhen: (a, b) => a.alertSerial != b.alertSerial && b.alert != SessionAlert.none,
      listener: (context, s) {
        if (s.alert == SessionAlert.realityCheck) {
          showRealityCheck(context);
        } else if (s.alert == SessionAlert.lossLimit) {
          showLossLimitReached(context);
        }
      },
      child: AppScaffold(
        glowColor: AppColors.purple,
        bottomBar: AppTabBar(items: _tabs, currentIndex: tab, onTap: (i) => context.read<ShellCubit>().go(i)),
        body: Column(
          children: [
            if (tab != ShellTab.settings) const _Header() else const SizedBox(height: 8),
            const StandingBanner(),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: const [BrowsePage(), LobbyPage(), SlotsLobbyPage(), SettingsPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final ready = context.select((ProfileCubit c) => c.state.walletReady);
    final balance = watchBalance(context);
    if (!ready) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('REV GAMES', style: AppText.heading(30, letterSpacing: -1.5)),
            const SkeletonBox(width: 150, height: 46, radius: 46),
          ],
        ),
      );
    }
    return AppHeader(
      balance: balance,
      onBalanceTap: () => pushPage<void>(context, const WalletPage()),
      onAdd: () => showGetCredits(context),
      action: const SupportButton(size: 42),
    );
  }
}
