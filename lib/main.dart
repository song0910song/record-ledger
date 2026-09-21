import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'services/db.dart';
import 'services/pay_detect_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_shell.dart';

/// 数据库初始化失败时记录的错误信息。
/// 非 null 时首页会显示错误界面，而不是一直转圈。
String? dbInitError;

Future<void> main() async {
  // 捕获 Flutter 框架层未处理的异常，避免 release 模式下直接闪退
  WidgetsFlutterBinding.ensureInitialized();

  // 日期本地化失败不应阻塞启动
  try {
    await initializeDateFormatting('zh_CN', null);
  } catch (_) {}

  // 预热数据库：首次启动建表 + 灌入默认分类。
  // 失败时记录错误，交给界面提示，而不是让 App 白屏或闪退。
  try {
    await Db.instance;
  } catch (e) {
    dbInitError = e.toString();
  }

  // 初始化支付监听通道。
  // 即使当前没有授权也不报错 —— 用户可以在「我的」页里随时去开启。
  try {
    await PayDetectService.instance.init();
  } catch (_) {}

  runApp(const LedgerApp());
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('zh', 'CN'),
      home: dbInitError == null
          ? const HomeShell()
          : _StartupErrorPage(message: dbInitError!),
    );
  }
}

/// 启动失败提示页 —— 至少让用户知道发生了什么，而不是对着转圈等待
class _StartupErrorPage extends StatelessWidget {
  final String message;
  const _StartupErrorPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storage_outlined,
                    size: 56, color: AppColors.textSub),
                const SizedBox(height: 16),
                const Text('本地存储初始化失败',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                const Text(
                  'App 需要访问本机存储来保存账单。\n'
                  '请确认已授予存储权限，然后重新打开。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSub, height: 1.6),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSub,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
