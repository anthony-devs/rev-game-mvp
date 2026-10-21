import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/components.dart';
import 'api/api_client.dart';

/// What this build of the app is. KEEP IN STEP with `version:` in pubspec.yaml, e.g. 1.0.0+1.
/// The server compares this with the minimum you set in the Developer Console.
class AppVersion {
  AppVersion._();

  static const String current = '1.0.0+1';

  static String get platform {
    if (kIsWeb) return '';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return '';
  }

  /// Sent with every request so the server can tell which build is calling.
  static Map<String, String> get headers => {
        'X-App-Version': current,
        if (platform.isNotEmpty) 'X-Platform': platform,
      };

  /// Set when the server refuses this build. The app then shows the update screen over everything.
  static final ValueNotifier<UpdateInfo?> required = ValueNotifier(null);

  static void markRequired(Map<String, dynamic> body) {
    required.value = UpdateInfo(
      message: (body['message'] as String?)?.trim().isNotEmpty == true ? body['message'] as String : UpdateInfo.defaultMessage,
      url: (body['url'] as String?) ?? '',
    );
  }
}

class UpdateInfo {
  const UpdateInfo({required this.message, required this.url, this.latest = ''});

  static const String defaultMessage = 'A newer version of REV GAMES is available. Please update to keep playing.';

  final String message;
  final String url;
  final String latest;
}

/// Wraps the whole app. Shows the update screen when this version is paused, and a one-time reminder
/// when a newer version exists but the old one still works.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.api, required this.navigatorKey, required this.child});

  final ApiClient api;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _reminded = false;
  DateTime _checked = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_checked) > const Duration(minutes: 2)) _check();
  }

  Future<void> _check() async {
    _checked = DateTime.now();
    final platform = AppVersion.platform;
    if (platform.isEmpty) return;
    try {
      final j = await widget.api.getPublic('/v1/app-version?platform=$platform&version=${Uri.encodeQueryComponent(AppVersion.current)}');
      final status = j['status'];
      if (status == 'required') {
        AppVersion.markRequired(j);
      } else {
        AppVersion.required.value = null;
        if (status == 'optional' && !_reminded) {
          _reminded = true;
          _remind(UpdateInfo(message: 'A new version of REV GAMES is available with the latest improvements.', url: (j['url'] as String?) ?? ''));
        }
      }
    } catch (_) {
      // Offline or the server is busy: never block the player because of a failed check.
    }
  }

  void _remind(UpdateInfo info) {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || info.url.isEmpty) return;
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Update available', style: AppText.heading(20)),
        content: Text(info.message, style: AppText.body(14, color: AppColors.textMuted, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: Text('Later', style: AppText.body(14, color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              Navigator.of(c).pop();
              openStore(info.url);
            },
            child: Text('Update', style: AppText.body(14, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: AppVersion.required,
      builder: (context, info, child) => Stack(
        fit: StackFit.expand,
        children: [child!, if (info != null) Positioned.fill(child: UpdateRequiredScreen(info: info, onRetry: _check))],
      ),
      child: widget.child,
    );
  }
}

Future<void> openStore(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) await Clipboard.setData(ClipboardData(text: url));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
  }
}

/// Full-screen block shown when this version has been paused.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.info, required this.onRetry});

  final UpdateInfo info;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_rounded, size: 56, color: AppColors.text),
                const SizedBox(height: 22),
                Text('Update required', textAlign: TextAlign.center, style: AppText.heading(26, letterSpacing: -.6)),
                const SizedBox(height: 10),
                Text(info.message, textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.textMuted, height: 1.45)),
                const SizedBox(height: 28),
                if (info.url.isNotEmpty)
                  AppButton(label: 'Update now', icon: Icons.download_rounded, height: 54, fontSize: 16, onPressed: () => openStore(info.url)),
                const SizedBox(height: 10),
                AppButton(label: 'I have updated', variant: AppButtonVariant.ghost, height: 48, fontSize: 14, onPressed: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
