import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.data, required this.colorFor});

  final Map<String, double> data;
  final Color Function(String) colorFor;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    if (total <= 0) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 290;
      final chart = SizedBox(
        width: 150,
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 45,
            sections: [
              for (final entry in entries)
                PieChartSectionData(
                  value: entry.value,
                  color: colorFor(entry.key),
                  radius: 24,
                  showTitle: false,
                ),
            ],
          )),
          SizedBox(
            width: 85,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Total', style: TextStyle(fontSize: 11, color: muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(total),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),
        ]),
      );
      final legend = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colorFor(entry.key), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(entry.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                Text('${(entry.value / total * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12)),
              ]),
            ),
        ],
      );
      if (compact) return Column(children: [chart, const SizedBox(height: 12), legend]);
      return Row(children: [chart, const SizedBox(width: 12), Expanded(child: legend)]);
    });
  }
}
