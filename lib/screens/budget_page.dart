import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/data_bus.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 预算页 —— 事前规划 + 事中监控
///
/// 两个独立的预算维度：
///   · 总预算 —— 自己设一个数，管住整体开销。点击卡片编辑。
///   · 分类预算 —— 按需给分类设额度，只显示设过的，不铺满屏幕。
///
/// 两者互不约束：分类额度之和超过总预算时会给出提示，但不阻止保存。
/// 理由 —— 分类额度是"意图分配"，总预算是"实际闸门"，
/// 月初拍脑袋分配的数字经常需要调整，硬拦着只会让人放弃设分类预算。
class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => BudgetPageState();
}

class BudgetPageState extends State<BudgetPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  /// 当月全部支出分类的视图（含未设额度的，用于选择器）
  List<BudgetView> _allViews = [];

  /// 总预算金额
  double _totalBudget = 0;

  /// 总预算的来源月份 —— 为 null 表示从未设置；与当前月份不同表示「沿用」
  String? _totalBudgetFrom;

  /// 当月支出总额（含所有分类，不只是设了额度的）
  double _monthSpent = 0;

  bool _loading = true;

  /// 今日还可花
  double _todaySpent = 0;
  double _todayRemain = 0;
  bool _todayReady = false;

  @override
  void initState() {
    super.initState();
    load();
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
      final budgets = await Db.budgetsOf(m);
      final spent = await Db.categoryTotals(m);
      final total = await Db.totalBudgetOf(m);
      final summary = await Db.monthSummary(m);

      final list = cats
          .map((c) => BudgetView(
                category: c,
                budget: budgets[c.id] ?? 0,
                spent: spent[c.id] ?? 0,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _allViews = list;
        _totalBudget = (total[0] as num).toDouble();
        _totalBudgetFrom = total[1] as String?;
        _monthSpent = summary[0];
        _loading = false;
      });
      await _calcToday();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _calcToday() async {
    try {
      final m = formatMonth(DateTime.now());
      final list = await Db.txns(month: m, limit: 500);
      final now = DateTime.now();
      final spent = list
          .where((t) =>
              t.isExpense &&
              t.date.year == now.year &&
              t.date.month == now.month &&
              t.date.day == now.day)
          .fold<double>(0, (a, b) => a + b.amount);
      if (!mounted) return;
      setState(() {
        _todaySpent = spent;
        _todayRemain = spent < _todayAllowance ? _todayAllowance - spent : 0;
        _todayReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _todayReady = true);
    }
  }

  /// 每日可用额度 = 剩余预算 / 剩余天数
  double get _todayAllowance {
    if (_totalBudget <= 0) return 0;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day + 1;
    final remain = _totalBudget - _monthSpent;
    if (remain <= 0) return 0;
    return remain / (daysLeft <= 0 ? 1 : daysLeft);
  }

  /// 已设额度的分类 —— 列表里只显示这些
  List<BudgetView> get _activeViews =>
      _allViews.where((v) => v.budget > 0).toList();

  /// 还没设额度的分类 —— 供「添加分类预算」选择
  List<BudgetView> get _availableViews =>
      _allViews.where((v) => v.budget <= 0).toList();

  /// 分类额度合计
  double get _sumOfCategoryBudgets =>
      _allViews.fold(0.0, (a, b) => a + b.budget);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _monthBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      children: [
                        _overallCard(),
                        const SizedBox(height: 18),
                        _categoryHeader(),
                        const SizedBox(height: 8),
                        if (_activeViews.isEmpty)
                          _emptyCategories()
                        else ...[
                          ..._activeViews.map(_budgetTile),
                          const SizedBox(height: 4),
                          _addCategoryButton(),
                        ],
                        const SizedBox(height: 16),
                        _tip(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          const Text('预算',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          InkWell(
            onTap: () => _shift(-1),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left, size: 20, color: AppColors.textSub),
            ),
          ),
          Text('${_month.year}年${_month.month}月',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          InkWell(
            onTap: _isCurrentMonth ? null : () => _shift(1),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_right,
                  size: 20,
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

  void _shift(int d) {
    setState(() {
      _month = DateTime(_month.year, _month.month + d, 1);
      _loading = true;
    });
    load();
  }

  // ---------------- 总预算卡片 ----------------

  Widget _overallCard() {
    final hasBudget = _totalBudget > 0;
    final over = hasBudget && _monthSpent > _totalBudget;
    final ratio =
        hasBudget ? (_monthSpent / _totalBudget).clamp(0.0, 1.0) : 0.0;
    final color = over
        ? AppColors.danger
        : (ratio >= 0.8 ? AppColors.warn : AppColors.primary);

    // 沿用的月份和当前月不同 —— 提示数字来源
    final isInherited = hasBudget &&
        _totalBudgetFrom != null &&
        _totalBudgetFrom != formatMonth(_month);

    return GestureDetector(
      onTap: _editTotalBudget,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasBudget
                ? [color.withOpacity(0.9), color.withOpacity(0.68)]
                : [AppColors.textSub, AppColors.textSub.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('本月总预算',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(width: 6),
                if (hasBudget)
                  const Icon(Icons.edit_outlined,
                      size: 12, color: Colors.white54),
                const Spacer(),
                if (hasBudget)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      over ? '已超支' : (ratio >= 0.8 ? '接近上限' : '正常'),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(hasBudget ? fmtMoney(_totalBudget) : '点击设置',
                    style: TextStyle(
                        fontSize: hasBudget ? 30 : 24,
                        fontWeight: FontWeight.w700,
                        color: hasBudget ? Colors.white : Colors.white70,
                        letterSpacing: -0.5)),
                if (!hasBudget) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.add_circle_outline,
                      size: 18, color: Colors.white70),
                ],
              ],
            ),
            if (isInherited) ...[
              const SizedBox(height: 4),
              Text('沿用自 ${_prettyMonth(_totalBudgetFrom!)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
            ],
            const SizedBox(height: 14),
            if (hasBudget) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ovStat('已支出', fmtCompact(_monthSpent)),
                  _ovStat(
                      '剩余',
                      over
                          ? '-${fmtCompact(_monthSpent - _totalBudget)}'
                          : fmtCompact(_totalBudget - _monthSpent)),
                  _ovStat('进度', '${(ratio * 100).toStringAsFixed(0)}%'),
                ],
              ),
              if (_isCurrentMonth && _todayReady) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.today, size: 15, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('今天还可花',
                          style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const Spacer(),
                      Text(fmtMoney(_todayRemain),
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(width: 8),
                      Text('已花 ${fmtCompact(_todaySpent)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white60)),
                    ],
                  ),
                ),
              ],
            ] else
              const Text('设一个本月能花的总额，打开 App 就知道还剩多少',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  String _prettyMonth(String ym) {
    final p = ym.split('-');
    if (p.length != 2) return ym;
    return '${p[0]}年${int.parse(p[1])}月';
  }

  Widget _ovStat(String label, String v) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white60)),
          const SizedBox(height: 2),
          Text(v,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  // ---------------- 分类预算 ----------------

  Widget _categoryHeader() {
    final sum = _sumOfCategoryBudgets;
    final hasTotal = _totalBudget > 0;
    final exceed = hasTotal && sum > _totalBudget;

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('分类预算',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          if (_activeViews.isNotEmpty)
            Expanded(
              child: Text(
                '已分配 ${fmtCompact(sum)}'
                '${hasTotal ? ' / ${fmtCompact(_totalBudget)}' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: exceed ? AppColors.warn : AppColors.textSub),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }

  /// 一个分类额度都没设时的引导
  Widget _emptyCategories() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.donut_large_outlined,
              size: 34, color: AppColors.textSub),
          const SizedBox(height: 10),
          const Text('还没有分类预算',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            '给容易超支的分类单独设个额度\n比如「餐饮 2000」「购物 800」',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5, color: AppColors.textSub, height: 1.6),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _pickCategoryToAdd,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('添加分类预算'),
              style: ElevatedButton.styleFrom(
                primary: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                textStyle:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addCategoryButton() {
    final left = _availableViews.length;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: left == 0 ? null : _pickCategoryToAdd,
        icon: const Icon(Icons.add, size: 17),
        label: Text(left == 0 ? '所有分类都已设置额度' : '添加分类预算'),
        style: OutlinedButton.styleFrom(
          primary: AppColors.primary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _budgetTile(BudgetView v) {
    final color =
        v.over ? AppColors.danger : (v.near ? AppColors.warn : AppColors.primary);
    final ratio = v.ratio.clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => _editCategoryBudget(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: v.over
              ? Border.all(color: AppColors.danger.withOpacity(0.35), width: 1)
              : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: v.category.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(v.category.icon, size: 17, color: v.category.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v.category.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text(fmtCompact(v.spent),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: v.over ? AppColors.danger : AppColors.textMain)),
                Text(' / ${fmtCompact(v.budget)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppColors.textSub),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  v.over
                      ? Icons.error_outline
                      : (v.near
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline),
                  size: 12,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  v.over
                      ? '超支 ${fmtMoney(v.spent - v.budget)}'
                      : '还剩 ${fmtMoney(v.remain)}',
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text('${(v.ratio * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 编辑交互 ----------------

  /// 添加分类预算 —— 先选分类，再输金额
  Future<void> _pickCategoryToAdd() async {
    if (_availableViews.isEmpty) return;

    final picked = await showModalBottomSheet<BudgetView>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: const [
                  Text('选择要设额度的分类',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Spacer(),
                  Text('设过的不会再出现',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSub)),
                ],
              ),
            ),            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _availableViews.length,
                itemBuilder: (_, i) {
                  final v = _availableViews[i];
                  return ListTile(
                    onTap: () => Navigator.pop(ctx, v),
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: v.category.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(v.category.icon,
                          size: 18, color: v.category.color),
                    ),
                    title: Text(v.category.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: v.spent > 0
                        ? Text('本月已花 ${fmtMoney(v.spent)}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSub))
                        : null,
                    trailing: const Icon(Icons.chevron_right,
                        size: 17, color: AppColors.textSub),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      await _editCategoryBudget(picked);
    }
  }

  /// 编辑总预算
  Future<void> _editTotalBudget() async {
    final own = await Db.hasOwnTotalBudget(formatMonth(_month));
    final ctrl = TextEditingController(
        text: _totalBudget > 0 ? _totalBudget.toStringAsFixed(0) : '');

    if (!mounted) return;
    final r = await _amountSheet(
      title: '本月总预算',
      subtitle: '${_month.year}年${_month.month}月'
          '${(!own && _totalBudget > 0 && _totalBudgetFrom != null) ? ' · 当前沿用自 ${_prettyMonth(_totalBudgetFrom!)}' : ''}',
      hint: '比如 7000',
      helper: '留空或填 0 表示不设总预算',
      controller: ctrl,
      icon: Icons.account_balance_wallet_outlined,
      iconColor: AppColors.primary,
      canClear: own,
    );
    if (r == true) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0;
      await Db.setTotalBudget(formatMonth(_month), val);
      if (mounted) load();
    }
  }

  /// 编辑分类预算
  Future<void> _editCategoryBudget(BudgetView v) async {
    final ctrl = TextEditingController(
        text: v.budget > 0 ? v.budget.toStringAsFixed(0) : '');

    final r = await _amountSheet(
      title: '${v.category.name} · 月度预算',
      subtitle: '${_month.year}年${_month.month}月'
          '${v.spent > 0 ? ' · 本月已花 ${fmtMoney(v.spent)}' : ''}',
      hint: '比如 2000',
      helper: '留空或填 0 表示不再限制这个分类',
      controller: ctrl,
      icon: v.category.icon,
      iconColor: v.category.color,
      canClear: v.budget > 0,
    );
    if (r == true) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0;
      await Db.setBudget(v.category.id!, formatMonth(_month), val);
      if (mounted) load();
    }
  }

  /// 复用的金额输入弹窗
  Future<bool?> _amountSheet({
    required String title,
    required String subtitle,
    required String hint,
    required String helper,
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required bool canClear,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSub)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '¥ ',
                  prefixStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain),
                  hintText: hint,
                  hintStyle: const TextStyle(color: AppColors.textSub),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              Text(helper,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSub)),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (canClear)
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('清除',
                              style: TextStyle(color: AppColors.textSub)),
                        ),
                      ),
                    ),
                  if (canClear) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          primary: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('保存',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('怎么用',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 4),
                const Text(
                  '总预算管整体，分类预算管细节，两者独立。\n'
                  '分类预算只用给你真正想管的分类设 —— 比如「餐饮」容易超，「居住」是固定支出就不用管。\n'
                  '预设的额度下个月会自动沿用，不用重复设置。',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textMain, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
