import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/bid_check_screen.dart';
import 'screens/home_shell.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mobile_signin_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/signup_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Show the reason instead of a blank page.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Could not start Tender Mitra.\n\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(const TenderMitraApp());
}

class TenderMitraApp extends StatelessWidget {
  const TenderMitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tender Mitra',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

enum _Entry { landing, mobile, company }

/// Logged out -> login. Logged in -> check the account status the web app stores, then the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  Future<AccountStatus>? _status;
  String? _statusUid;

  bool _signingUp = false;

  /// Which screen a signed-out visitor sees: the first page, the mobile sign-in, or the email log-in.
  _Entry _entry = _Entry.landing;

  Future<AccountStatus> _loadStatus(String uid) async =>
      _auth.statusOf(await _auth.company(uid));

  @override
  void initState() {
    super.initState();
    authRefresh.addListener(_reload);
  }

  @override
  void dispose() {
    authRefresh.removeListener(_reload);
    super.dispose();
  }

  /// The sign-up wizard saved a company record: forget the cached status so it is read again.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _status = null;
      _statusUid = null;
    });
  }

  void _endSignUp() => setState(() {
    _signingUp = false;
    _status = null;
    _statusUid = null;
  });

  @override
  Widget build(BuildContext context) {
    // The wizard creates the account half-way through; it must stay on screen until it finishes.
    if (_signingUp) {
      return SignupScreen(
        key: const ValueKey('signup'),
        auth: _auth,
        onFinished: _endSignUp,
        onBackToLogin: () => setState(() => _signingUp = false),
      );
    }
    return StreamBuilder<User?>(
      stream: _auth.userChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          _status = null;
          _statusUid = null;
          return switch (_entry) {
            _Entry.landing => LandingScreen(
              onStart: () => setState(() => _entry = _Entry.mobile),
            ),
            _Entry.mobile => MobileSignInScreen(
              signIn: _auth.signInWithToken,
              onBack: () => setState(() => _entry = _Entry.landing),
              onCompanyDetails: () => setState(() => _entry = _Entry.company),
            ),
            _Entry.company => LoginScreen(
              auth: _auth,
              onSignUp: () => setState(() => _signingUp = true),
              onBack: () => setState(() => _entry = _Entry.mobile),
            ),
          };
        }
        _entry = _Entry.landing; // after a sign-out the first page comes back
        if (_statusUid != user.uid) {
          _statusUid = user.uid;
          _status = _loadStatus(user.uid);
        }
        return FutureBuilder<AccountStatus>(
          future: _status,
          builder: (context, status) {
            if (status.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (status.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load your account.\n${status.error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              setState(() => _status = _loadStatus(user.uid)),
                          child: const Text('Try again'),
                        ),
                        TextButton(
                          onPressed: _auth.signOut,
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (status.data == AccountStatus.needsProfile) {
              return SignupScreen(
                key: const ValueKey('signup-existing'),
                auth: _auth,
                existing: user,
                onFinished: _endSignUp,
                onBackToLogin: _auth.signOut,
              );
            }
            if (status.data == AccountStatus.pending) {
              return PendingScreen(
                auth: _auth,
                onRefresh: () async {
                  final fresh = await _loadStatus(user.uid);
                  if (fresh != AccountStatus.pending && mounted) {
                    setState(() => _status = Future.value(fresh));
                  }
                  return fresh != AccountStatus.pending;
                },
              );
            }
            if (status.data == AccountStatus.bidCheck) {
              return BidCheckScreen(onSignOut: _auth.signOut);
            }
            return HomeShell(user: user, auth: _auth);
          },
        );
      },
    );
  }
}
