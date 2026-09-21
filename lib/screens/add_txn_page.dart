import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 记一笔 —— 核心交互：输金额 → 点分类 → 完成
class AddTxnPage extends StatefulWidget {
  final Txn? editing;
  const AddTxnPage({super.key, this.editing});

  @override
  State<AddTxnPage> createState() => _AddTxnPageState();
}

class _AddTxnPageState extends State<AddTxnPage> {
  int _type = 0; // 0 支出 / 1 收入
  String _input = '0';
  Category? _category;
  final _noteCtrl = TextEditingController();
  List<Category> _cats = [];
  DateTime _time = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      final t = widget.editing!;
      _type = t.type;
      _input = t.amount.toString();
      _noteCtrl.text = t.note;
      _time = t.date;
    }
    _loadCats();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    final list = await Db.categories(type: _type);
    if (!mounted) return;
    setState(() {
      _cats = list;
      if (_category != null) {
        _category = list.firstWhere((c) => c.id == _category!.id,
            orElse: () => list.isEmpty ? _category! : list.first);
      }
      _category ??= list.isNotEmpty ? list.first : null;
    });
  }

  double get _amount => double.tryParse(_input) ?? 0;

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == 'del') {
        _input = _input.length <= 1 ? '0' : _input.substring(0, _input.length - 1);
      } else if (k == '.') {
        if (!_input.contains('.')) _input += '.';
      } else {
        if (_input == '0') {
          _input = k;
        } else if (_input.contains('.')) {
          if (_input.split('.')[1].length < 2) _input += k;
        } else if (_input.length < 9) {
          _input += k;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入金额'), duration: Duration(seconds: 1)),
      );
      return;
    }
    if (_category == null) return;
    setState(() => _saving = true);

    try {
      if (widget.editing != null) {
        await Db.updateTxn(Txn(
          id: widget.editing!.id,
          amount: _amount,
          type: _type,
          categoryId: _category!.id!,
          note: _noteCtrl.text.trim(),
          timestamp: _time.millisecondsSinceEpoch,
        ));
        if (!mounted) return;
        // Db.updateTxn 内部已广播数据变更，账单/统计/预算会自动刷新
        Navigator.pop(context, true);
        return;
      }

      await Db.addTxn(Txn(
        amount: _amount,
        type: _type,
        categoryId: _category!.id!,
        note: _noteCtrl.text.trim(),
        timestamp: _time.millisecondsSinceEpoch,
      ));

      if (!mounted) return;
      // 记完立刻能看到这个月的预算进度
      _showSavedToast();
      // Db.addTxn 内部已广播数据变更，账单/统计/预算会自动刷新
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 保存后浮出预算进度提示 —— 让用户马上知道还剩多少
  void _showSavedToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('已记录 ${fmtMoney(_amount)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSub),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.editing == null ? '记一笔' : '编辑',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          // 时间可改
          TextButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.access_time, size: 15, color: AppColors.textSub),
            label: Text(
              '${fmtTime(_time)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _typeSwitch(),
          _amountDisplay(),
          _noteField(),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(child: _categoryGrid()),
          _keypad(),
          _saveBar(),
        ],
      ),
    );
  }

  Widget _typeSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _typeBtn('支出', 0),
          const SizedBox(width: 8),
          _typeBtn('收入', 1),
        ],
      ),
    );
  }

  Widget _typeBtn(String label, int v) {
    final on = _type == v;
    return GestureDetector(
      onTap: () {
        setState(() {
          _type = v;
          _category = null;
        });
        _loadCats();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? (v == 0 ? AppColors.expense : AppColors.income)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }

  Widget _amountDisplay() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('¥',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: _category?.color ?? AppColors.textMain,
              )),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _input,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                color: AppColors.textMain,
              ),
            ),
          ),
          if (_category != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _category!.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(_category!.icon, size: 13, color: _category!.color),
                  const SizedBox(width: 5),
                  Text(_category!.name,
                      style: TextStyle(
                          fontSize: 12,
                          color: _category!.color,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _noteField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 16, color: AppColors.textSub),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _noteCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '备注（可选）',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryGrid() {
    if (_cats.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _cats.length,
      itemBuilder: (_, i) {
        final c = _cats[i];
        final on = _category?.id == c.id;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _category = c);
          },
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: on ? c.color : c.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(c.icon,
                    size: 20, color: on ? Colors.white : c.color),
              ),
              const SizedBox(height: 5),
              Text(
                c.name,
                style: TextStyle(
                  fontSize: 11,
                  color: on ? AppColors.textMain : AppColors.textSub,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _keypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'del'],
    ];
    return Container(
      color: const Color(0xFFFAFBFC),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Column(
        children: [
          for (final row in keys)
            Row(
              children: [
                for (final k in row) Expanded(child: _key(k)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _key(String k) {
    return InkWell(
      onTap: () => _tap(k),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        child: k == 'del'
            ? const Icon(Icons.backspace_outlined, size: 20, color: AppColors.textSub)
            : Text(k,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMain)),
      ),
    );
  }

  Widget _saveBar() {
    return Container(
      color: const Color(0xFFFAFBFC),
      padding: EdgeInsets.fromLTRB(
          16, 6, 16, 10 + MediaQuery.of(context).padding.bottom),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            primary: _category?.color ?? AppColors.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('保存',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    setState(() {
      _time = DateTime(d.year, d.month, d.day, t?.hour ?? _time.hour,
          t?.minute ?? _time.minute);
    });
  }
}
