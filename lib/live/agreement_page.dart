import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import 'live_api.dart';
import 'live_models.dart';

/// The Live Money Agreement. Opens before a player's first real-money session (and again whenever
/// the text is updated). Returns `true` once it was accepted. The text comes from the server.
Future<bool> showLiveAgreement(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LiveAgreementPage()));
  return ok == true;
}

class LiveAgreementPage extends StatefulWidget {
  const LiveAgreementPage({super.key});

  @override
  State<LiveAgreementPage> createState() => _LiveAgreementPageState();
}

class _LiveAgreementPageState extends State<LiveAgreementPage> {
  late final LiveApi _api = context.read<LiveApi>();
  LiveAgreement? _doc;
  String? _loadError;
  final _ticked = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await _api.agreement();
      if (!mounted) return;
      if (d.accepted) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _doc = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Something went wrong. Please try again.');
    }
  }

  Future<void> _accept() async {
    final d = _doc;
    if (d == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.acceptAgreement(d.version, _ticked.toList());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.code == 'agreement_changed') _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    final all = d != null && d.confirmations.every((c) => _ticked.contains(c.id));
    return AppScaffold(
      glowColor: AppColors.green,
      body: Column(
        children: [
          SubPageBar(title: d?.title ?? 'Live Money Agreement', onBack: () => Navigator.of(context).pop(false), padding: const EdgeInsets.fromLTRB(16, 8, 16, 8)),
          Expanded(
            child: d == null
                ? (_loadError == null
                    ? const Padding(padding: EdgeInsets.all(AppSpacing.screen), child: SkeletonList(rows: 5, rowHeight: 72))
                    : Center(child: StatusView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: _loadError!, actionLabel: 'Try again', onAction: _load)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 24),
                    children: [
                      Text(d.intro, style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
                      const SizedBox(height: 14),
                      for (var i = 0; i < d.sections.length; i++) ...[
                        Text('${i + 1}. ${d.sections[i].title}', style: AppText.body(15, weight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(d.sections[i].body, style: AppText.body(13.5, color: AppColors.textSoft, height: 1.55)),
                        const SizedBox(height: 16),
                      ],
                      Text('Version ${d.version}', style: AppText.body(11, color: AppColors.textDim)),
                    ],
                  ),
          ),
          if (d != null)
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(color: AppColors.sheet, border: Border(top: BorderSide(color: AppColors.line))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in d.confirmations)
                    PressScale(
                      onTap: _busy ? null : () => setState(() => _ticked.contains(c.id) ? _ticked.remove(c.id) : _ticked.add(c.id)),
                      scale: .99,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_ticked.contains(c.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 24, color: _ticked.contains(c.id) ? AppColors.green : AppColors.textDim),
                            const SizedBox(width: 10),
                            Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(c.text, style: AppText.body(13.5, color: AppColors.textSoft, height: 1.35)))),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null) ...[const SizedBox(height: 6), Text(_error!, style: AppText.body(13, color: AppColors.loss))],
                  const SizedBox(height: 10),
                  AppButton(label: 'Accept and continue', variant: AppButtonVariant.gold, loading: _busy, onPressed: all && !_busy ? _accept : null),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: Text('Not now, stay on demo', style: AppText.body(13, color: AppColors.textMuted))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
