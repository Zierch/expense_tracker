import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class CategoryPieChart extends StatelessWidget {
  final Map<String, double> data;

  const CategoryPieChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final colors = _generateColors(entries.length);

    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 60,
              sections: entries.asMap().entries.map((e) {
                final index = e.key;
                final entry = e.value;
                final percentage = (entry.value / total * 100);
                return PieChartSectionData(
                  value: entry.value,
                  title: '${percentage.toStringAsFixed(1)}%',
                  color: colors[index],
                  radius: 80,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  badgeWidget: percentage > 10 ? _Badge(entry.key, colors[index]) : null,
                  badgePositionPercentageOffset: 1.1,
                );
              }).toList(),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(total),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _generateColors(int count) {
    final baseColors = [
      Colors.orange, Colors.blue, Colors.purple, Colors.pink,
      Colors.red, Colors.indigo, Colors.teal, Colors.amber,
      Colors.cyan, Colors.deepOrange,
    ];
    return List.generate(count, (i) => baseColors[i % baseColors.length]);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}