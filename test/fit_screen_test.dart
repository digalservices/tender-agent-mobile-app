import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/bid_check.dart';
import 'package:tender_agent_mobile/screens/bid_check_screen.dart';
import 'package:tender_agent_mobile/screens/landing_screen.dart';
import 'package:tender_agent_mobile/screens/mobile_signin_screen.dart';
import 'package:tender_agent_mobile/services/api_client.dart';

/// A server stand-in with one tender file added (so the second page can be reached).
class _EmptyApi extends ApiClient {
  @override
  Future<BidCheckStatus> bidCheck() async => BidCheckStatus.fromJson({
    'files': {'tender': ['nit.pdf'], 'bid': []},
  });

  @override
  Future<void> addBidCheckFile(String kind, String name, Uint8List data) async {}
}

/// The pages before sign-in are drawn to fit the phone: no scrolling on any phone size. The test uses the real Roboto
/// font from the Flutter SDK (the default test font is far wider than a real one, so it would give wrong heights).
const _fonts = 'C:/mobile app/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadRoboto() async {
  final loader = FontLoader('Roboto');
  for (final f in ['regular', 'medium', 'bold']) {
    final bytes = File('$_fonts/roboto-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

// logical size (width, height) of phones from small to tall
const _phones = {
  'small 320x568': Size(320, 568),
  'compact 360x640': Size(360, 640),
  'common 360x800': Size(360, 800),
  'tall 412x915': Size(412, 915),
};

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData(fontFamily: 'Roboto'),
  home: home,
);

void _phone(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 28, bottom: 48); // status bar and navigation bar
  tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 48);
  addTearDown(tester.view.reset);
}

double _scrollRoom(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .map((s) => s.position.maxScrollExtent)
    .fold(0.0, (a, b) => a > b ? a : b);

void main() {
  setUpAll(_loadRoboto);

  for (final e in _phones.entries) {
    testWidgets('the mobile sign-in page fits a ${e.key} phone without scrolling', (tester) async {
      _phone(tester, e.value);
      await tester.pumpWidget(
        _app(MobileSignInScreen(signIn: (_) async {}, onBack: () {}, onCompanyDetails: () {})),
      );
      await tester.pump();
      expect(tester.takeException(), isNull); // no overflow
      expect(_scrollRoom(tester), lessThan(1.0));
    });

    testWidgets('both Bid Check upload pages fit a ${e.key} phone without scrolling', (tester) async {
      _phone(tester, e.value);
      await tester.pumpWidget(_app(BidCheckScreen(api: _EmptyApi(), onSignOut: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Add the tender'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_scrollRoom(tester), lessThan(1.0), reason: 'step 1');
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(find.text('Upload your technical bid'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_scrollRoom(tester), lessThan(1.0), reason: 'step 2');
    });

    testWidgets('the landing page fits a ${e.key} phone without scrolling', (tester) async {
      _phone(tester, e.value);
      await tester.pumpWidget(_app(LandingScreen(onStart: () {})));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_scrollRoom(tester), lessThan(1.0));
    });
  }
}
