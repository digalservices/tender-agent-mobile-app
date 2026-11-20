import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/activity.dart';
import 'package:tender_agent_mobile/models/compare.dart';
import 'package:tender_agent_mobile/models/tender.dart';

Tender tender(
  String id, {
  int match = 70,
  String risk = 'Medium',
  int? daysLeft = 10,
  List<Map<String, String>> reqs = const [],
}) => Tender.fromJson({
  'id': id,
  'title': 'T$id',
  'match': match,
  'risk': risk,
  'days_left': daysLeft,
  'doc_cost_cr': 0.001,
  'requirements': reqs,
});

void main() {
  liveTests();
  test('bestIndexes marks the best value, or nothing when it is a tie', () {
    expect(bestIndexes([5, 9, 7]), {1});
    expect(bestIndexes([5, 9, 7], higher: false), {0});
    expect(bestIndexes([4, 4, 4]), isEmpty);
    expect(
      bestIndexes([null, 3]),
      isEmpty,
    ); // one known value: nothing to choose
    expect(bestIndexes([2, null, 2, 1]), {0, 2});
  });

  test('requirementsMet ignores info lines', () {
    final t = tender(
      '1',
      reqs: [
        {'label': 'a', 'status': 'met'},
        {'label': 'b', 'status': 'verify'},
        {'label': 'c', 'status': 'info'},
      ],
    );
    expect(requirementsMet(t), (1, 2));
  });

  test('recommended: match first, then lower risk, then more time', () {
    expect(
      recommended([tender('a', match: 80), tender('b', match: 90)]).id,
      'b',
    );
    expect(
      recommended([
        tender('a', match: 80, risk: 'High'),
        tender('b', match: 80, risk: 'Low'),
      ]).id,
      'b',
    );
    expect(
      recommended([tender('a', daysLeft: 3), tender('b', daysLeft: 20)]).id,
      'b',
    );
  });

  test('a tender carries its document fee', () {
    expect(tender('1').docCostCr, 0.001);
  });

  test('an agent run adds the cheap reading model tokens', () {
    final r = AgentRun.fromJson({
      'id': 'x',
      'kind': 'Question',
      'status': 'success',
      'started_at': '2026-10-17T06:30:00+00:00',
      'duration_s': 75.4,
      'steps': ['a', 'b'],
      'input_tokens': 1000,
      'output_tokens': 200,
      'read_input_tokens': 300,
      'read_output_tokens': 50,
      'cost_usd': 0.0303,
    });
    expect(r.ok, isTrue);
    expect(r.tokens, 1550);
    expect(r.costUsd, 0.0303);
    expect(r.steps.length, 2);
    expect(r.startedAt, isNotNull);
  });

  test('cost wording', () {
    expect(formatCost(0), '\$0.00');
    expect(formatCost(0.0004), '<\$0.001');
    expect(formatCost(0.0303), '\$0.0303');
    expect(formatCost(0.293), '\$0.293');
    expect(formatCost(2.327), '\$2.33');
  });

  test('duration, token and day wording', () {
    expect(formatDuration(45), '45s');
    expect(formatDuration(192), '3m 12s');
    expect(formatTokens(950), '950');
    expect(formatTokens(12300), '12.3k');
    expect(formatTokens(1400000), '1.4M');
    final now = DateTime(2026, 10, 17, 12);
    expect(dayLabel(DateTime(2026, 10, 17, 3), now), 'Today');
    expect(dayLabel(DateTime(2026, 10, 16), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 10, 12), now), 'Mon, 12 Oct 2026');
  });
}

void liveTests() {
  test('a live page carries its total, page count and tenders', () {
    final page = LivePage.fromJson({
      'total': 103,
      'pages': 11,
      'page': 2,
      'tenders': [
        {'id': '9123', 'title': 'Road', 'match': 80},
        {'id': '9124', 'title': 'Drain', 'match': 60},
      ],
    });
    expect(page.tenders.map((t) => t.id), ['9123', '9124']);
    expect((page.total, page.pages, page.page), (103, 11, 2));
    expect(page.totalText, '103');
    expect(
      LivePage.fromJson({'total': 50000, 'tenders': []}).totalText,
      '50,000+',
    );
  });

  test('the feed says whether the tenders are searched live', () {
    expect(
      TenderFeed.fromJson({'source': 'BidAssist', 'live': true}).live,
      isTrue,
    );
    expect(TenderFeed.fromJson({'source': 'TenderDetail'}).live, isFalse);
  });
}
