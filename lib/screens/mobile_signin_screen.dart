import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'landing_screen.dart';

/// Sign in with a mobile number and an OTP (the server sends and checks the code; the first time a number signs in its
/// account is made with the company name typed here). "Sign up with company details" opens the email log-in.
class MobileSignInScreen extends StatefulWidget {
  const MobileSignInScreen({
    super.key,
    required this.signIn,
    required this.onBack,
    required this.onCompanyDetails,
    this.api,
  });

  /// Signs in with the custom token the server returns after a correct OTP (AuthService.signInWithToken).
  final Future<void> Function(String token) signIn;
  final VoidCallback onBack, onCompanyDetails;

  /// The server client; tests pass their own.
  final ApiClient? api;

  @override
  State<MobileSignInScreen> createState() => _MobileSignInScreenState();
}

class _MobileSignInScreenState extends State<MobileSignInScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _company = TextEditingController();
  String? _sentTo; // the number an OTP was sent to, as the server shows it
  bool _returning = false; // that number already has an account: no company name needed
  String? _busy; // what is happening now ("Sending the OTP...")
  String? _error;

  /// The page is drawn this much smaller than its normal size on a short phone, so all of it fits the screen
  /// without scrolling (see build). 1.0 on a tall phone.
  double _k = 1.0;
  static const _designHeight = 780.0; // the height the page needs at its normal size
  double _s(double v) => v * _k;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = 'Sending the OTP...';
      _error = null;
    });
    try {
      final sent = await _api.requestOtp(_phone.text.trim());
      if (mounted) {
        setState(() {
          _sentTo = sent.phone;
          _returning = sent.returning;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _continue() async {
    if (_sentTo == null) {
      setState(() => _error = 'Tap Send OTP first, then enter the code you get.');
      return;
    }
    if (!_returning && _company.text.trim().isEmpty) {
      setState(() => _error = 'Enter your company name.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = 'Enter the 6-digit OTP.');
      return;
    }
    setState(() {
      _busy = 'Checking your OTP...';
      _error = null;
    });
    try {
      final token = await _api.verifyOtp(
        _phone.text.trim(),
        _otp.text.trim(),
        _company.text.trim(),
      );
      if (mounted) setState(() => _busy = 'Signed in. Opening your bid check...');
      await widget.signIn(token);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _busy = null;
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _busy = null;
    } finally {
      if (mounted && _error != null) setState(() => _busy = null);
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: BidColors.field,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: _s(14)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: BidColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: BidColors.line),
    ),
  );

  Widget _label(String text) => Padding(
    padding: EdgeInsets.only(top: _s(14), bottom: _s(6)),
    child: Text(
      text,
      style: TextStyle(
        color: BidColors.navy,
        fontWeight: FontWeight.w600,
        fontSize: _s(14),
      ),
    ),
  );

  TextStyle get _fieldStyle => TextStyle(fontSize: _s(16));

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;
    // The room the page has on this phone (the keyboard is not taken off, so the page does not jump when it opens).
    final media = MediaQuery.of(context);
    final room = media.size.height - media.padding.top - media.padding.bottom;
    _k = (room / _designHeight).clamp(0.6, 1.0);
    return Scaffold(
      backgroundColor: BidColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, _s(8), 20, _s(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('signin-back'),
                      onPressed: busy ? null : widget.onBack,
                      icon: Icon(Icons.arrow_back, color: BidColors.orange, size: _s(18)),
                      label: Text(
                        'Back',
                        style: TextStyle(color: BidColors.orange, fontSize: _s(16)),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('signin-company'),
                      onPressed: busy ? null : widget.onCompanyDetails,
                      child: Text(
                        'Sign up with company details',
                        style: TextStyle(color: BidColors.orange, fontSize: _s(14)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: _s(8)),
                Container(
                  padding: EdgeInsets.fromLTRB(20, _s(22), 20, _s(22)),
                  decoration: BoxDecoration(
                    color: BidColors.cream,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Sign in with your mobile',
                        style: TextStyle(
                          color: BidColors.navy,
                          fontSize: _s(26),
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: _s(8)),
                      Text(
                        'No password, and no payment details needed for the free check.',
                        style: TextStyle(color: BidColors.muted, fontSize: _s(15)),
                      ),
                      _label('Mobile number'),
                      TextField(
                        key: const ValueKey('mobile'),
                        controller: _phone,
                        enabled: !busy,
                        keyboardType: TextInputType.phone,
                        style: _fieldStyle,
                        decoration: _decoration('+91 98765 43210'),
                      ),
                      SizedBox(height: _s(8)),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _sentTo == null ? '' : 'OTP sent to $_sentTo',
                              style: TextStyle(
                                color: BidColors.muted,
                                fontSize: _s(13),
                              ),
                            ),
                          ),
                          OutlinedButton(
                            key: const ValueKey('send-otp'),
                            onPressed: busy ? null : _send,
                            style: OutlinedButton.styleFrom(
                              visualDensity: _k < 0.85 ? VisualDensity.compact : null,
                              foregroundColor: BidColors.navy,
                              side: const BorderSide(color: BidColors.navy, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              _sentTo == null ? 'Send OTP' : 'Resend OTP',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: _s(14)),
                            ),
                          ),
                        ],
                      ),
                      _label('OTP'),
                      TextField(
                        key: const ValueKey('otp'),
                        controller: _otp,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: _fieldStyle,
                        decoration: _decoration('6-digit code').copyWith(counterText: ''),
                      ),
                      if (_sentTo != null && _returning)
                        Padding(
                          padding: EdgeInsets.only(top: _s(14)),
                          child: Text(
                            'Welcome back. This number already has an account - just enter the OTP.',
                            key: const ValueKey('welcome-back'),
                            style: TextStyle(color: BidColors.muted, fontSize: _s(14)),
                          ),
                        )
                      else ...[
                        _label('Company name'),
                        TextField(
                          key: const ValueKey('company'),
                          controller: _company,
                          enabled: !busy,
                          textCapitalization: TextCapitalization.words,
                          style: _fieldStyle,
                          decoration: _decoration('As on your GST certificate'),
                        ),
                      ],
                      SizedBox(height: _s(14)),
                      Container(
                        padding: EdgeInsets.all(_s(12)),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECE8DE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text.rich(
                          const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Free plan: ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: '3 bid checks every month. Upgrade any time for your team.',
                              ),
                            ],
                          ),
                          style: TextStyle(color: const Color(0xFF3D4560), fontSize: _s(14)),
                        ),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: _s(12)),
                        Text(
                          _error!,
                          key: const ValueKey('signin-error'),
                          style: const TextStyle(
                            color: Color(0xFFB3261E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      SizedBox(height: _s(16)),
                      FilledButton(
                        key: const ValueKey('signin-continue'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BidColors.navy,
                          foregroundColor: Colors.white,
                          minimumSize: Size.fromHeight(_s(52)),
                        ),
                        onPressed: busy ? null : _continue,
                        child: busy
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(child: Text(_busy!)),
                                ],
                              )
                            : Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: _s(17),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
