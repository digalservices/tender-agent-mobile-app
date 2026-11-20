import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/bid_check.dart';
import 'package:tender_agent_mobile/screens/bid_check_screen.dart';
import 'package:tender_agent_mobile/screens/landing_screen.dart';
import 'package:tender_agent_mobile/screens/mobile_signin_screen.dart';
import 'package:tender_agent_mobile/services/api_client.dart';
import 'package:tender_agent_mobile/services/auth_service.dart';

class FakeApi extends ApiClient {
  final calls = <String>[];
  String? otpError, verifyError;
  bool returning = false;
  BidCheckStatus status = BidCheckStatus.fromJson({
    'files': {'tender': [], 'bid': []},
  });

  @override
  Future<({String phone, bool returning})> requestOtp(String phone) async {
    calls.add('otp:$phone');
    if (otpError != null) throw ApiException(otpError!);
    return (phone: '+91 98765 43210', returning: returning);
  }

  @override
  Future<String> verifyOtp(String phone, String code, String company) async {
    calls.add('verify:$phone:$code:$company');
    if (verifyError != null) throw ApiException(verifyError!);
    return 'TOKEN';
  }

  @override
  Future<BidCheckStatus> bidCheck() async => status;

  @override
  Future<void> addBidCheckFile(String kind, String name, Uint8List data) async {
    calls.add('add:$kind:$name');
  }

  @override
  Future<void> startBidCheck() async => calls.add('start');

  @override
  Future<void> clearBidCheck() async => calls.add('clear');

  @override
  Future<void> clearBidCheckFiles(String kind) async => calls.add('clearfiles:$kind');
}

Map<String, dynamic> report() => {
  'tender': {'title': 'Security services', 'authority': 'HPCL', 'closing_date': '2026-11-20'},
  'summary': {
    'total': 4, 'done': 1, 'wrong': 1, 'missing': 1, 'unclear': 1, 'score': 47, 'risk_count': 2,
    'groups': {'Eligibility': {'total': 2, 'done': 1, 'score': 50}},
  },
  'steps': [
    {'id': 'S1', 'group': 'Eligibility', 'title': 'PSARA licence', 'detail': 'Valid licence', 'ref': 'A.1', 'weight': 3, 'status': 'done', 'found_in': 'bid.pdf, page 5', 'cause': '', 'fix': ''},
    {'id': 'S2', 'group': 'Eligibility', 'title': 'Turnover proof', 'detail': 'CA certificate', 'ref': '', 'weight': 3, 'status': 'missing', 'found_in': '', 'cause': 'Only 2 years', 'fix': 'Add the third year'},
    {'id': 'S3', 'group': 'Forms', 'title': 'Declaration', 'detail': 'Signed', 'ref': '', 'weight': 1, 'status': 'wrong', 'found_in': 'p22', 'cause': 'Unsigned', 'fix': 'Sign it'},
    {'id': 'S4', 'group': 'Forms', 'title': 'Stamp', 'detail': 'Seal', 'ref': '', 'weight': 1, 'status': 'unclear', 'found_in': '', 'cause': '', 'fix': ''},
  ],
  'warnings': ['Your bid is long'],
};

/// A phone-sized screen, so overflow and off-screen buttons show up like they would on the phone.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800); // tall: the test font is wider than a real one
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the report model', () {
    test('reads the numbers, the groups and the steps', () {
      final r = BidReport.fromJson(report());
      expect((r.score, r.done, r.total, r.problems, r.riskCount), (47, 1, 4, 2, 2));
      expect(r.groups.single.name, 'Eligibility');
      expect(r.steps.map((s) => s.risky), [false, true, false, false]);
      expect((r.level, r.levelWord), ('red', 'Needs a lot of work'));
      expect(r.message, '1 of 4 steps are done. 2 need fixing, 2 of them can get the bid rejected.');
    });

    test('levels follow the website: under 60 red, under 85 amber, else green', () {
      BidReport at(int score) => BidReport.fromJson({
        'summary': {'score': score},
      });
      expect(at(59).level, 'red');
      expect(at(60).level, 'amber');
      expect(at(85).level, 'green');
    });

    test('a status with progress and no report', () {
      final s = BidCheckStatus.fromJson({
        'files': {'tender': ['a.pdf'], 'bid': ['b.pdf', 'c.pdf']},
        'running': true, 'stage': 2, 'elapsed': 65.4, 'steps': ['x'], 'report': null, 'error': '',
      });
      expect(s.tenderFiles, ['a.pdf']);
      expect((s.bidFiles.length, s.running, s.stage, s.report), (2, true, 2, null));
      expect(s.stageWord, 'finding what the tender requires');
    });
  });

  group('who gets the Bid Check pages', () {
    test('only active accounts made with a mobile OTP', () {
      expect(accountStatusOf({'status': 'active', 'signup_method': 'mobile_otp'}), AccountStatus.bidCheck);
      expect(accountStatusOf({'status': 'active'}), AccountStatus.active);
      expect(accountStatusOf({'signup_method': 'mobile_otp', 'status': 'pending'}), AccountStatus.pending);
      expect(accountStatusOf(null), AccountStatus.needsProfile);
    });
  });

  group('the first page', () {
    testWidgets('Sign in and Check my bid free both open sign-in', (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(home: LandingScreen(onStart: () => opened++)));
      expect(find.text('Check your bid before you submit.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('landing-signin')));
      await tester.tap(find.byKey(const ValueKey('landing-cta')));
      expect(opened, 2);
    });
  });

  group('mobile sign-in', () {
    late FakeApi api;
    late List<String> tokens;
    Future<void> open(WidgetTester tester, {void Function()? onCompany}) async {
      phone(tester);
      api = FakeApi();
      tokens = [];
      await tester.pumpWidget(MaterialApp(
        home: MobileSignInScreen(
          api: api,
          signIn: (t) async => tokens.add(t),
          onBack: () {},
          onCompanyDetails: onCompany ?? () {},
        ),
      ));
    }

    testWidgets('Send OTP sends it and says where', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('mobile')), '98765 43210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(api.calls, ['otp:98765 43210']);
      expect(find.text('OTP sent to +91 98765 43210'), findsOneWidget);
      expect(find.text('Resend OTP'), findsOneWidget);
    });

    testWidgets('a refused OTP shows the server message', (tester) async {
      await open(tester);
      api.otpError = 'Please wait 20 seconds before asking for another OTP.';
      await tester.enterText(find.byKey(const ValueKey('mobile')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(find.text('Please wait 20 seconds before asking for another OTP.'), findsOneWidget);
    });

    testWidgets('Continue needs the OTP sent, the company name and 6 digits', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pump();
      expect(find.text('Tap Send OTP first, then enter the code you get.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('mobile')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pump();
      expect(find.text('Enter your company name.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('company')), 'Acme Works');
      await tester.enterText(find.byKey(const ValueKey('otp')), '12');
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pump();
      expect(find.text('Enter the 6-digit OTP.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('verify')), isEmpty);
    });

    testWidgets('a right code signs in with the token the server gives', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('mobile')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
      await tester.enterText(find.byKey(const ValueKey('company')), 'Acme Works');
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pump(); // the screen stays busy until the app swaps it, so it never "settles"
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.last, 'verify:9876543210:123456:Acme Works');
      expect(tokens, ['TOKEN']);
    });

    testWidgets('a number that has an account is not asked for the company name', (tester) async {
      await open(tester);
      api.returning = true;
      await tester.enterText(find.byKey(const ValueKey('mobile')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('company')), findsNothing);
      expect(find.byKey(const ValueKey('welcome-back')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.last, 'verify:9876543210:123456:');
      expect(tokens, ['TOKEN']);
    });

    testWidgets('a wrong code shows the server message and signs nobody in', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('mobile')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      api.verifyError = 'Wrong OTP. 4 tries left.';
      await tester.enterText(find.byKey(const ValueKey('otp')), '111111');
      await tester.enterText(find.byKey(const ValueKey('company')), 'Acme');
      await tester.tap(find.byKey(const ValueKey('signin-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong OTP. 4 tries left.'), findsOneWidget);
      expect(tokens, isEmpty);
    });

    testWidgets('the company details link opens the email log-in', (tester) async {
      var opened = false;
      await open(tester, onCompany: () => opened = true);
      await tester.tap(find.byKey(const ValueKey('signin-company')));
      expect(opened, isTrue);
    });
  });

  group('the Bid Check pages', () {
    testWidgets('step one asks for the tender files before moving on', (tester) async {
      phone(tester);
      final api = FakeApi();
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Add the tender'), findsOneWidget);
      expect(find.text('Menu'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('next')));
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump();
      expect(find.text('Upload the tender PDF (NIT, ATC and corrigenda) first.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('tender-id')), '2026_ABC_1');
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump();
      expect(find.textContaining('coming soon'), findsOneWidget);
    });

    testWidgets('with the tender added the next step asks for the bid, and Check needs bid files', (tester) async {
      phone(tester);
      final api = FakeApi()
        ..status = BidCheckStatus.fromJson({
          'files': {'tender': ['nit.pdf'], 'bid': []},
        });
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('next')));
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(find.text('Upload your technical bid'), findsOneWidget);
      expect(find.text('Tender added'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('check')));
      await tester.tap(find.byKey(const ValueKey('check')));
      await tester.pump();
      expect(find.text('Upload your bid files first.'), findsOneWidget);
      expect(api.calls, isNot(contains('start')));
    });

    testWidgets('Check my bid starts the check', (tester) async {
      phone(tester);
      final api = FakeApi()
        ..status = BidCheckStatus.fromJson({
          'files': {'tender': ['nit.pdf'], 'bid': ['bid.pdf']},
        });
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('next')));
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('check')));
      await tester.tap(find.byKey(const ValueKey('check')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('start'));
    });

    testWidgets('while it runs the stage and time are shown', (tester) async {
      phone(tester);
      final api = FakeApi()
        ..status = BidCheckStatus.fromJson({
          'files': {'tender': [], 'bid': []},
          'running': true, 'stage': 2, 'elapsed': 65.0, 'steps': ['Finding what this tender requires'],
        });
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Step 2 of 3 · finding what the tender requires · 1:05'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // stops the polling timer
    });

    testWidgets('the report shows the numbers, the problems and starts again', (tester) async {
      phone(tester);
      final api = FakeApi()
        ..status = BidCheckStatus.fromJson({
          'files': {'tender': [], 'bid': []},
          'report': report(),
        });
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pumpAndSettle();
      expect(find.text('47%'), findsOneWidget);
      expect(find.text('Needs a lot of work. '), findsNothing); // it is one rich text with the message
      expect(find.textContaining('Needs a lot of work.', findRichText: true), findsOneWidget);
      expect(find.text('Turnover proof'), findsOneWidget);
      expect(find.text('PSARA licence'), findsNothing); // done steps are hidden under "Problems"
      await tester.tap(find.text('All steps'));
      await tester.pumpAndSettle();
      expect(find.text('PSARA licence'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('check-another')), 400,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
      await tester.ensureVisible(find.byKey(const ValueKey('check-another')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-another')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('clear'));
    });

    testWidgets('a failed check shows why and Try again clears it', (tester) async {
      phone(tester);
      final api = FakeApi()
        ..status = BidCheckStatus.fromJson({
          'files': {'tender': [], 'bid': []},
          'error': 'The files could not be read.',
        });
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: api, onSignOut: () {})));
      await tester.pumpAndSettle();
      expect(find.text('The files could not be read.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('try-again')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('clear'));
    });

    testWidgets('Sign out is there', (tester) async {
      phone(tester);
      var out = false;
      await tester.pumpWidget(MaterialApp(home: BidCheckScreen(api: FakeApi(), onSignOut: () => out = true)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      expect(out, isTrue);
    });
  });
}
