import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/tender.dart';
import 'package:tender_agent_mobile/models/tender_filters.dart';
import 'package:tender_agent_mobile/screens/tenders_screen.dart';

Tender tender(String title) =>
    Tender.fromJson({'id': title, 'title': title});

void main() {
  test('the search splits at commas and spaces', () {
    expect(searchWords('manpower,civil'), ['manpower', 'civil']);
    expect(searchWords(' Manpower ,  Civil work '), ['manpower', 'civil', 'work']);
    expect(searchWords(''), isEmpty);
  });

  test('hits count the words found; an exact phrase counts as every word', () {
    final t = tender('civil work and manpower supply');
    expect(queryHits(t, 'manpower,civil'), 2);
    expect(queryHits(t, 'manpower,roads'), 1);
    expect(queryHits(t, 'roads,bridge'), 0);
    expect(queryHits(tender('new road construction'), 'road construction'), 2);
  });

  test('a tender with any of the words stays; none of them is hidden', () {
    final f = const TenderFilters(query: 'manpower,civil');
    expect(f.matches(tender('manpower only')), isTrue);
    expect(f.matches(tender('roads only')), isFalse);
  });

  test('all the words first, then some, each group keeping its order', () {
    final rows = [
      tender('civil only A'),
      tender('manpower and civil B'),
      tender('manpower only C'),
      tender('civil and manpower D'),
    ];
    final out = bestMatchesFirst(rows, 'manpower,civil').map((t) => t.title);
    expect(out, [
      'manpower and civil B',
      'civil and manpower D',
      'civil only A',
      'manpower only C',
    ]);
    expect(bestMatchesFirst(rows, 'civil'), rows);
  });

  tendersScreenSearch();
}

// The Tenders screen's own list (when the live search is off).
void tendersScreenSearch() {
  test('the Tenders screen keeps a tender with any of the words', () {
    expect(matchesQuery(tender('manpower only'), 'manpower,civil'), isTrue);
    expect(matchesQuery(tender('roads only'), 'manpower,civil'), isFalse);
    expect(matchesQuery(tender('new road construction'), 'road construction'), isTrue);
    expect(matchesQuery(tender('anything'), ''), isTrue);
  });
}
