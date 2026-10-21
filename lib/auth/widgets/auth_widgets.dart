import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../components/components.dart';
import '../../legal/legal_page.dart';

/// Red (error) or green (info) message above a form.
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, this.error, this.info});

  final String? error;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final text = error ?? info;
    if (text == null) return const SizedBox.shrink();
    final color = error != null ? AppColors.loss : AppColors.green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error != null ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.body(13, color: color, height: 1.35))),
        ],
      ),
    );
  }
}

/// "or continue with" divider.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(height: 1, color: AppColors.line));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: AppText.body(12, color: AppColors.textDim)),
          ),
          line,
        ],
      ),
    );
  }
}

/// "New here?  Create account" style text link.
class AuthLink extends StatelessWidget {
  const AuthLink({super.key, this.prefix, required this.action, required this.onTap, this.center = true});

  final String? prefix;
  final String action;
  final VoidCallback? onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final child = PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text.rich(
          TextSpan(
            children: [
              if (prefix != null) TextSpan(text: '$prefix ', style: AppText.body(14, color: AppColors.textMuted)),
              TextSpan(text: action, style: AppText.body(14, weight: FontWeight.w700, color: AppColors.gold)),
            ],
          ),
        ),
      ),
    );
    return center ? Center(child: child) : Align(alignment: Alignment.centerRight, child: child);
  }
}

/// Eye icon that shows or hides a password.
class PasswordToggle extends StatelessWidget {
  const PasswordToggle({super.key, required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppColors.textDim),
    );
  }
}


const _appleLogo =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#FFFFFF" d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>';

/// The Sign in with Apple button: black, the Apple logo and Apple's own wording, as Apple's design
/// guidelines ask. Shown on iPhone and iPad only.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.onPressed, this.loading = false, this.label = 'Sign in with Apple'});

  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressScale(
        onTap: loading ? null : onPressed,
        child: Container(
          height: 52,
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.line)),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(height: 22, child: FittedBox(child: AppLoader(color: Colors.white)))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  SvgPicture.string(_appleLogo, width: 20, height: 20),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1)),
                ]),
        ),
      ),
    );
  }
}

/// "By continuing you agree to our Terms of Service and Privacy Policy", both opening the real documents.
class AuthLegalNote extends StatelessWidget {
  const AuthLegalNote({super.key, this.action = 'continuing'});

  /// Completes "By ...": continuing, signing in, creating an account.
  final String action;

  @override
  Widget build(BuildContext context) {
    final plain = AppText.body(12, color: AppColors.textDim, height: 1.4);
    Widget link(String text, String slug) => PressScale(
          onTap: () => openLegal(context, slug),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(text, style: AppText.body(12, weight: FontWeight.w700, color: AppColors.gold, decoration: TextDecoration.underline)),
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By $action, you agree to our ', style: plain),
        link('Terms of Service', 'terms'),
        Text(' and ', style: plain),
        link('Privacy Policy', 'privacy'),
        Text('.', style: plain),
      ],
    );
  }
}
