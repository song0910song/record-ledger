import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/data_bus.dart';
import '../services/db.dart';
import '../theme/app_theme.dart';

/// 分类管理 —— 可增删、改图标和颜色
class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  int _type = 0;
  List<Category> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // 订阅数据变更：分类增删改后自动刷新列表
    DataBus.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() => _loading = true);
      final list = await Db.categories(type: _type);
      if (!mounted) return;
      setState(() {
        _cats = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('管理分类', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add, size: 17, color: AppColors.primary),
            label: const Text('新增',
                style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _seg('支出', 0),
                const SizedBox(width: 8),
                _seg('收入', 1),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < _cats.length; i++) ...[
                              _row(_cats[i]),
                              if (i != _cats.length - 1)
                                const Padding(
                                  padding: EdgeInsets.only(left: 56),
                                  child: Divider(
                                      height: 1, color: AppColors.divider),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '提示：删除分类不会删除已有账单，那些账单会显示为「未分类」。',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSub,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, int v) {
    final on = _type == v;
    return GestureDetector(
      onTap: () {
        setState(() => _type = v);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : AppColors.textSub)),
      ),
    );
  }

  Widget _row(Category c) {
    return InkWell(
      onTap: () => _edit(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(c.icon, size: 16, color: c.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            GestureDetector(
              onTap: () => _confirmDelete(c),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 15, color: AppColors.textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<IconData> _icons = [
    Icons.restaurant,
    Icons.local_cafe,
    Icons.shopping_bag,
    Icons.directions_bus,
    Icons.local_taxi,
    Icons.home,
    Icons.bolt,
    Icons.water_drop,
    Icons.sports_esports,
    Icons.movie,
    Icons.music_note,
    Icons.fitness_center,
    Icons.local_hospital,
    Icons.medication,
    Icons.smartphone,
    Icons.wifi,
    Icons.card_giftcard,
    Icons.menu_book,
    Icons.school,
    Icons.pets,
    Icons.child_care,
    Icons.flight,
    Icons.hotel,
    Icons.local_gas_station,
    Icons.account_balance_wallet,
    Icons.emoji_events,
    Icons.work_outline,
    Icons.trending_up,
    Icons.redeem,
    Icons.receipt_long,
    Icons.more_horiz,
    Icons.savings,
    Icons.attach_money,
  ];

  Future<void> _edit(Category? c) async {
    final nameCtrl = TextEditingController(text: c?.name ?? '');
    int iconCode = c?.iconCode ?? _icons.first.codePoint;
    int colorValue = c?.colorValue ?? AppColorsSeed.palette[0];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                Text(c == null ? '新增分类' : '编辑分类',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: c == null,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '分类名称',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('图标',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: _icons.length,
                    itemBuilder: (_, i) {
                      final on = iconCode == _icons[i].codePoint;
                      return GestureDetector(
                        onTap: () => setS(() => iconCode = _icons[i].codePoint),
                        child: Container(
                          decoration: BoxDecoration(
                            color: on
                                ? Color(colorValue).withValues(alpha: 0.15)
                                : AppColors.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: on
                                ? Border.all(
                                    color: Color(colorValue), width: 1.5)
                                : null,
                          ),
                          child: Icon(_icons[i],
                              size: 17,
                              color:
                                  on ? Color(colorValue) : AppColors.textSub),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                const Text('颜色',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: AppColorsSeed.palette.map((v) {
                    final on = colorValue == v;
                    return GestureDetector(
                      onTap: () => setS(() => colorValue = v),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(v),
                          shape: BoxShape.circle,
                          border: on
                              ? Border.all(color: AppColors.textMain, width: 2)
                              : null,
                        ),
                        child: on
                            ? const Icon(Icons.check,
                                size: 15, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      if (c == null) {
                        await Db.addCategory(Category(
                          name: name,
                          iconCode: iconCode,
                          colorValue: colorValue,
                          type: _type,
                          sort: _cats.length,
                        ));
                      } else {
                        await Db.deleteCategory(c.id!);
                        await Db.addCategory(Category(
                          name: name,
                          iconCode: iconCode,
                          colorValue: colorValue,
                          type: c.type,
                          sort: c.sort,
                        ));
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
              ],
            ),
          ),
        ),
      ),
    );
    _load();
  }

  Future<void> _confirmDelete(Category c) async {
    if (_cats.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个分类')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('删除「${c.name}」？', style: const TextStyle(fontSize: 16)),
        content:
            const Text('已有账单不会删除，会显示为「未分类」。', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Db.deleteCategory(c.id!);
      _load();
    }
  }
}
