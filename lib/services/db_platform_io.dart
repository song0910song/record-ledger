import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 桌面 / 移动端：直接用 sqflite 默认工厂（Android 原生 SQLite）。
///
/// 保留这个空函数而不是条件判断，是为了让 `db.dart` 里只有一行平台相关代码，
/// 不必到处写 kIsWeb。
void useWebDatabaseFactoryIfNeeded() {}

/// 数据库文件路径 —— 放到应用文档目录
Future<String> resolveDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'ledger.db');
}

/// 导出：写文件，返回文件路径（供后续分享）
Future<String> saveExportFile(String fileName, String content) async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File(p.join(dir.path, fileName));
  await f.writeAsString(content);
  return f.path;
}
