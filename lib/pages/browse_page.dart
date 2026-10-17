import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../catalog/catalog_cubit.dart';
import '../components/components.dart';
import '../games/game_launcher.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../shell/shell_cubit.dart';
import '../legal/legal_page.dart';
import 'help_page.dart';
import 'history_page.dart';
import 'limits_page.dart';
import 'wallet_page.dart';
import '../support/support_button.dart';

/// L2. Browse menu: jump to a section, search games, open wallet and help.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.read<ShellCubit>();
    final games = context.watch<CatalogCubit>().state.games;
    final q = _q.trim().toLowerCase();
    final results = [for (final g in games) if (g.name.toLowerCase().contains(q) || g.tag.toLowerCase().contains(q)) g];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 120),
      children: [
        SearchField(hint: 'Search games', controller: _search, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 16),
        if (q.isNotEmpty) ...[
          if (results.isEmpty)
            const InfoCard(title: 'No games found', message: 'Try another word.')
          else
            ListGroup(
              title: 'Results',
              children: [
                for (final g in results)
                  ListRowTile(
                    icon: g.comingSoon ? Icons.lock_outline_rounded : Icons.play_circle_outline_rounded,
                    title: g.name,
                    subtitle: g.comingSoon ? 'Coming soon' : g.tag,
                    onTap: () => openGame(context, g, viaDetails: g.type == GameType.slots && !g.comingSoon),
                  ),
              ],
            ),
          const SizedBox(height: 20),
        ] else ...[
          ListGroup(
            children: [
              ListRowTile(icon: Icons.casino_outlined, title: 'Casino Games', onTap: () => shell.go(ShellTab.casino, filter: GameGroup.table)),
              ListRowTile(icon: Icons.apps_rounded, title: 'Slots', onTap: () => shell.go(ShellTab.slots)),
              ListRowTile(icon: Icons.bolt_rounded, title: 'Instant Games', onTap: () => shell.go(ShellTab.casino, filter: GameGroup.instant)),
              ListRowTile(icon: Icons.star_border_rounded, title: 'Favourites', onTap: () => shell.go(ShellTab.casino, favouritesOnly: true)),
            ],
          ),
          const SizedBox(height: 16),
          ListGroup(
            children: [
              ListRowTile(icon: Icons.account_balance_wallet_outlined, title: 'Wallet and credits', onTap: () => pushPage<void>(context, const WalletPage())),
              ListRowTile(icon: Icons.history_rounded, title: 'Game history', onTap: () => pushPage<void>(context, const HistoryPage())),
              ListRowTile(icon: Icons.help_outline_rounded, title: 'Help Centre', trailing: const SupportBadge(), onTap: () => pushPage<void>(context, const HelpPage())),
              ListRowTile(icon: Icons.shield_outlined, title: 'Responsible Play', onTap: () => pushPage<void>(context, const LimitsPage())),
              ListRowTile(icon: Icons.gavel_rounded, title: 'Legal and policies', onTap: () => pushPage<void>(context, const LegalPage())),
              ListRowTile(icon: Icons.settings_outlined, title: 'Settings', trailingText: 'English', onTap: () => shell.go(ShellTab.settings)),
            ],
          ),
        ],
      ],
    );
  }
}
