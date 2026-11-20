import 'package:flutter/material.dart';

/// Colours of the free Bid Check screens (the same navy / cream / orange as the website's first page).
class BidColors {
  static const navy = Color(0xFF141F3D);
  static const card = Color(0xFF1D2A52);
  static const cream = Color(0xFFF5F3EE);
  static const field = Color(0xFFFDFCF8);
  static const line = Color(0xFFD9D4C7);
  static const orange = Color(0xFFF4A65A);
  static const brown = Color(0xFFB04A1C);
  static const soft = Color(0xFFD5DBEE);
  static const muted = Color(0xFF4A5470);
}

/// The first screen for someone who is not signed in: "Check your bid before you submit".
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key, required this.onStart});

  /// "Sign in" and "Check my bid free" both open the mobile sign-in screen.
  final VoidCallback onStart;

  static const _steps = [
    'Upload the tender paper',
    'Upload your technical bid',
    'Get your score and fixes',
  ];

  @override
  Widget build(BuildContext context) {
    // On a short phone the whole page is drawn smaller (text and gaps), so it fits without scrolling.
    final media = MediaQuery.of(context);
    final room = media.size.height - media.padding.top - media.padding.bottom;
    final k = (room / 780.0).clamp(0.6, 1.0);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(media.textScaler.scale(1) * k),
      ),
      child: Scaffold(
      backgroundColor: BidColors.navy,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Tender Agent',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          key: const ValueKey('landing-signin'),
                          onPressed: onStart,
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              color: BidColors.soft,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 28 * k),
                    const Text(
                      'FREE BID CHECK',
                      style: TextStyle(
                        color: BidColors.orange,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 14 * k),
                    const Text(
                      'Check your bid before you submit.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 16 * k),
                    const Text(
                      'Upload the tender and your bid. Get a score out of 10 and see what could get you rejected, in 5 minutes.',
                      style: TextStyle(
                        color: BidColors.soft,
                        fontSize: 17,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 24 * k),
                    for (var i = 0; i < _steps.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: BidColors.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: BidColors.orange,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: BidColors.navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _steps[i],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    SizedBox(height: 20 * k),
                    SizedBox(
                      width: double.infinity,
                      height: 54 * k,
                      child: FilledButton(
                        key: const ValueKey('landing-cta'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BidColors.orange,
                          foregroundColor: BidColors.navy,
                        ),
                        onPressed: onStart,
                        child: const Text(
                          'Check my bid free',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12 * k),
                    const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 15,
                            color: BidColors.soft,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Private. Files auto-delete after the check.',
                            style: TextStyle(
                              color: BidColors.soft,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
