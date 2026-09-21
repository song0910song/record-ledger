import 'package:flutter/material.dart';

import '../services/pay_detect_service.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'stats_page.dart';
import 'budget_page.dart';
import 'settings_page.dart';
import 'add_txn_page.dart';
import 'pay_confirm_sheet.dart';

/// 四个 Tab：账单 / 统计 / 预算 / 我的
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 防止同时弹出多个确认框
  bool _sheetShowing = false;

  @override
  void initState() {
    super.initState();
    // 监听支付感应服务：检测到新支付就弹确认框
    PayDetectService.instance.onNewPending = _onNewPending;
    // 冷启动补偿：服务的 init() 在 runApp 之前就跑完了，
    // 从唤起/横幅带进来的通知那时已经进了队列，但回调还没注册。
    // 首帧渲染后检查一次，把这笔"见面礼"弹出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && PayDetectService.instance.hasQueue) {
        _onNewPending();
      }
    });
  }

  @override
  void dispose() {
    PayDetectService.instance.onNewPending = null;
    super.dispose();
  }

  /// 检测到支付 —— 弹确认框
  Future<void> _onNewPending() async {
    if (!mounted || _sheetShowing) return;

    final svc = PayDetectService.instance;
    if (!svc.hasQueue) return;

    _sheetShowing = true;
    try {
      final p = svc.queue.first;
      final saved = await PayConfirmSheet.show(context, p);

      if (saved == true && mounted) {
        // 记完切回账单页，让用户看到进度变化
        setState(() => _index = 0);
      }

      // 队列里还有别的，接着处理
      if (mounted && svc.hasQueue) {
        _sheetShowing = false;
        await Future.delayed(const Duration(milliseconds: 320));
        await _onNewPending();
        return;
      }
    } catch (_) {
      // 弹窗异常不应影响主流程
    } finally {
      _sheetShowing = false;
    }
  }

  final _pages = const [
    HomePage(),
    StatsPage(),
    BudgetPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 62,
        height: 62,
        child: FloatingActionButton(
          onPressed: () async {
            final saved = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddTxnPage()),
            );
            // 记完一笔后切回账单页 —— 用户能立刻看到预算进度变化。
            // （数据刷新由 DataBus 广播驱动，这里只负责把视图切过去）
            if (saved == true && mounted) {
              setState(() => _index = 0);
            }
          },
          backgroundColor: AppColors.primary,
          elevation: 3,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
      bottomNavigationBar: _buildBar(),
    );
  }

  Widget _buildBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomAppBar(
        color: Colors.white,
        elevation: 0,
        notchMargin: 8,
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _tab(0, Icons.receipt_long_outlined, Icons.receipt_long, '账单'),
              _tab(1, Icons.pie_chart_outline, Icons.pie_chart, '统计'),
              const SizedBox(width: 62), // FAB 占位
              _tab(2, Icons.savings_outlined, Icons.savings, '预算'),
              _tab(3, Icons.person_outline, Icons.person, '我的'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, IconData activeIcon, String label) {
    final on = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(on ? activeIcon : icon,
                size: 22, color: on ? AppColors.primary : AppColors.textSub),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: on ? AppColors.primary : AppColors.textSub,
                    fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
