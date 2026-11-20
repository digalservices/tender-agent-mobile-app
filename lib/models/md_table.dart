/// A Markdown table split into its header and rows (cells with the Markdown still in them).
class MdTable {
  MdTable(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;

  int _find(RegExp re) =>
      header.indexWhere((h) => re.hasMatch(h.toLowerCase().trim()));

  int get rankIndex => _find(RegExp(r'^(rank|#|priority)'));
  int get bidIndex => _find(RegExp(r'bid\s*no|bid\s*id'));

  /// A table of tenders (Rank / Bid No / Tender ...). Only these become cards on a phone: they are wide, with long
  /// text in each row. Other tables (prices, quantities) keep their grid and scroll sideways.
  bool get isTenderTable =>
      header.length >= 4 &&
      (bidIndex >= 0 || rankIndex >= 0) &&
      _find(RegExp(r'tender|title|work')) >= 0;

  /// The column that names the tender: "Tender" / "Title" / "Work", else the one with the longest text.
  int get titleIndex {
    final i = _find(RegExp(r'^(tender|title|work)'));
    if (i >= 0 && i != bidIndex && i != rankIndex) return i;
    var best = -1;
    var bestLen = -1;
    for (var c = 0; c < header.length; c++) {
      if (c == rankIndex || c == bidIndex) continue;
      final len = rows.fold<int>(
        0,
        (n, r) => n + (c < r.length ? r[c].length : 0),
      );
      if (len > bestLen) {
        best = c;
        bestLen = len;
      }
    }
    return best;
  }
}

final _separatorCell = RegExp(r'^:?-{2,}:?$');

List<String> _cells(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  return [for (final c in t.split('|')) c.trim()];
}

/// Reads a Markdown table chunk (header line, a ---|--- line, then rows). Null when it is not one.
MdTable? parseMdTable(String chunk) {
  final lines = [
    for (final l in chunk.split('\n'))
      if (l.trim().startsWith('|')) l,
  ];
  if (lines.length < 3) return null;
  final header = _cells(lines[0]);
  final sep = _cells(lines[1]);
  if (sep.isEmpty || !sep.every(_separatorCell.hasMatch)) return null;
  final rows = <List<String>>[];
  for (final l in lines.skip(2)) {
    final c = _cells(l);
    rows.add([for (var i = 0; i < header.length; i++) i < c.length ? c[i] : '']);
  }
  return MdTable(header, rows);
}
