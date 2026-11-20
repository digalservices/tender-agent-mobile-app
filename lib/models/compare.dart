import 'tender.dart';

/// Up to four tenders can be put side by side (the website's limit too).
const maxCompare = 4;

const _riskRank = {'Low': 0, 'Medium': 1, 'High': 2};

int riskRank(String risk) => _riskRank[risk] ?? 1;

/// Indexes of the best value(s); empty when there is nothing to choose between (fewer than two known
/// values, or all equal). Same rule as the website's comparison.
Set<int> bestIndexes(List<num?> values, {bool higher = true}) {
  final known = [
    for (var i = 0; i < values.length; i++)
      if (values[i] != null) (i, values[i]!),
  ];
  if (known.length < 2 || known.map((e) => e.$2).toSet().length == 1) {
    return {};
  }
  final target = known
      .map((e) => e.$2)
      .reduce((a, b) => (higher ? a >= b : a <= b) ? a : b);
  return {
    for (final e in known)
      if (e.$2 == target) e.$1,
  };
}

/// (requirements met, requirements checked) - "info" lines are not checks.
(int, int) requirementsMet(Tender t) {
  final checks = [
    for (final r in t.requirements)
      if (r.status != 'info') r.status,
  ];
  return (checks.where((s) => s == 'met').length, checks.length);
}

/// Best fit: highest match, then lower risk, then more time to prepare.
Tender recommended(List<Tender> items) {
  var best = items.first;
  for (final t in items.skip(1)) {
    if (_better(t, best)) best = t;
  }
  return best;
}

bool _better(Tender a, Tender b) {
  if (a.match != b.match) return a.match > b.match;
  if (riskRank(a.risk) != riskRank(b.risk)) {
    return riskRank(a.risk) < riskRank(b.risk);
  }
  return (a.daysLeft ?? 0) > (b.daysLeft ?? 0);
}
