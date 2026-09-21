import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'data_bus.dart';

/// 本地数据库 —— 纯离线，数据只存本机
class Db {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'ledger.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE category(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon INTEGER NOT NULL,
        color INTEGER NOT NULL,
        type INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE txn(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        note TEXT DEFAULT '',
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE budget(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        month TEXT NOT NULL,
        UNIQUE(category_id, month)
      )
    ''');
    await db.execute('CREATE INDEX idx_txn_ts ON txn(timestamp)');
    await _createTotalBudgetTable(db);
    await _seedCategories(db);
  }

  /// 版本迁移。
  ///
  /// v2 新增「总预算」表 —— 老用户升级时补建，不影响已有账单和分类预算。
  static Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      await _createTotalBudgetTable(db);
    }
  }

  /// 总预算表。
  ///
  /// 为什么单开一张表而不是塞进 budget 表？
  /// budget 表的语义是「某个分类的额度」，主键和外键都是 category_id。
  /// 总预算不属于任何分类，混进去要用 -1 之类的魔法值，查询和迁移都容易出错。
  static Future<void> _createTotalBudgetTable(Database db) async {
    await db.execute('''
      CREATE TABLE total_budget(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        month TEXT NOT NULL UNIQUE
      )
    ''');
  }

  /// 预置常用分类
  static Future<void> _seedCategories(Database db) async {
    final c = AppColorsSeed.palette;
    final expenses = <List<dynamic>>[
      ['餐饮', Icons.restaurant.codePoint, c[3], 0],
      ['交通', Icons.directions_bus.codePoint, c[1], 1],
      ['购物', Icons.shopping_bag.codePoint, c[2], 2],
      ['居住', Icons.home.codePoint, c[0], 3],
      ['娱乐', Icons.sports_esports.codePoint, c[4], 4],
      ['医疗', Icons.local_hospital.codePoint, c[7], 5],
      ['通讯', Icons.smartphone.codePoint, c[5], 6],
      ['人情', Icons.card_giftcard.codePoint, c[6], 7],
      ['学习', Icons.menu_book.codePoint, c[1], 8],
      ['其他', Icons.more_horiz.codePoint, c[1], 9],
    ];
    for (final e in expenses) {
      await db.insert('category', {
        'name': e[0], 'icon': e[1], 'color': e[2], 'type': 0, 'sort': e[3],
      });
    }
    final incomes = <List<dynamic>>[
      ['工资', Icons.account_balance_wallet.codePoint, c[0], 0],
      ['奖金', Icons.emoji_events.codePoint, c[2], 1],
      ['兼职', Icons.work_outline.codePoint, c[1], 2],
      ['理财', Icons.trending_up.codePoint, c[5], 3],
      ['红包', Icons.redeem.codePoint, c[3], 4],
      ['报销', Icons.receipt_long.codePoint, c[6], 5],
      ['其他', Icons.more_horiz.codePoint, c[1], 6],
    ];
    for (final e in incomes) {
      await db.insert('category', {
        'name': e[0], 'icon': e[1], 'color': e[2], 'type': 1, 'sort': e[3],
      });
    }
  }

  // ---------- 分类 ----------
  static Future<List<Category>> categories({int? type}) async {
    final db = await instance;
    final rows = await db.query(
      'category',
      where: type == null ? null : 'type = ?',
      whereArgs: type == null ? null : [type],
      orderBy: 'sort ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  static Future<int> addCategory(Category c) async {
    final db = await instance;
    final id = await db.insert('category', c.toMap());
    DataBus.notify();
    return id;
  }

  static Future<void> deleteCategory(int id) async {
    final db = await instance;
    await db.delete('category', where: 'id = ?', whereArgs: [id]);
    DataBus.notify();
  }

  // ---------- 账单 ----------
  static Future<int> addTxn(Txn t) async {
    final db = await instance;
    final id = await db.insert('txn', t.toMap());
    DataBus.notify();
    return id;
  }

  static Future<void> updateTxn(Txn t) async {
    final db = await instance;
    await db.update('txn', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    DataBus.notify();
  }

  static Future<void> deleteTxn(int id) async {
    final db = await instance;
    await db.delete('txn', where: 'id = ?', whereArgs: [id]);
    DataBus.notify();
  }

  static const String _txnJoin = '''
    SELECT t.*, c.name AS category_name, c.icon AS category_icon, c.color AS category_color
    FROM txn t LEFT JOIN category c ON t.category_id = c.id
  ''';

  /// 按时间倒序取账单，可限定月份
  static Future<List<Txn>> txns({String? month, int limit = 500}) async {
    final db = await instance;
    String sql = _txnJoin;
    List<dynamic> args = [];
    if (month != null) {
      final range = monthRange(month);
      sql += ' WHERE t.timestamp >= ? AND t.timestamp < ?';
      args = [range[0], range[1]];
    }
    sql += ' ORDER BY t.timestamp DESC LIMIT ?';
    args.add(limit);
    final rows = await db.rawQuery(sql, args);
    return rows.map(Txn.fromMap).toList();
  }

  /// 某分类在某月的已花费
  static Future<double> spentOf(int categoryId, String month) async {
    final db = await instance;
    final range = monthRange(month);
    final r = await db.rawQuery(
      'SELECT SUM(amount) AS s FROM txn WHERE type = 0 AND category_id = ? AND timestamp >= ? AND timestamp < ?',
      [categoryId, range[0], range[1]],
    );
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// 某月支出总计 / 收入总计
  static Future<List<double>> monthSummary(String month) async {
    final db = await instance;
    final range = monthRange(month);
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 0 THEN amount ELSE 0 END), 0) AS expense,
        COALESCE(SUM(CASE WHEN type = 1 THEN amount ELSE 0 END), 0) AS income
      FROM txn WHERE timestamp >= ? AND timestamp < ?
    ''', [range[0], range[1]]);
    return [
      (r.first['expense'] as num).toDouble(),
      (r.first['income'] as num).toDouble(),
    ];
  }

  /// 某月按分类聚合（支出）
  static Future<Map<int, double>> categoryTotals(String month) async {
    final db = await instance;
    final range = monthRange(month);
    final rows = await db.rawQuery('''
      SELECT category_id, SUM(amount) AS s FROM txn
      WHERE type = 0 AND timestamp >= ? AND timestamp < ?
      GROUP BY category_id
    ''', [range[0], range[1]]);
    final map = <int, double>{};
    for (final r in rows) {
      map[r['category_id'] as int] = (r['s'] as num).toDouble();
    }
    return map;
  }

  /// 近 N 个月支出趋势
  static Future<List<MapEntry<String, double>>> monthlyTrend(int n) async {
    final now = DateTime.now();
    final out = <MapEntry<String, double>>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final m = formatMonth(d);
      final s = await monthSummary(m);
      out.add(MapEntry(m, s[0]));
    }
    return out;
  }

  // ---------- 预算 ----------
  static Future<void> setBudget(int categoryId, String month, double amount) async {
    final db = await instance;
    if (amount <= 0) {
      await db.delete('budget',
          where: 'category_id = ? AND month = ?', whereArgs: [categoryId, month]);
      DataBus.notify();
      return;
    }
    await db.insert(
      'budget',
      {'category_id': categoryId, 'amount': amount, 'month': month},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DataBus.notify();
  }

  static Future<Map<int, double>> budgetsOf(String month) async {
    final db = await instance;
    final rows = await db.query('budget', where: 'month = ?', whereArgs: [month]);
    final map = <int, double>{};
    for (final r in rows) {
      map[r['category_id'] as int] = (r['amount'] as num).toDouble();
    }
    return map;
  }

  // ---------- 总预算 ----------

  /// 设置某月总预算。amount <= 0 表示清除该月设置。
  static Future<void> setTotalBudget(String month, double amount) async {
    final db = await instance;
    if (amount <= 0) {
      await db.delete('total_budget', where: 'month = ?', whereArgs: [month]);
      DataBus.notify();
      return;
    }
    await db.insert(
      'total_budget',
      {'amount': amount, 'month': month},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DataBus.notify();
  }

  /// 精确读取某月的总预算（不做沿用）。没有则返回 0。
  static Future<double> totalBudgetExact(String month) async {
    final db = await instance;
    final rows = await db.query(
      'total_budget',
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['amount'] as num).toDouble();
  }

  /// 读取某月生效的总预算 —— 「下月自动沿用」的语义在这里实现。
  ///
  /// 规则：本月没单独设 → 沿用**之前最近一次**设置的值。
  /// 只往前找（不看未来），否则给 6 月设了额度会莫名其妙影响 3 月。
  ///
  /// 返回 [金额, 实际来源月份]。来源月份用于在界面上提示
  /// 「沿用自 2026年8月」，避免用户困惑数字从哪来的。
  static Future<List<dynamic>> totalBudgetOf(String month) async {
    final db = await instance;
    final rows = await db.rawQuery(
      "SELECT amount, month FROM total_budget WHERE month <= ? ORDER BY month DESC LIMIT 1",
      [month],
    );
    if (rows.isEmpty) return [0.0, null];
    return [
      (rows.first['amount'] as num).toDouble(),
      rows.first['month'] as String?,
    ];
  }

  /// 该月是否是「自己设的」（而非沿用）
  static Future<bool> hasOwnTotalBudget(String month) async {
    final db = await instance;
    final rows = await db.query(
      'total_budget',
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ---------- 导出 ----------
  static Future<File> exportCsv() async {
    final list = await txns(limit: 100000);
    final buf = StringBuffer('\uFEFF日期,类型,分类,金额,备注\n');
    for (final t in list) {
      final d = t.date;
      final ds =
          '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
      final note = t.note.replaceAll('"', '""');
      buf.writeln('$ds,${t.isExpense ? "支出" : "收入"},${t.categoryName ?? ""},${t.amount},"$note"');
    }
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'ledger_export_${DateTime.now().millisecondsSinceEpoch}.csv'));
    await f.writeAsString(buf.toString());
    return f;
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');

  /// 全量导出为 JSON 字符串（用于备份分享）
  static Future<String> exportJson() async {
    final list = await txns(limit: 100000);
    final cats = await categories();
    final buf = StringBuffer('{"categories":[');
    for (int i = 0; i < cats.length; i++) {
      final c = cats[i];
      buf.write('{"name":"${c.name}","icon":${c.iconCode},"color":${c.colorValue},"type":${c.type}}');
      if (i != cats.length - 1) buf.write(',');
    }
    buf.write('],"txns":[');
    for (int i = 0; i < list.length; i++) {
      final t = list[i];
      final note = t.note.replaceAll('"', r'\"');
      buf.write('{"amount":${t.amount},"type":${t.type},"category":"${t.categoryName ?? ""}","note":"$note","timestamp":${t.timestamp}}');
      if (i != list.length - 1) buf.write(',');
    }
    buf.write(']}');
    return buf.toString();
  }

  static Future<void> clearAll() async {
    final db = await instance;
    await db.delete('txn');
    await db.delete('budget');
    await db.delete('total_budget');
    DataBus.notify();
  }

  static Future<int> txnCount() async {
    final db = await instance;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM txn');
    return (r.first['c'] as int?) ?? 0;
  }
}

/// 避免和 theme 循环依赖，这里冗余一份色盘
class AppColorsSeed {
  static const List<int> palette = [
    0xFF00B894, 0xFF6C8AE4, 0xFFF5A623, 0xFFE8686B,
    0xFF9B6CE4, 0xFF4BC0C0, 0xFFE48A6C, 0xFF5BA8E4,
  ];
}

/// 月份工具
String formatMonth(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 返回 [起始ts, 结束ts)
List<int> monthRange(String month) {
  final parts = month.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final start = DateTime(y, m, 1);
  final end = DateTime(y, m + 1, 1);
  return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
}

/// 一天的区间
List<int> dayRange(DateTime d) {
  final start = DateTime(d.year, d.month, d.day);
  final end = start.add(const Duration(days: 1));
  return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
}
