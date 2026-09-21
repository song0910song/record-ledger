import 'package:flutter/foundation.dart';

/// 数据变更广播器。
///
/// 所有会改动数据库的操作（记账、改预算、删账单、加分类、清空数据）
/// 完成后都会调用 [DataBus.notify]，已订阅的页面收到通知后重新加载。
///
/// 用全局单例而不是逐层传回调，好处是：
/// - 页面之间不需要知道对方存在，加新页面无需改调用链
/// - 一次记账能同时刷新账单/统计/预算三个页面
class DataBus extends ChangeNotifier {
  DataBus._();
  static final DataBus instance = DataBus._();

  /// 单调递增的版本号。页面可用它判断数据是否真的变了，
  /// 避免在没变化时做无谓的重新查询。
  int _version = 0;
  int get version => _version;

  /// 标记数据已变更，通知所有订阅者
  static void notify() {
    final self = instance;
    self._version++;
    self.notifyListeners();
  }
}
