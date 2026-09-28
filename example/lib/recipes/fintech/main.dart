// Recipe: a fully branded KYC flow, as a Nigerian fintech might ship it.
//
// Run: flutter run -t lib/recipes/fintech/main.dart
//
// "AcmePay" is a fictional brand; everything brand-specific is in
// brand.dart. The files, in the order a user meets them:
//   main.dart                 account home that asks for a Tier 2 upgrade
//   account.dart              the user's tier (a stand-in for your backend)
//   kyc_intro_screen.dart     why we need a face check, tips, consent
//   face_capture_screen.dart  the liveness check, fully restyled
//   outcome_screens.dart      verifying → success, or failure with help

import 'package:flutter/material.dart';

import 'account.dart';
import 'brand.dart';
import 'kyc_intro_screen.dart';

void main() => runApp(const AcmePayApp());

class AcmePayApp extends StatelessWidget {
  const AcmePayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Brand.name,
      theme: Brand.theme(),
      debugShowCheckedModeBanner: false,
      home: const AccountHome(),
    );
  }
}

class AccountHome extends StatelessWidget {
  const AccountHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: accountTier,
          builder: (context, tier, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Hi, Ada 👋',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 16),
              _BalanceCard(tier: tier),
              const SizedBox(height: 16),
              if (tier < 2)
                _UpgradeBanner(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const KycIntroScreen()),
                  ),
                )
              else
                const _VerifiedBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.tier});

  final int tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Brand.primary, Brand.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Wallet balance',
                  style: TextStyle(color: Colors.white70)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Tier $tier',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '₦ 24,500.00',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Daily transfer limit: ${tier < 2 ? '₦50,000' : '₦1,000,000'}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE8EDFF),
                child: Icon(Icons.trending_up, color: Brand.primary),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upgrade to Tier 2',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Brand.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Send up to ₦1,000,000 a day. Takes about a minute.',
                      style: TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Brand.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedBanner extends StatelessWidget {
  const _VerifiedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified, color: Brand.success),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your identity is verified. Enjoy higher limits.',
              style: TextStyle(color: Brand.ink),
            ),
          ),
        ],
      ),
    );
  }
}
