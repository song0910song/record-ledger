import 'dart:convert';
import 'dart:js_interop';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:web/web.dart' as web;

/// Web：换成 sqlite3 WASM 工厂。
///
/// 浏览器里没有 SQLite 原生实现，默认工厂（Android/iOS 通道）会直接抛
/// MissingPluginException。这里换成 wasm 版，数据落在 IndexedDB 里。
///
/// 依赖 `web/sqlite3.wasm` 与 `web/sqflite_sw.js`
/// （`dart run sqflite_common_ffi_web:setup` 生成）。
void useWebDatabaseFactoryIfNeeded() {
  databaseFactory = databaseFactoryFfiWeb;
}

/// Web 端的库名。不用拼目录 —— wasm 版的文件落在 IndexedDB 虚拟文件系统里。
Future<String> resolveDatabasePath() async => 'ledger.db';

/// Web 端导出：直接触发浏览器下载，返回 blob URL
Future<String> saveExportFile(String fileName, String content) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return url;
}
