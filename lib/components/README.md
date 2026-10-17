# REV GAMES components

Import everything with `import 'package:YOUR_APP/components/components.dart';`
or import single files.

Needs (pubspec): `google_fonts: ^6.2.1`, Flutter 3.22+.

| Folder | What is in it |
|---|---|
| core | AppColors (dark + light, switched by ThemeCubit), AppText (Space Grotesk), AppSpacing/AppRadius/AppShadows, formatters, PressScale, GlowBackground, AppScaffold |
| buttons | AppButton (6 variants), IconSquareButton, PillButton, DockToggleButton, BrassButton |
| inputs | SearchField, AppTextField, AmountField, SegmentedToggle, SwitchRow, PillChip/FilterChipRow, BetChipPicker |
| navigation | AppTabBar, AppHeader, GameTopBar, SubPageBar, SectionHeader |
| cards | GameTile, GameArt, FeaturedGameCard, LevelProgressCard, StatTile, DailyRewardCard, BalanceCard, InfoCard, WinBanner |
| lists | ListGroup, ListRowTile, ActivityRow, FaqTile |
| feedback | BalancePill, DemoBadge, MultiplierPill, HistoryStrip, AppProgressBar, SkeletonBox, AppBottomSheet, AppDialogCard, StatusView |
| game | GameScaffold, BetPanel, MultiplierDisplay, StatusPill, PlayingCardView/CardHand, RouletteNumberCell, RouletteWheel, CrashGraph, DiceTrack, CashOutButton, BigWinOverlay |

Every widget takes its content through named parameters, e.g.

```dart
AppButton(label: 'Play now', variant: AppButtonVariant.success, onPressed: play)
GameTile(title: 'Roulette', tag: 'Table', kind: GameKind.roulette, onTap: openRoulette)
BalancePill(balance: 94250, onAdd: openGetCredits)
```
