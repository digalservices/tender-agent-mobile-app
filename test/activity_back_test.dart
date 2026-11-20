import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/activity.dart';
import 'package:tender_agent_mobile/screens/activity_screen.dart';
import 'package:tender_agent_mobile/services/api_client.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.admin = true});
  final bool admin;

  @override
  Future<List<AgentRun>> activity() async => [
    AgentRun.fromJson({
      'id': '1',
      'kind': 'Tender search',
      'question': 'Find the best tenders for me',
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'duration_s': 42,
      'status': 'success',
      'steps': ['🔎 Searching BidAssist live: road', '📄 Opening BidAssist tender 9123', '📥 Downloading tender documents for 9123'],
      'tenders_found': 3,
    }),
  ];

  @override
  Future<TenderStatus> tenderStatus() async => TenderStatus.fromJson({
    'source': 'BidAssist',
    'live': true,
    'notice': '',
    'is_admin': admin,
    'admin': admin
        ? {
            'can_switch': true,
            'choice': 'bidassist_api',
            'have_tenderdetail_key': true,
            'token': {'ok': true, 'message': 'Works.', 'plan_end': '2027-08-05', 'days_left': 300, 'token_from': '.env'},
          }
        : null,
  });
}

void main() {
  for (final (tenders, admin) in [(false, true), (true, true), (true, false)]) {
    testWidgets('back from Agent & Tender Activity (tenders: $tenders, admin: $admin)', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 900));
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(c).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityScreen(onAsk: (_) {}, api: _FakeApi(admin: admin)),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      if (tenders) {
        await t.tap(find.text('Tenders'));
        await t.pumpAndSettle();
      }
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  }
}
