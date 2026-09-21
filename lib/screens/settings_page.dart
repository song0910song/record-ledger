import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/data_bus.dart';
import '../services/db.dart';
import '../services/pay_detect_service.dart';
import '../theme/app_theme.dart';
import 'category_manage_page.dart';
import 'pay_detect_settings_page.dart';

/// 我的 —— 数据管理（导出永远免费）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
    // 订阅数据变更：记账或清空数据后，累计记录数要跟着变
    DataBus.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final c = await Db.txnCount();
      if (!mounted) return;
      setState(() => _count = c);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('我的',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),

          // 数据概况
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF00A383)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 28),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('累计记录',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 2),
                    Text('$_count 笔',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text('数据仅存本机',
                        style: TextStyle(fontSize: 11, color: Colors.white70)),
                    SizedBox(height: 2),
                    Text('不上传、无广告',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionTitle('自动记账'),
          _card([
            _tile(
              Icons.notifications_active_outlined,
              '感应支付宝/微信支付',
              _paySubtitle(),
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PayDetectSettingsPage()));
                if (mounted) setState(() {});
              },
            ),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('数据'),
          _card([
            _tile(Icons.file_download_outlined, '导出 CSV', 'Excel 可直接打开，永久免费',
                onTap: _exportCsv),
            _line(),
            _tile(Icons.backup_outlined, '导出 JSON 备份', '完整数据，可留档',
                onTap: _exportJson),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('分类'),
          _card([
            _tile(Icons.category_outlined, '管理分类', '增删分类、改名、换图标',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CategoryManagePage()))),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('关于'),
          _card([
            _tile(Icons.info_outline, '版本', 'v1.0.0 · 纯本地离线版'),
            _line(),
            _tile(Icons.code, '技术', 'Flutter + SQLite'),
            _line(),
            _tile(Icons.shield_outlined, '隐私', '无网络权限，数据不出手机'),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('危险操作'),
          _card([
            _tile(Icons.delete_forever_outlined, '清空所有数据', '删除全部账单和预算',
                danger: true, onTap: _confirmClear),
          ]),

          const SizedBox(height: 24),
          const Center(
            child: Text('你的数据，永远归你。',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  /// 「自动记账」那一行的副标题 —— 直接显示当前状态，不用点进去才知道
  String _paySubtitle() {
    final svc = PayDetectService.instance;
    if (!svc.available) return '当前平台不支持';
    if (svc.permissionGranted) {
      return svc.enabled ? '已开启 · 检测到支付会提示确认' : '已授权，但功能已关闭';
    }
    return '未开启 · 点此去设置';
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      );

  Widget _line() => const Padding(
        padding: EdgeInsets.only(left: 56),
        child: Divider(height: 1, color: AppColors.divider),
      );

  Widget _tile(IconData icon, String title, String sub,
      {VoidCallback? onTap, bool danger = false}) {
    final c = danger ? AppColors.danger : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: danger ? AppColors.danger : AppColors.textMain)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSub)),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final f = await Db.exportCsv();
      await Share.shareXFiles([XFile(f.path)], text: '记账数据导出');
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e');
    }
  }

  Future<void> _exportJson() async {
    try {
      final json = await Db.exportJson();
      final dir = await Db.exportCsv(); // 复用目录
      // 直接分享文本
      await Share.share(json.substring(0, json.length > 5000 ? 5000 : json.length));
      if (dir.path.isEmpty) return;
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空所有数据？', style: TextStyle(fontSize: 16)),
        content: const Text('将删除全部账单和预算设置，且无法恢复。建议先导出备份。',
            style: TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Db.clearAll();
      await _loadCount();
      if (mounted) _toast('已清空');
    }
  }
}
