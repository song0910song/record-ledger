import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';
import 'add_txn_page.dart';

/// 账单详情 / 编辑 / 删除
class TxnDetailPage extends StatelessWidget {
  final Txn txn;
  const TxnDetailPage({super.key, required this.txn});

  @override
  Widget build(BuildContext context) {
    final cat = Category(
      id: txn.categoryId,
      name: txn.categoryName ?? '未分类',
      iconCode: txn.categoryIcon ?? Icons.help_outline.codePoint,
      colorValue: txn.categoryColor ?? AppColorsSeed.palette[0],
    );
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('账单详情', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSub),
            onPressed: () async {
              final r = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AddTxnPage(editing: txn)));
              if (r != null && Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.expense),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(cat.icon, size: 24, color: cat.color),
                ),
                const SizedBox(height: 12),
                Text(
                  '${txn.isExpense ? "-" : "+"}${fmtMoney(txn.amount)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: txn.isExpense ? AppColors.textMain : AppColors.income,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(cat.name,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _row('类型', txn.isExpense ? '支出' : '收入'),
                _divider(),
                _row('分类', cat.name),
                _divider(),
                _row('金额', fmtMoney(txn.amount)),
                _divider(),
                _row(
                    '时间',
                    '${txn.date.year}-${_p2(txn.date.month)}-${_p2(txn.date.day)} '
                        '${fmtTime(txn.date)}'),
                _divider(),
                _row('备注', txn.note.isEmpty ? '无' : txn.note),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(k,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 16),
        child: Divider(height: 1, color: AppColors.divider),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这笔记录？', style: TextStyle(fontSize: 16)),
        content: const Text('删除后无法恢复', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Db.deleteTxn(txn.id!);
      if (Navigator.of(context).canPop()) Navigator.pop(context);
    }
  }
}
