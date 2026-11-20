import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/md_table.dart';
import 'package:tender_agent_mobile/widgets/table_cards.dart';

const _ranked = '''
| Rank | Bid No | Tender | Authority | Value | Due | Risk | Why it fits |
|---|---|---|---|---|---|---|---|
| 1 | 9093781539577726 | Storm water drain construction at Puri | PWD | ₹1.2 Crore | 2026-11-07 | Low | Matches our drainage work and the turnover covers it |
| 2 | 9864280985487561 | Upgradation of road | Rural Dev | — | 2026-11-09 | Medium | Value not stated |
''';

void main() {
  test('a ranked tender table is recognised and read', () {
    final t = parseMdTable(_ranked)!;
    expect(t.isTenderTable, isTrue);
    expect(t.rows.length, 2);
    expect((t.rankIndex, t.bidIndex, t.titleIndex), (0, 1, 2));
    expect(t.rows[0][2], 'Storm water drain construction at Puri');
  });

  test('other tables keep their grid', () {
    const prices = '| Item | Qty | Rate |\n|---|---|---|\n| Cement | 10 | 400 |\n';
    expect(parseMdTable(prices)!.isTenderTable, isFalse);
    expect(parseMdTable('not a table'), isNull);
  });

  testWidgets('each tender becomes a card with rank, title, BID NO and facts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TableCards(
              table: parseMdTable(_ranked)!,
              style: MarkdownStyleSheet(),
              onTapLink: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.textContaining('Storm water drain'), findsOneWidget);
    expect(find.text('BID NO 9093781539577726'), findsOneWidget);
    // Closed at first: only the name and the BID NO, with a "Details" toggle.
    expect(find.text('Details'), findsNWidgets(2));
    expect(find.textContaining('Risk: Low'), findsNothing);
    // Tapping a card opens its details.
    await tester.tap(find.text('Details').first);
    await tester.pump();
    expect(find.textContaining('Risk: Low'), findsOneWidget);
    expect(find.textContaining('Why it fits'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    expect(find.textContaining('Risk: Medium'), findsNothing); // the other card is still closed
    await tester.tap(find.text('Hide details'));
    await tester.pump();
    expect(find.textContaining('Risk: Low'), findsNothing);
  });
}
