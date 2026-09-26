import 'package:flutter/material.dart';

import 'brand.dart';
import 'face_capture_screen.dart';

/// Sets expectations before the camera opens: where the user is in the
/// upgrade, what to do for a first-time pass, and what the photos are for.
class KycIntroScreen extends StatelessWidget {
  const KycIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade to Tier 2')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: const [
          _Steps(),
          SizedBox(height: 24),
          Text(
            'Quick face check',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Brand.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'We’ll ask you to do a few simple moves, like blinking or '
            'turning your head, to confirm it’s really you.',
            style: TextStyle(color: Brand.muted, height: 1.4),
          ),
          SizedBox(height: 20),
          _Card(
            children: [
              _Tip(
                icon: Icons.wb_sunny_outlined,
                text: 'Find good light, with nothing bright behind you',
              ),
              _Tip(
                icon: Icons.face_outlined,
                text: 'Remove glasses, caps and face coverings',
              ),
              _Tip(
                icon: Icons.smartphone,
                text: 'Hold your phone at eye level',
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your photos are used only to verify your identity, as '
                'required for account upgrades.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FaceCaptureScreen(),
                  ),
                ),
                child: const Text('Start face check'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Phone number', true),
      ('BVN', true),
      ('Face check', false),
    ];
    return _Card(
      children: [
        for (final (i, (label, done)) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: done ? Brand.success : Brand.primary,
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: done ? Brand.muted : Brand.ink,
                    fontWeight: done ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  done ? 'Done' : 'Now',
                  style: TextStyle(
                    color: done ? Brand.success : Brand.primary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Brand.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Brand.ink)),
          ),
        ],
      ),
    );
  }
}
