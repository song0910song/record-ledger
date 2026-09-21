import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/data_bus.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';
import 'txn_detail_page.dart';

/// 账单页：顶部月度概览 + 按日分组的流水
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Txn> _list = [];
  double _expense = 0;
  double _income = 0;

  /// 总预算（独立存储，非分类额度之和）
  double _totalBudget = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
    // 订阅数据变更：记账、改预算、删账单后自动重新加载
    DataBus.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  /// 数据有变动 —— 重新拉一次
  void _onDataChanged() {
    if (!mounted) return;
    load();
  }

  Future<void> load() async {
    final m = formatMonth(_month);
    try {
      final list = await Db.txns(month: m);
      final sum = await Db.monthSummary(m);
      final total = await Db.totalBudgetOf(m);
      if (!mounted) return;
      setState(() {
        _list = list;
        _expense = sum[0];
        _income = sum[1];
        _totalBudget = (total[0] as num).toDouble();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _loading = true;
    });
    load();
  }

  /// 整体预算进度 —— 总预算 vs 当月全部支出。
  ///
  /// 口径说明：总预算是独立的，所以这里用 _expense（当月所有支出），
  /// 而不是只统计"设了额度的分类"。否则给「餐饮」设了额度后，
  /// 买衣服花的钱不计入进度，进度条会一直显得很宽松，失去警示意义。
  double get _totalSpentInBudget => _expense;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: load,
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _overviewCard()),
            if (_totalBudget > 0) SliverToBoxAdapter(child: _budgetBar()),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_list.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty())
            else
              ..._buildGroups(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _shift(-1),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.chevron_left, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('${_month.year}年${_month.month}月',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          GestureDetector(
            onTap: () {
              final now = DateTime.now();
              if (_month.year == now.year && _month.month == now.month) return;
              _shift(1);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.chevron_right,
                  color: _isCurrentMonth ? AppColors.divider : AppColors.textSub),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isCurrentMonth {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  Widget _overviewCard() {
    final balance = _income - _expense;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text('本月结余', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          const SizedBox(height: 6),
          Text(
            fmtMoney(balance),
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: balance >= 0 ? AppColors.textMain : AppColors.danger,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _miniStat('支出', _expense, AppColors.expense),
              Container(width: 1, height: 30, color: AppColors.divider),
              _miniStat('收入', _income, AppColors.income),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double v, Color c) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 4),
          Text(fmtCompact(v),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }

  /// 预算进度条 —— 记完能立刻看到"还剩多少"
  Widget _budgetBar() {
    final budget = _totalBudget;
    final spent = _totalSpentInBudget;
    final ratio = (spent / budget).clamp(0.0, 1.0);
    final over = spent > budget;
    final near = !over && spent / budget >= 0.8;
    final color = over ? AppColors.danger : (near ? AppColors.warn : AppColors.primary);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(over ? Icons.error_outline : Icons.savings_outlined,
                  size: 16, color: color),
              const SizedBox(width: 6),
              Text('预算进度',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color)),
              const Spacer(),
              Text(
                over
                    ? '超支 ${fmtMoney(spent - budget)}'
                    : '还剩 ${fmtMoney(budget - spent)}',
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text('已花 ${fmtCompact(spent)} / ${fmtCompact(budget)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        ],
      ),
    );
  }

  List<Widget> _buildGroups() {
    // 按日期分组
    final groups = <String, List<Txn>>{};
    for (final t in _list) {
      final d = t.date;
      final key = '${d.year}-${d.month}-${d.day}';
      groups.putIfAbsent(key, () => []).add(t);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return keys.map((k) {
      final items = groups[k]!;
      final day = items.first.date;
      final dayExpense = items
          .where((e) => e.isExpense)
          .fold<double>(0, (a, b) => a + b.amount);
      final dayIncome = items
          .where((e) => !e.isExpense)
          .fold<double>(0, (a, b) => a + b.amount);

      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Text(fmtDay(day),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain)),
                  const SizedBox(width: 6),
                  Text(weekdayCn(day),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                  const Spacer(),
                  if (dayExpense > 0)
                    Text('支出 ${fmtCompact(dayExpense)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                  if (dayExpense > 0 && dayIncome > 0)
                    const Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                  if (dayIncome > 0)
                    Text('收入 ${fmtCompact(dayIncome)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _row(items[i]),
                    if (i != items.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 58),
                        child: Divider(height: 1, color: AppColors.divider),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _row(Txn t) {
    final cat = Category(
      id: t.categoryId,
      name: t.categoryName ?? '未分类',
      iconCode: t.categoryIcon ?? Icons.help_outline.codePoint,
      colorValue: t.categoryColor ?? AppColorsSeed.palette[0],
    );
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TxnDetailPage(txn: t)),
        );
        load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cat.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(cat.icon, size: 18, color: cat.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (t.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${t.isExpense ? "-" : "+"}${fmtMoney(t.amount, withSymbol: false)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.isExpense ? AppColors.textMain : AppColors.income,
                  ),
                ),
                const SizedBox(height: 2),
                Text(fmtTime(t.date),
                    style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: AppColors.textSub.withOpacity(0.4)),
          const SizedBox(height: 12),
          const Text('这个月还没有记录',
              style: TextStyle(fontSize: 14, color: AppColors.textSub)),
          const SizedBox(height: 4),
          const Text('点下面的加号记第一笔',
              style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        ],
      ),
    );
  }
}
