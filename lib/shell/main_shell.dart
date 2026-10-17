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
import '../live/add_funds.dart';
import '../live/wallet_switcher.dart';
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
  }

  @override
  void dispose() {
    _catalog.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.select((ShellCubit c) => c.state.tab);
    final wide = context.isWide;

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
        maxWidth: double.infinity, // the shell lays itself out (see below)
        bottomBar: wide ? null : AppTabBar(items: _tabs, currentIndex: tab, onTap: (i) => context.read<ShellCubit>().go(i)),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // iPad landscape, Mac and browser: tabs live in a side rail.
            if (wide) _SideRail(items: _tabs, currentIndex: tab, onTap: (i) => context.read<ShellCubit>().go(i)),
            Expanded(
              child: ContentWidth(
                maxWidth: wide ? 1120 : 900,
                child: Column(
                  children: [
                    if (tab != ShellTab.settings) const _Header() else const SizedBox(height: 8),
                    const StandingBanner(),
                    Expanded(
                      child: IndexedStack(
                        index: tab,
                        children: const [BrowsePage(), LobbyPage(), SlotsLobbyPage(), ContentWidth(maxWidth: 720, child: SettingsPage())],
                      ),
                    ),
                  ],
                ),
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
      onBalanceTap: () => showWalletSwitcher(context),
      dropdown: true,
      onAdd: () => openAddFunds(context),
      action: const SupportButton(size: 42),
    );
  }
}

/// Vertical tab bar for wide screens.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.items, required this.currentIndex, required this.onTap});

  final List<AppTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      margin: const EdgeInsets.fromLTRB(12, 8, 0, 12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Text('REV', style: AppText.heading(20, letterSpacing: -0.6)),
          const SizedBox(height: 20),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Semantics(
                button: true,
                selected: i == currentIndex,
                label: items[i].label,
                child: PressScale(
                  onTap: () => onTap(i),
                  scale: .95,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: i == currentIndex ? AppColors.text.withValues(alpha: .08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        Icon(i == currentIndex ? (items[i].activeIcon ?? items[i].icon) : items[i].icon, size: 24, color: i == currentIndex ? AppColors.text : AppColors.textDim),
                        const SizedBox(height: 6),
                        Text(items[i].label, style: AppText.body(11, weight: FontWeight.w600, color: i == currentIndex ? AppColors.text : AppColors.textDim, height: 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
