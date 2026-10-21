import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/require_sign_in.dart';
import '../catalog/catalog_cubit.dart';
import '../events/events_page.dart';
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
import 'app_tour.dart';
import 'shell_cubit.dart';

/// The signed in app: header with the one balance, four tabs, floating navbar.
class MainShell extends StatelessWidget {
  const MainShell({super.key, this.guest = false});

  /// A visitor who has not signed in: can browse everything, can't play.
  final bool guest;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => ShellCubit(), child: _ShellView(guest: guest));
  }
}

class _ShellView extends StatefulWidget {
  const _ShellView({required this.guest});

  final bool guest;

  @override
  State<_ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<_ShellView> {
  static const _tabs = [
    AppTabItem(label: 'Browse', icon: Icons.manage_search_rounded),
    AppTabItem(label: 'Casino', icon: Icons.casino_outlined, activeIcon: Icons.casino_rounded),
    AppTabItem(label: 'Slots', icon: Icons.grid_view_rounded),
    AppTabItem(label: 'Events', icon: Icons.emoji_events_outlined, activeIcon: Icons.emoji_events_rounded),
    AppTabItem(label: 'Settings', icon: Icons.hexagon_outlined, activeIcon: Icons.hexagon_rounded),
  ];

  late final CatalogCubit _catalog = context.read<CatalogCubit>();

  @override
  void initState() {
    super.initState();
    _catalog.start();
    if (!widget.guest) _tourWhenReady();
  }

  /// First run: once the header has its real balance, light up the controls one by one.
  Future<void> _tourWhenReady() async {
    for (var tries = 0; tries < 8; tries++) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      final profile = context.read<ProfileCubit>();
      final onTop = ModalRoute.of(context)?.isCurrent ?? true;
      final onHome = context.read<ShellCubit>().state.tab != ShellTab.settings;
      if (profile.state.walletReady && onTop && onHome && !profile.state.blocksPlay) {
        await AppTour.maybeShow(context, uid: profile.state.user.id);
        return;
      }
    }
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
        bottomBar: wide ? null : CoachTarget(id: 'tabs', child: AppTabBar(items: _tabs, currentIndex: tab, onTap: (i) => context.read<ShellCubit>().go(i))),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // iPad landscape, Mac and browser: tabs live in a side rail.
            if (wide) CoachTarget(id: 'tabs', child: _SideRail(items: _tabs, currentIndex: tab, onTap: (i) => context.read<ShellCubit>().go(i))),
            Expanded(
              child: ContentWidth(
                maxWidth: wide ? 1120 : 900,
                child: Column(
                  children: [
                    if (widget.guest)
                      const _GuestHeader()
                    else if (tab != ShellTab.settings)
                      const _Header()
                    else
                      const SizedBox(height: 8),
                    if (!widget.guest) const StandingBanner(),
                    Expanded(
                      child: IndexedStack(
                        index: tab,
                        children: [const BrowsePage(), const LobbyPage(), const SlotsLobbyPage(), const EventsPage(), widget.guest ? const _GuestSettings() : const ContentWidth(maxWidth: 720, child: SettingsPage())],
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

/// What a visitor sees instead of the balance: a way in.
class _GuestHeader extends StatelessWidget {
  const _GuestHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('REV GAMES', maxLines: 1, style: AppText.heading(30, letterSpacing: -1.5)))),
          const SizedBox(width: 10),
          AppButton(label: 'Log in', variant: AppButtonVariant.ghost, expanded: false, height: 42, fontSize: 13, radius: AppRadius.md, onPressed: () => openSignIn(context)),
          const SizedBox(width: 8),
          AppButton(label: 'Sign up', expanded: false, height: 42, fontSize: 13, radius: AppRadius.md, onPressed: () => openSignIn(context)),
        ],
      ),
    );
  }
}

/// The Settings tab for a visitor: everything in it needs an account.
class _GuestSettings extends StatelessWidget {
  const _GuestSettings();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 24, AppSpacing.screen, 120),
      children: [
        Icon(Icons.lock_open_rounded, size: 44, color: AppColors.gold),
        const SizedBox(height: 14),
        Text('Join to play', textAlign: TextAlign.center, style: AppText.heading(26, letterSpacing: -.8)),
        const SizedBox(height: 8),
        Text('You can look around freely. Create a free account to play, join events and track your bets.', textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
        const SizedBox(height: 22),
        AppButton(label: 'Sign up', onPressed: () => openSignIn(context)),
        const SizedBox(height: 10),
        AppButton(label: 'Log in', variant: AppButtonVariant.outline, onPressed: () => openSignIn(context)),
      ],
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
