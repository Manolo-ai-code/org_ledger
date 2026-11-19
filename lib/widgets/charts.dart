import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/app_format.dart';
import '../providers/ledger_provider.dart';
import 'brand_mark.dart';

/// Donut chart + legend for approved spending by category.
class CategoryBreakdownCard extends StatelessWidget {
  const CategoryBreakdownCard({
    super.key,
    required this.totals,
    required this.total,
  });

  final Map<String, double> totals;
  final double total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, double> collapsed = _collapse(totals);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Spending by category',
              subtitle: 'Approved expenses only',
            ),
            const SizedBox(height: 14),
            if (collapsed.isEmpty || total <= 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.donut_large_rounded,
                      size: 34,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No approved spending yet',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Category insights appear once the Adviser grants final approval.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool stacked = constraints.maxWidth < 390;
                  final Widget chart = SizedBox(
                    width: stacked ? 180 : 158,
                    height: stacked ? 180 : 158,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 48,
                            startDegreeOffset: -90,
                            sections: collapsed.entries
                                .toList()
                                .asMap()
                                .entries
                                .map(
                                  (MapEntry<int, MapEntry<String, double>>
                                          indexed) =>
                                      PieChartSectionData(
                                    value: AppFormat.safeNumber(
                                      indexed.value.value,
                                    ),
                                    color: AppColors.category(indexed.key),
                                    radius: 26,
                                    showTitle: false,
                                    borderSide: const BorderSide(
                                      color: Colors.white,
                                      width: 1.4,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          duration: const Duration(milliseconds: 650),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              AppFormat.compactCurrency(total),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'approved',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );

                  final Widget legend = Column(
                    children: collapsed.entries
                        .toList()
                        .asMap()
                        .entries
                        .map(
                          (MapEntry<int, MapEntry<String, double>> indexed) {
                            final String label = indexed.value.key;
                            final double amount = indexed.value.value;
                            final double share = total > 0
                                ? AppFormat.clampRatio(amount, total)
                                : 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.category(indexed.key),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    AppFormat.percent(share, decimals: 0),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      AppFormat.compactCurrency(amount),
                                      textAlign: TextAlign.right,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                        .toList(growable: false),
                  );

                  if (stacked) {
                    return Column(
                      children: <Widget>[
                        Center(child: chart),
                        const SizedBox(height: 14),
                        legend,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      chart,
                      const SizedBox(width: 16),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Keeps the legend readable: top six categories plus an "Other" bucket.
  Map<String, double> _collapse(Map<String, double> source) {
    if (source.length <= 6) {
      return source;
    }
    final List<MapEntry<String, double>> entries = source.entries.toList();
    final Map<String, double> result = <String, double>{};
    for (int i = 0; i < 5; i++) {
      result[entries[i].key] = entries[i].value;
    }
    double rest = 0;
    for (int i = 5; i < entries.length; i++) {
      rest += entries[i].value;
    }
    result['Other categories'] = rest;
    return result;
  }
}

/// Line chart showing the remaining budget after each approved expense.
class BurnDownChart extends StatelessWidget {
  const BurnDownChart({
    super.key,
    required this.points,
    required this.budget,
  });

  final List<BurnDownPoint> points;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (points.isEmpty) {
      return const SizedBox(height: 150);
    }

    double minRemaining = 0;
    for (final BurnDownPoint point in points) {
      if (point.remaining < minRemaining) {
        minRemaining = point.remaining;
      }
    }
    final double maxY = math.max(
      math.max(budget, 1),
      points.map((BurnDownPoint p) => p.remaining).fold<double>(0, math.max),
    );
    final double lowerY = math.min(minRemaining, 0);
    final double span = maxY - lowerY;
    final double yInterval = math.max(span / 4, 1);
    final List<FlSpot> spots = points
        .map(
          (BurnDownPoint point) => FlSpot(
            point.index.toDouble(),
            AppFormat.safeNumber(point.remaining),
          ),
        )
        .toList(growable: false);
    final int lastIndex = points.length - 1;
    final double xInterval = lastIndex <= 1 ? 1 : (lastIndex / 3).ceilToDouble();

    return SizedBox(
      height: 168,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: lastIndex <= 0 ? 1 : lastIndex.toDouble(),
          minY: lowerY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (double value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 54,
                interval: yInterval,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      AppFormat.compactCurrency(value),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: xInterval,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (index != 0 && index != lastIndex &&
                      index % xInterval.round() != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[index].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot touchedSpot) =>
                  theme.colorScheme.inverseSurface,
              getTooltipItems: (List<LineBarSpot> touched) {
                return touched
                    .map(
                      (LineBarSpot spot) => LineTooltipItem(
                        AppFormat.currency(spot.y),
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    )
                    .toList(growable: false);
              },
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.emerald,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: points.length <= 12,
                getDotPainter: (
                  FlSpot spot,
                  double percent,
                  LineChartBarData barData,
                  int index,
                ) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: AppColors.emerald,
                    strokeWidth: 1.5,
                    strokeColor: theme.colorScheme.surface,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppColors.emerald.withValues(alpha: 0.2),
                    AppColors.emerald.withValues(alpha: 0.01),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 600),
      ),
    );
  }
}
