import 'package:flutter/material.dart';

import '../theme.dart';

/// A horizontal bar per label, the bar length relative to the biggest value. Used by the Reports charts.
class HBarList extends StatelessWidget {
  const HBarList({super.key, required this.items, this.color = AppColors.blue});
  final List<(String label, num value)> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Nothing to show yet.'),
      );
    }
    final top = items.map((e) => e.$2).fold<num>(0, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: top == 0 ? 0 : value / top,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                    color: color,
                    backgroundColor: color.withAlpha(30),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Vertical bars over a range of days. Each bar is a stack of segments (for example success and error runs).
class DayBars extends StatelessWidget {
  const DayBars({
    super.key,
    required this.days,
    required this.colors,
    this.height = 120,
  });

  /// One entry per day: its short label and the height of each stacked segment.
  final List<(String label, List<num> parts)> days;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top = days
        .map((d) => d.$2.fold<num>(0, (a, b) => a + b))
        .fold<num>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: height + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (label, parts) in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = parts.length - 1; i >= 0; i--)
                      if (parts[i] > 0 && top > 0)
                        Container(
                          height: height * parts[i] / top,
                          color: colors[i % colors.length],
                        ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 16,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small coloured number tile (the website's KPI tiles).
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

/// KPI tiles laid out two per row.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});
  final List<KpiTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in tiles)
          SizedBox(width: (box.maxWidth - 10) / 2, child: t),
      ],
    ),
  );
}
