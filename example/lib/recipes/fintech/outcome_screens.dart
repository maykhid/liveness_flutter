import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import 'brand.dart';
import 'face_capture_screen.dart';
import 'account.dart';

/// Shown while a passing result goes to the backend. A pass on the phone
/// is only a claim: the upgrade happens when the server agrees.
class VerifyingScreen extends StatefulWidget {
  const VerifyingScreen({super.key, required this.result});

  final LivenessResult result;

  @override
  State<VerifyingScreen> createState() => _VerifyingScreenState();
}

class _VerifyingScreenState extends State<VerifyingScreen> {
  @override
  void initState() {
    super.initState();
    _submit();
  }

  /// In your app: upload the result with HttpLivenessUploader (or your own
  /// client) and return your backend's decision, made after it has checked
  /// the nonce, photos and face match (doc/server_verification.md). This
  /// sample pretends the server approves every passing check.
  Future<bool> _serverApproves(LivenessResult result) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return true;
  }

  Future<void> _submit() async {
    final approved = await _serverApproves(widget.result);
    if (!mounted) return;
    if (approved) accountTier.value = 2;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => approved
            ? const SuccessScreen()
            : const FailureScreen(reason: null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 48,
              child: CircularProgressIndicator(color: Brand.primary),
            ),
            SizedBox(height: 20),
            Text(
              'Verifying your face…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'This usually takes a few seconds',
              style: TextStyle(color: Brand.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _OutcomeLayout(
      icon: Icons.verified,
      color: Brand.success,
      title: 'You’re verified',
      body: const Column(
        children: [
          Text(
            'Your account is now Tier 2.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted),
          ),
          SizedBox(height: 16),
          _Perk(text: 'Send up to ₦1,000,000 a day'),
          _Perk(text: 'Receive larger payments'),
          _Perk(text: 'Higher wallet balance limit'),
        ],
      ),
      primary: FilledButton(
        onPressed: () =>
            Navigator.popUntil(context, (route) => route.isFirst),
        child: const Text('Back to home'),
      ),
    );
  }
}

class FailureScreen extends StatelessWidget {
  const FailureScreen({super.key, required this.reason});

  final LivenessFailureReason? reason;

  @override
  Widget build(BuildContext context) {
    final help = Brand.failureHelp(reason);
    return _OutcomeLayout(
      icon: Icons.error_outline,
      color: Brand.danger,
      title: help.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in help.tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: Brand.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tip, style: const TextStyle(color: Brand.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
      primary: FilledButton(
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FaceCaptureScreen()),
        ),
        child: const Text('Try again'),
      ),
      secondary: TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Not now'),
      ),
    );
  }
}

class _OutcomeLayout extends StatelessWidget {
  const _OutcomeLayout({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.primary,
    this.secondary,
  });

  final IconData icon;
  final Color color;
  final String title;
  final Widget body;
  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 44,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, size: 48, color: color),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 12),
              body,
              const Spacer(flex: 2),
              primary,
              if (secondary != null) ...[
                const SizedBox(height: 8),
                secondary!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 18, color: Brand.success),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Brand.ink)),
        ],
      ),
    );
  }
}
