import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:tender_agent_mobile/models/tender.dart';
import 'package:tender_agent_mobile/models/tender_filters.dart';

Tender _t(
  String id, {
  String dept = 'PWD',
  String loc = 'Odisha',
  double? value = 1.0,
  int match = 80,
  String? deadline,
  bool isNew = false,
}) => Tender.fromJson({
  'id': id,
  'title': 'Road work $id',
  'department': dept,
  'location': loc,
  'category': 'Civil',
  'type': 'Works',
  'value_cr': value,
  'match': match,
  'deadline': deadline,
  'is_new': isNew,
});

void main() {
  final rows = [
    _t(
      '1',
      dept: 'PWD',
      loc: 'Odisha',
      value: 0.5,
      match: 90,
      deadline: '2026-10-20',
    ),
    _t(
      '2',
      dept: 'MCL',
      loc: 'Odisha',
      value: 2.0,
      match: 60,
      deadline: '2026-10-25',
      isNew: true,
    ),
    _t('3', dept: 'PWD', loc: 'Karnataka', value: null, match: 40),
  ];

  test(
    'no filters keeps everything',
    () => expect(const TenderFilters().apply(rows).length, 3),
  );

  test('search by BID NO, department and place', () {
    expect(const TenderFilters(query: '2').apply(rows).map((t) => t.id), ['2']);
    expect(const TenderFilters(query: 'mcl').apply(rows).length, 1);
  });

  test('dropdown, value range and match filters combine', () {
    final f = const TenderFilters(location: {'Odisha'}, minCr: 1, minMatch: 50);
    expect(f.apply(rows).map((t) => t.id), ['2']);
  });

  test('location, department, category and type take several choices', () {
    // A tender passes when it matches ANY choice of a filter; none chosen means all.
    expect(
      const TenderFilters(
        location: {'Odisha', 'Karnataka'},
      ).apply(rows).map((t) => t.id),
      ['1', '2', '3'],
    );
    expect(
      const TenderFilters(location: {'Karnataka'}).apply(rows).map((t) => t.id),
      ['3'],
    );
    expect(
      const TenderFilters(
        department: {'PWD'},
        location: {'Odisha', 'Karnataka'},
      ).apply(rows).map((t) => t.id),
      ['1', '3'], // both are PWD; one is in Odisha, one in Karnataka
    );
    expect(const TenderFilters(location: {}).apply(rows).length, 3);
    expect(
      const TenderFilters(location: {'Odisha', 'Karnataka'}).advancedCount,
      1,
    ); // one filter, however many choices
  });

  test('a tender without a value never passes a value filter', () {
    expect(const TenderFilters(maxCr: 5).apply(rows).map((t) => t.id), [
      '1',
      '2',
    ]);
  });

  test('deadline range', () {
    final f = TenderFilters(
      deadline: DateTimeRange(
        start: DateTime(2026, 10, 21),
        end: DateTime(2026, 10, 30),
      ),
    );
    expect(f.apply(rows).map((t) => t.id), ['2']);
  });

  test('advancedCount and isActive', () {
    expect(const TenderFilters().isActive, false);
    expect(
      const TenderFilters(location: {'Odisha'}, minMatch: 10).advancedCount,
      2,
    );
  });

  test('sorting', () {
    expect(sortTenders(rows, TenderSort.matchHighest).map((t) => t.id), [
      '1',
      '2',
      '3',
    ]);
    expect(sortTenders(rows, TenderSort.deadlineEarliest).map((t) => t.id), [
      '1',
      '2',
      '3',
    ]); // no deadline last
    expect(sortTenders(rows, TenderSort.valueHighest).first.id, '2');
  });

  test('tabs', () {
    expect(rows.where((t) => inTab(t, TenderTab.newOnes)).map((t) => t.id), [
      '2',
    ]);
  });

  test('pageWindow matches the website (1 2 3 4 5 … 100)', () {
    expect(pageWindow(1, 100), [1, 2, 3, 4, 5, null, 100]);
    expect(pageWindow(50, 100), [1, null, 49, 50, 51, null, 100]);
    expect(pageWindow(100, 100), [1, null, 96, 97, 98, 99, 100]);
    expect(pageWindow(2, 5), [1, 2, 3, 4, 5]);
  });
}
