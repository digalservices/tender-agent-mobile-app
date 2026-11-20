import 'package:flutter/material.dart' show DateTimeRange;

import 'tender.dart';

/// The dashboard's tabs: All / New / Closing soon / High-value (same as the website).
enum TenderTab { all, newOnes, closing, highValue }

const tabLabels = {
  TenderTab.all: 'All Tenders',
  TenderTab.newOnes: 'New',
  TenderTab.closing: 'Closing Soon',
  TenderTab.highValue: 'High-Value',
};

enum TenderSort {
  deadlineEarliest,
  deadlineLatest,
  matchHighest,
  valueHighest,
  recentlyPublished,
}

const sortLabels = {
  TenderSort.deadlineEarliest: 'Bid Deadline (Earliest)',
  TenderSort.deadlineLatest: 'Bid Deadline (Latest)',
  TenderSort.matchHighest: 'Match Score (Highest)',
  TenderSort.valueHighest: 'Value (Highest)',
  TenderSort.recentlyPublished: 'Recently Published',
};

bool inTab(Tender t, TenderTab tab) => switch (tab) {
  TenderTab.all => true,
  TenderTab.newOnes => t.isNew,
  TenderTab.closing => t.closingSoon,
  TenderTab.highValue => t.highValue,
};

/// "Search & Filter Tenders" - the same filters as the website's dashboard.
class TenderFilters {
  const TenderFilters({
    this.query = '',
    this.location = const {},
    this.department = const {},
    this.category = const {},
    this.type = const {},
    this.minCr,
    this.maxCr,
    this.deadline,
    this.published,
    this.minMatch = 0,
  });

  final String query;
  // Several choices each; none chosen = all.
  final Set<String> location;
  final Set<String> department;
  final Set<String> category;
  final Set<String> type;
  final double? minCr;
  final double? maxCr;
  final DateTimeRange? deadline;
  final DateTimeRange? published;
  final int minMatch;

  /// How many filters differ from "show everything" (the badge on Advanced filters).
  int get advancedCount => [
    location.isNotEmpty,
    department.isNotEmpty,
    category.isNotEmpty,
    type.isNotEmpty,
    minCr != null,
    maxCr != null,
    deadline != null,
    published != null,
    minMatch > 0,
  ].where((x) => x).length;

  bool get isActive => query.trim().isNotEmpty || advancedCount > 0;

  TenderFilters copyWith({
    String? query,
    Set<String>? location,
    Set<String>? department,
    Set<String>? category,
    Set<String>? type,
    Object? minCr = _keep,
    Object? maxCr = _keep,
    Object? deadline = _keep,
    Object? published = _keep,
    int? minMatch,
  }) => TenderFilters(
    query: query ?? this.query,
    location: location ?? this.location,
    department: department ?? this.department,
    category: category ?? this.category,
    type: type ?? this.type,
    minCr: identical(minCr, _keep) ? this.minCr : minCr as double?,
    maxCr: identical(maxCr, _keep) ? this.maxCr : maxCr as double?,
    deadline: identical(deadline, _keep)
        ? this.deadline
        : deadline as DateTimeRange?,
    published: identical(published, _keep)
        ? this.published
        : published as DateTimeRange?,
    minMatch: minMatch ?? this.minMatch,
  );

  bool matches(Tender t) {
    if (query.trim().isNotEmpty && queryHits(t, query) == 0) return false;
    if (location.isNotEmpty && !location.contains(t.location)) return false;
    if (department.isNotEmpty && !department.contains(t.department)) {
      return false;
    }
    if (category.isNotEmpty && !category.contains(t.category)) return false;
    if (type.isNotEmpty && !type.contains(t.type)) return false;
    if (minCr != null && (t.valueCr == null || t.valueCr! < minCr!))
      return false;
    if (maxCr != null && (t.valueCr == null || t.valueCr! > maxCr!))
      return false;
    if (!_inRange(t.deadlineDate, deadline) ||
        !_inRange(t.publishedDate, published))
      return false;
    return t.match >= minMatch;
  }

  List<Tender> apply(Iterable<Tender> all) => [
    for (final t in all)
      if (matches(t)) t,
  ];
}

const _keep = Object();

/// "manpower, civil" -> [manpower, civil]: the search splits at commas and spaces.
List<String> searchWords(String query) =>
    query.toLowerCase().split(RegExp(r'[,;\s]+')).where((w) => w.isNotEmpty).toList();

/// How many of the search words are in the tender. The whole search written exactly as typed (an ID, "road
/// construction") counts as every word.
int queryHits(Tender t, String query) {
  final words = searchWords(query);
  if (words.isEmpty) return 0;
  final text =
      '${t.title} ${t.id} ${t.tenderNo} ${t.department} ${t.subDepartment} ${t.category}'
          .toLowerCase();
  if (text.contains(query.trim().toLowerCase())) return words.length;
  return words.where(text.contains).length;
}

/// Tenders with all the search words first, then those with all but one ... (each group keeps its order).
List<Tender> bestMatchesFirst(List<Tender> rows, String query) {
  final n = searchWords(query).length;
  if (n < 2) return rows;
  final hits = {for (final t in rows) t: queryHits(t, query)};
  return [
    for (var k = n; k >= 1; k--)
      for (final t in rows)
        if (hits[t] == k) t,
    for (final t in rows)
      if (hits[t]! < 1 || hits[t]! > n) t,
  ];
}

bool _inRange(DateTime? d, DateTimeRange? range) {
  if (range == null) return true;
  if (d == null) return false;
  final day = DateTime(d.year, d.month, d.day);
  return !day.isBefore(range.start) && !day.isAfter(range.end);
}

List<Tender> sortTenders(Iterable<Tender> rows, TenderSort sort) {
  final out = [...rows];
  final far = DateTime(9999);
  final past = DateTime(1);
  switch (sort) {
    case TenderSort.deadlineEarliest:
      out.sort(
        (a, b) => (a.deadlineDate ?? far).compareTo(b.deadlineDate ?? far),
      );
    case TenderSort.deadlineLatest:
      out.sort(
        (a, b) => (b.deadlineDate ?? past).compareTo(a.deadlineDate ?? past),
      );
    case TenderSort.matchHighest:
      out.sort((a, b) => b.match.compareTo(a.match));
    case TenderSort.valueHighest:
      out.sort((a, b) => (b.valueCr ?? 0).compareTo(a.valueCr ?? 0));
    case TenderSort.recentlyPublished:
      out.sort(
        (a, b) => (b.publishedDate ?? past).compareTo(a.publishedDate ?? past),
      );
  }
  return out;
}

/// Page buttons like 1 2 3 4 5 … 100; `null` marks a gap (same as the website).
List<int?> pageWindow(int current, int pages) {
  if (pages <= 7) return [for (var i = 1; i <= pages; i++) i];
  final Set<int> keep;
  if (current <= 4) {
    keep = {1, 2, 3, 4, 5, pages};
  } else if (current >= pages - 3) {
    keep = {1, for (var i = pages - 4; i <= pages; i++) i};
  } else {
    keep = {1, current - 1, current, current + 1, pages};
  }
  final out = <int?>[];
  var last = 0;
  for (final p in (keep.toList()..sort())) {
    if (p - last > 1) out.add(null);
    out.add(p);
    last = p;
  }
  return out;
}
