import 'package:flutter_test/flutter_test.dart';

/// 总预算的「沿用」规则测试
///
/// 这里不依赖 sqflite（测试环境没有原生 sqlite），
/// 而是把「找最近一次设置」的规则单独抽出来验证 —— 规则本身是纯逻辑。
///
/// 规则：本月没单独设 → 沿用**之前最近一次**设置的值；只往前找，不看未来。
List<dynamic> resolveTotalBudget(Map<String, double> stored, String month) {
  final keys = stored.keys.where((k) => k.compareTo(month) <= 0).toList()
    ..sort((a, b) => b.compareTo(a));
  if (keys.isEmpty) return [0.0, null];
  return [stored[keys.first]!, keys.first];
}

void main() {
  group('总预算沿用规则', () {
    test('当月有设置 —— 用当月的，来源就是当月', () {
      final r = resolveTotalBudget({'2026-09': 7000}, '2026-09');
      expect(r[0], 7000.0);
      expect(r[1], '2026-09');
    });

    test('当月没设 —— 沿用上个月', () {
      final r = resolveTotalBudget({'2026-08': 6000}, '2026-09');
      expect(r[0], 6000.0);
      expect(r[1], '2026-08');
      expect(r[1], isNot('2026-09'), reason: '来源月份应不同于当前月，界面才好提示"沿用自…"');
    });

    test('跨多个月 —— 沿用最近的那次，不是最早的', () {
      final r = resolveTotalBudget({
        '2026-03': 3000,
        '2026-06': 5000,
        '2026-07': 5500,
      }, '2026-09');
      expect(r[0], 5500.0);
      expect(r[1], '2026-07');
    });

    test('当月有设置时不看历史值', () {
      final r = resolveTotalBudget({
        '2026-06': 5000,
        '2026-09': 8000,
      }, '2026-09');
      expect(r[0], 8000.0);
      expect(r[1], '2026-09');
    });

    test('只看过去 —— 未来月份的设置不影响当前月', () {
      // 给 12 月设了 9999，查 9 月时不应拿到它
      final r = resolveTotalBudget({
        '2026-09': 7000,
        '2026-12': 9999,
      }, '2026-09');
      expect(r[0], 7000.0, reason: '12 月的值不能穿越回来影响 9 月');
      expect(r[1], '2026-09');
    });

    test('只有未来月份的设置 —— 当前月视为未设置', () {
      final r = resolveTotalBudget({'2026-12': 9999}, '2026-09');
      expect(r[0], 0.0);
      expect(r[1], isNull);
    });

    test('完全没设过 —— 返回 0 且无来源', () {
      final r = resolveTotalBudget({}, '2026-09');
      expect(r[0], 0.0);
      expect(r[1], isNull);
    });

    test('跨年沿用 —— 去年 12 月的值能被今年 1 月沿用', () {
      final r = resolveTotalBudget({'2025-12': 4000}, '2026-01');
      expect(r[0], 4000.0);
      expect(r[1], '2025-12');
    });

    test('字符串比较在 yyyy-MM 格式下等价于时间先后', () {
      // 这是实现依赖的前提，月份补零后才能这么比
      expect('2026-09'.compareTo('2026-10') < 0, isTrue);
      expect('2026-12'.compareTo('2027-01') < 0, isTrue);
      expect('2026-01'.compareTo('2025-12') > 0, isTrue);
    });
  });

  group('预算进度口径', () {
    /// 总预算进度用「当月全部支出」，不是「设了额度的分类支出」
    double progress(double totalBudget, double monthExpense) {
      if (totalBudget <= 0) return 0;
      return (monthExpense / totalBudget).clamp(0.0, 1.0);
    }

    test('未设总预算 —— 进度为 0，界面不显示进度条', () {
      expect(progress(0, 5000), 0);
    });

    test('正常范围内按比例', () {
      expect(progress(7000, 3500), closeTo(0.5, 1e-9));
    });

    test('超支时钳制在 1.0，但超支金额由外部单独计算', () {
      expect(progress(7000, 7700), 1.0);
    });

    test('80% 是"接近上限"的阈值', () {
      expect(progress(7000, 5600), closeTo(0.8, 1e-9));
      expect(progress(7000, 5599) >= 0.8, isFalse);
    });
  });

  group('分类额度分配提示', () {
    /// 分类额度之和与总预算的关系 —— 只提示不阻止
    String allocationHint(double sum, double total) {
      if (total <= 0) return '';
      if (sum > total) return '分类额度已超出总预算 ${(sum - total).toStringAsFixed(0)}';
      return '';
    }

    test('未设总预算时不提示', () {
      expect(allocationHint(5000, 0), '');
    });

    test('分类额度之和小于总预算 —— 不提示', () {
      expect(allocationHint(3000, 7000), '');
    });

    test('分类额度之和等于总预算 —— 不提示', () {
      expect(allocationHint(7000, 7000), '');
    });

    test('分类额度之和超出总预算 —— 提示但不阻止保存', () {
      expect(allocationHint(8200, 7000), contains('超出'));
    });
  });
}
