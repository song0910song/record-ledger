import 'package:flutter/material.dart';

/// 分类
class Category {
  final int? id;
  final String name;
  final int iconCode; // IconData.codePoint
  final int colorValue;
  final int type; // 0=支出 1=收入
  final int sort;

  Category({
    this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    this.type = 0,
    this.sort = 0,
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');
  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'icon': iconCode,
        'color': colorValue,
        'type': type,
        'sort': sort,
      };

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        iconCode: m['icon'] as int,
        colorValue: m['color'] as int,
        type: m['type'] as int? ?? 0,
        sort: m['sort'] as int? ?? 0,
      );
}

/// 一笔账单
class Txn {
  final int? id;
  final double amount; // 金额（正数）
  final int type; // 0=支出 1=收入
  final int categoryId;
  final String note;
  final int timestamp; // 毫秒时间戳
  final String? categoryName; // 联表查询带出
  final int? categoryIcon;
  final int? categoryColor;

  Txn({
    this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    this.note = '',
    required this.timestamp,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
  });

  bool get isExpense => type == 0;
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(timestamp);

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'type': type,
        'category_id': categoryId,
        'note': note,
        'timestamp': timestamp,
      };

  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: m['id'] as int?,
        amount: (m['amount'] as num).toDouble(),
        type: m['type'] as int,
        categoryId: m['category_id'] as int,
        note: m['note'] as String? ?? '',
        timestamp: m['timestamp'] as int,
        categoryName: m['category_name'] as String?,
        categoryIcon: m['category_icon'] as int?,
        categoryColor: m['category_color'] as int?,
      );
}

/// 分类预算
class Budget {
  final int? id;
  final int categoryId;
  final double amount; // 月度额度
  final String month; // yyyy-MM

  Budget({this.id, required this.categoryId, required this.amount, required this.month});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category_id': categoryId,
        'amount': amount,
        'month': month,
      };

  factory Budget.fromMap(Map<String, dynamic> m) => Budget(
        id: m['id'] as int?,
        categoryId: m['category_id'] as int,
        amount: (m['amount'] as num).toDouble(),
        month: m['month'] as String,
      );
}

/// 分类 + 已花费，用于预算页展示
class BudgetView {
  final Category category;
  final double budget;
  final double spent;
  BudgetView({required this.category, required this.budget, required this.spent});

  double get ratio => budget <= 0 ? 0 : spent / budget;
  double get remain => budget - spent;
  bool get over => budget > 0 && spent > budget;
  bool get near => budget > 0 && ratio >= 0.8 && !over;
}
