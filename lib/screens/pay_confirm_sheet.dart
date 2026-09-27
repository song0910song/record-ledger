import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../services/pay_detect_service.dart';
import '../theme/app_theme.dart';

/// 支付确认弹窗
///
/// 感应到支付通知后弹出，预填金额和分类，用户点一下就入库。
/// 解析失败时也会弹出，但要求用户自己填金额。
class PayConfirmSheet extends StatefulWidget {
  final PendingPay pending;

  const PayConfirmSheet({super.key, required this.pending});

  /// 便捷调用：从任意位置弹出
  static Future<bool?> show(BuildContext context, PendingPay p) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PayConfirmSheet(pending: p),
    );
  }

  @override
  State<PayConfirmSheet> createState() => _PayConfirmSheetState();
}

class _PayConfirmSheetState extends State<PayConfirmSheet> {
  late int _type;
  late TextEditingController _amountCtrl;
  late TextEditingController _noteCtrl;
  Category? _category;
  List<Category> _cats = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.pending;
    _type = p.type;
    _amountCtrl = TextEditingController(
      text: p.parsed && p.amount > 0 ? _trimNum(p.amount) : '',
    );
    _noteCtrl = TextEditingController(text: p.merchant);
    _loadCats();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _trimNum(double v) {
    // 25.50 -> 25.5 ; 100.00 -> 100
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  Future<void> _loadCats() async {
    try {
      final list = await Db.categories(type: _type);
      if (!mounted) return;
      setState(() {
        _cats = list;
        // 优先用推荐分类，没有就用第一个
        final rec = widget.pending.suggestedCategoryId;
        if (rec != null) {
          final hit = list.where((c) => c.id == rec).toList();
          if (hit.isNotEmpty) _category = hit.first;
        }
        _category ??= list.isNotEmpty ? list.first : null;
      });
    } catch (_) {}
  }

  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_amount <= 0) {
      _toast('请输入金额');
      return;
    }
    if (_category == null) {
      _toast('请选择分类');
      return;
    }

    setState(() => _saving = true);
    try {
      HapticFeedback.mediumImpact();
      await Db.addTxn(Txn(
        amount: _amount,
        type: _type,
        categoryId: _category!.id!,
        note: _noteCtrl.text.trim(),
        timestamp: widget.pending.time.millisecondsSinceEpoch,
      ));
      PayDetectService.instance.resolve(widget.pending);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    final accent = p.type == 0 ? AppColors.expense : AppColors.income;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：来源标识 + 标题
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: p.source == '支付宝'
                          ? const Color(0xFF1677FF).withValues(alpha: 0.12)
                          : const Color(0xFF07C160).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        p.source == '支付宝' ? '支' : '微',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.source == '支付宝'
                              ? const Color(0xFF1677FF)
                              : const Color(0xFF07C160),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.parsed
                              ? '检测到一笔${p.type == 0 ? '支出' : '收入'}'
                              : '检测到一笔支付',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtTime(p.time),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSub),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 20, color: AppColors.textSub),
                    onPressed: () {
                      PayDetectService.instance.dismiss(p);
                      Navigator.pop(context, false);
                    },
                  ),
                ],
              ),

              // 解析失败时，把原文亮出来让用户看
              if (!p.parsed) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('通知原文（请自行核对金额）',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.warn,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        p.raw,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.textMain),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 收支切换
              Row(
                children: [
                  _typeBtn('支出', 0, AppColors.expense),
                  const SizedBox(width: 8),
                  _typeBtn('收入', 1, AppColors.income),
                ],
              ),

              const SizedBox(height: 14),

              // 金额输入
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('¥',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      autofocus: !p.parsed,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: AppColors.divider),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (p.parsed && p.amount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('自动识别',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),

              const Divider(height: 20, color: AppColors.divider),

              // 备注
              Row(
                children: [
                  const Icon(Icons.edit_note,
                      size: 16, color: AppColors.textSub),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '备注（可选）',
                        hintStyle:
                            TextStyle(fontSize: 13, color: AppColors.textSub),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // 分类选择
              const Text('分类',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub)),
              const SizedBox(height: 8),
              SizedBox(
                height: 74,
                child: _cats.isEmpty
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cats.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final c = _cats[i];
                          final on = _category?.id == c.id;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _category = c);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color:
                                        on ? c.color : c.color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(13),
                                    border: on
                                        ? Border.all(color: c.color, width: 2)
                                        : null,
                                  ),
                                  child: Icon(c.icon,
                                      size: 20,
                                      color: on ? Colors.white : c.color),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  c.name,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: on
                                        ? AppColors.textMain
                                        : AppColors.textSub,
                                    fontWeight: on
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 18),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () {
                          PayDetectService.instance.dismiss(p);
                          Navigator.pop(context, false);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.divider),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('略过',
                            style: TextStyle(color: AppColors.textSub)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _category?.color ?? AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('确认记账',
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

  Widget _typeBtn(String label, int v, Color c) {
    final on = _type == v;
    return GestureDetector(
      onTap: () {
        if (_type == v) return;
        setState(() {
          _type = v;
          _category = null;
        });
        _loadCats();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: on ? c : AppColors.bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
