import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/data_bus.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 统计页：克制在 3 个视图 —— 分类环形图、分类排行、月度趋势
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => StatsPageState();
}

class StatsPageState extends State<StatsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Category> _cats = [];
  Map<int, double> _totals = {};
  double _expense = 0;
  double _income = 0;
  List<MapEntry<String, double>> _trend = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
    // 订阅数据变更：记账、删账单后自动重新加载
    DataBus.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    load();
  }

  Future<void> load() async {
    final m = formatMonth(_month);
    try {
      final cats = await Db.categories(type: 0);
      final totals = await Db.categoryTotals(m);
      final sum = await Db.monthSummary(m);
      final trend = await Db.monthlyTrend(6);
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _totals = totals;
        _expense = sum[0];
        _income = sum[1];
        _trend = trend;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  void _shift(int d) {
    setState(() {
      _month = DateTime(_month.year, _month.month + d, 1);
      _loading = true;
    });
    load();
  }

  List<MapEntry<Category, double>> get _sorted {
    final list = <MapEntry<Category, double>>[];
    for (final c in _cats) {
      final v = _totals[c.id] ?? 0;
      if (v > 0) list.add(MapEntry(c, v));
    }
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                const Text('统计',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                InkWell(
                  onTap: () => _shift(-1),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left, size: 20, color: AppColors.textSub),
                  ),
                ),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                InkWell(
                  onTap: _isCurrentMonth ? null : () => _shift(1),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right,
                        size: 20,
                        color: _isCurrentMonth ? AppColors.divider : AppColors.textSub),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: load,
                    color: AppColors.primary,
                    child: _expense <= 0 && _expense == 0 && _sorted.isEmpty
                        ? ListView(children: [_empty()])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            children: [
                              _summaryRow(),
                              const SizedBox(height: 16),
                              if (_sorted.isNotEmpty) _donutCard(),
                              if (_sorted.isNotEmpty) const SizedBox(height: 16),
                              if (_sorted.isNotEmpty) _rankCard(),
                              const SizedBox(height: 16),
                              _trendCard(),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    return Row(
      children: [
        Expanded(
          child: _sumCard('支出', _expense, AppColors.expense, Icons.arrow_upward),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sumCard('收入', _income, AppColors.income, Icons.arrow_downward),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sumCard('结余', _income - _expense,
              (_income - _expense) >= 0 ? AppColors.primary : AppColors.danger,
              Icons.account_balance_wallet_outlined),
        ),
      ],
    );
  }

  Widget _sumCard(String label, double v, Color c, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: c),
              const SizedBox(width: 3),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmtCompact(v),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }

  Widget _donutCard() {
    final total = _sorted.fold<double>(0, (a, b) => a + b.value);
    final top = _sorted.take(6).toList();
    final rest = _sorted.skip(6).fold<double>(0, (a, b) => a + b.value);
    final sections = <PieChartSectionData>[];
    for (final e in top) {
      final pct = e.value / total * 100;
      sections.add(PieChartSectionData(
        value: e.value,
        color: e.key.color,
        radius: 22,
        showTitle: pct >= 8,
        title: '${pct.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ));
    }
    if (rest > 0) {
      sections.add(PieChartSectionData(
        value: rest,
        color: AppColors.textSub.withValues(alpha: 0.35),
        radius: 22,
        title: '其他',
        showTitle: rest / total * 100 >= 8,
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('支出构成',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('共 ${fmtMoney(total)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2,
                      centerSpaceRadius: 46,
                      startDegreeOffset: -90,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: top
                        .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                        color: e.key.color,
                                        borderRadius: BorderRadius.circular(2)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(e.key.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11.5)),
                                  ),
                                  Text(
                                    '${(e.value / total * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textSub),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankCard() {
    final max = _sorted.isEmpty ? 1.0 : _sorted.first.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('分类排行',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._sorted.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(e.key.icon, size: 14, color: e.key.color),
                      const SizedBox(width: 6),
                      Text(e.key.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(fmtMoney(e.value),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: e.value / max,
                      minHeight: 5,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation(
                          e.key.color.withValues(alpha: 0.85)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final maxV = _trend.fold<double>(0, (a, b) => b.value > a ? b.value : a);
    final maxY = maxV <= 0 ? 100.0 : maxV * 1.25;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('近 6 个月支出',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 3,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: maxY / 3,
                      getTitlesWidget: (v, m) => Text(
                        v <= 0 ? '' : fmtCompact(v),
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textSub),
                      ),
                    ),
                  ),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= _trend.length) return const SizedBox();
                        final mm = _trend[i].key.split('-')[1];
                        final isCur = i == _trend.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('$mm月',
                              style: TextStyle(
                                fontSize: 10,
                                color: isCur
                                    ? AppColors.primary
                                    : AppColors.textSub,
                                fontWeight: isCur
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              )),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < _trend.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: _trend[i].value,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        color: i == _trend.length - 1
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.32),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Icon(Icons.pie_chart_outline,
              size: 56, color: AppColors.textSub.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('还没有数据',
              style: TextStyle(fontSize: 14, color: AppColors.textSub)),
        ],
      ),
    );
  }
}
