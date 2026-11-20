import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/tender.dart';
import 'package:tender_agent_mobile/screens/tenders_screen.dart';

Tender _tender(Map<String, dynamic> extra) => Tender.fromJson({
  'id': '57931720',
  'tender_no': 'MCL/GM/OA/SO(C)/e-T/26-27/24',
  'title': 'Construction Of Cement Concrete Road',
  'department': 'Mahanadi Coalfields Limited',
  'sub_department': 'Jharsuguda, Odisha',
  'location': 'Odisha',
  'category': 'Civil',
  'type': 'Works',
  'value_cr': 2.07,
  'deadline': '2026-10-24',
  'days_left': 12,
  'match': 91,
  'risk': 'Low',
  'analysis': {'Scope match': 100},
  'requirements': [
    {'label': 'Scope matches', 'status': 'met'},
  ],
  'documents': [
    {'label': 'PAN card', 'have': true},
  ],
  ...extra,
});

void main() {
  savedSnapshotTests();
  test('parses the backend JSON, with BID NO as the id', () {
    final t = _tender({});
    expect(t.id, '57931720');
    expect(t.match, 91);
    expect(t.requirements.single.status, 'met');
    expect(t.documents.single.have, true);
  });

  test('search finds a tender by BID NO, authority or place', () {
    final t = _tender({});
    expect(matchesQuery(t, '57931720'), true);
    expect(matchesQuery(t, 'mahanadi'), true);
    expect(matchesQuery(t, 'jharsuguda'), true);
    expect(matchesQuery(t, 'karnataka'), false);
    expect(matchesQuery(t, '  '), true);
  });

  test('formatValueCr matches the web app wording', () {
    expect(formatValueCr(null), 'Not stated');
    expect(formatValueCr(2.0707105), '₹2.07 Crore');
    expect(formatValueCr(0.25), '₹25 Lakhs');
    expect(formatValueCr(0.00294), '₹29,400');
  });

  test('saved snapshot uses the web app field names', () {
    final s = _tender({}).toSavedSnapshot();
    expect(s['tender_no'], isNotEmpty);
    expect(
      s.keys,
      containsAll(['title', 'department', 'value_cr', 'deadline', 'link']),
    );
  });
}

void savedSnapshotTests() {
  test('a saved snapshot works out days left from its deadline', () {
    final soon = DateTime.now().add(const Duration(days: 3));
    final iso =
        '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    final t = Tender.fromJson({
      'id': '1',
      'title': 'x',
      'deadline': iso,
      'match': 70,
      'risk': 'Low',
    });
    expect(t.daysLeft, 3);
    expect(t.closingSoon, true);
    expect(t.requirements, isEmpty);
  });
}
