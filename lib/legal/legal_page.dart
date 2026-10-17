import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_cache.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model_json.dart';
import '../pages/system_pages.dart';

/// The documents, in the order they are listed. The text itself comes from the server so it can be
/// corrected without a new app release, and the last copy read is kept for offline use.
const _docs = <_DocInfo>[
  _DocInfo('terms', 'Terms of Service', 'The rules for using REV GAMES.', Icons.description_outlined),
  _DocInfo('privacy', 'Privacy Policy', 'What we collect, why, and your choices.', Icons.lock_outline_rounded),
  _DocInfo('refunds', 'Refund Policy', 'When money is returned, and when it is not.', Icons.receipt_long_outlined),
  _DocInfo('cookies', 'Cookie Policy', 'What our website stores. The app uses no cookies.', Icons.cookie_outlined),
  _DocInfo('about', 'Who we are', 'The company behind REV GAMES and how to reach us.', Icons.business_outlined),
];

class _DocInfo {
  const _DocInfo(this.slug, this.title, this.summary, this.icon);
  final String slug;
  final String title;
  final String summary;
  final IconData icon;
}

/// Legal and policies: the list of documents.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Legal and policies', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const SizedBox(height: 8),
          ListGroup(
            children: [
              for (final d in _docs)
                ListRowTile(icon: d.icon, title: d.title, subtitle: d.summary, onTap: () => pushPage<void>(context, LegalDocPage(slug: d.slug, title: d.title))),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'To delete your account and the information we hold, open your profile. To ask for a copy of your information, contact Support.',
            style: AppText.body(12, color: AppColors.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Opens one document straight from the list or from a link (Terms, Privacy).
void openLegal(BuildContext context, String slug) {
  final info = _docs.firstWhere((d) => d.slug == slug, orElse: () => _docs.first);
  pushPage<void>(context, LegalDocPage(slug: info.slug, title: info.title));
}

class LegalDocPage extends StatefulWidget {
  const LegalDocPage({super.key, required this.slug, required this.title});

  final String slug;
  final String title;

  @override
  State<LegalDocPage> createState() => _LegalDocPageState();
}

class _LegalDocPageState extends State<LegalDocPage> {
  Map<String, dynamic>? _doc;
  Object? _error;

  String get _key => 'legal.${widget.slug}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final cached = await ApiCache.read(_key); // show the last copy at once
    if (!mounted) return;
    if (cached != null) setState(() => _doc = cached);
    try {
      final fresh = await context.read<ApiClient>().getPublic('/v1/legal/${widget.slug}');
      if (!mounted) return;
      setState(() => _doc = fresh);
      ApiCache.write(_key, fresh);
    } catch (e) {
      if (mounted && _doc == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    final sections = d == null ? const [] : (d['sections'] as List? ?? const []);
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 40),
        children: [
          SubPageBar(title: widget.title, onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          if (d != null) ...[
            Text('Last updated ${parseString(d['updated']) ?? ''}', style: AppText.body(12, color: AppColors.textDim)),
            const SizedBox(height: 8),
            for (final s in sections) ...[
              const SizedBox(height: 18),
              Text(parseString(s['title']) ?? '', style: AppText.body(16, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(parseString(s['body']) ?? '', style: AppText.body(14, color: AppColors.textMuted, height: 1.6)),
            ],
          ] else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: (_error is ApiException && (_error as ApiException).isNetwork)
                  ? OfflineView(onRetry: _load, error: _error as ApiException)
                  : InfoCard(title: 'Could not open this page', message: failText(_error!), icon: Icons.error_outline_rounded, color: AppColors.loss),
            )
          else ...const [
            SizedBox(height: 12),
            SkeletonBox(height: 18, width: 160),
            SizedBox(height: 14),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14, width: 240),
            SizedBox(height: 28),
            SkeletonBox(height: 18, width: 120),
            SizedBox(height: 14),
            SkeletonBox(height: 14),
            SizedBox(height: 8),
            SkeletonBox(height: 14, width: 200),
          ],
        ],
      ),
    );
  }
}
