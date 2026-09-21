import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'db.dart';
import 'pay_parser.dart';

/// 一条待确认的支付记录 —— 解析成功但还没入库
class PendingPay {
  /// 解析出来的金额（解析失败时为 0）
  final double amount;

  /// 0=支出 1=收入
  final int type;

  /// 解析出的商户名，可能为空
  final String merchant;

  /// 来源：支付宝 / 微信
  final String source;

  /// 通知原文 —— 解析失败时用户靠它判断
  final String raw;

  /// 推荐分类的 id（可能为 null）
  final int? suggestedCategoryId;

  /// 通知时间
  final DateTime time;

  /// 解析是否成功。false 表示需要用户手动补金额
  final bool parsed;

  /// 去重用的指纹
  final String fingerprint;

  PendingPay({
    required this.amount,
    required this.type,
    required this.merchant,
    required this.source,
    required this.raw,
    required this.suggestedCategoryId,
    required this.time,
    required this.parsed,
    required this.fingerprint,
  });
}

/// 支付感应服务
///
/// 职责：
/// 1. 与 Android 原生层通信，接收支付通知
/// 2. 去重（微信常连发多条通知）
/// 3. 匹配分类
/// 4. 通知 UI 弹出确认框
/// 5. 上报 App 前后台状态 —— 后台时通知走「唤起 App / 横幅」路径，
///    实现付款后立即弹出，而不是等用户打开 App
class PayDetectService extends ChangeNotifier with WidgetsBindingObserver {
  PayDetectService._();
  static final PayDetectService instance = PayDetectService._();

  static const MethodChannel _channel = MethodChannel('record_ledger/pay');

  /// 最近处理过的指纹，用于去重。
  /// key=指纹, value=处理时间
  final Map<String, DateTime> _seen = {};

  /// 去重保留时长 —— 同一笔支付在 3 分钟内只处理一次
  static const Duration _dedupWindow = Duration(minutes: 3);

  /// 当前待用户确认的记录队列
  final List<PendingPay> _queue = [];
  List<PendingPay> get queue => List.unmodifiable(_queue);
  bool get hasQueue => _queue.isNotEmpty;

  /// 监听通道是否可用（非 Android 平台为 false）
  bool _available = false;
  bool get available => _available;

  /// 通知使用权是否已开启
  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  /// 悬浮窗权限（显示在其他应用上层）是否已开启。
  ///
  /// 有它，付款后确认框能立即弹到屏幕上（系统豁免后台弹界面限制）；
  /// 没有它，降级为发一条高优先级横幅通知，点击后直达确认框。
  bool _canOverlay = false;
  bool get canOverlay => _canOverlay;

  /// 通知权限（Android 13+ 发横幅通知需要）
  bool _notifyGranted = true;
  bool get notifyGranted => _notifyGranted;

  /// 是否启用感应功能（用户可以关掉）
  bool _enabled = true;
  bool get enabled => _enabled;

  /// 收到新通知时的回调 —— 供 UI 层监听以便弹窗
  VoidCallback? onNewPending;

  /// 初始化：检查权限、告诉原生层我们准备好了
  Future<void> init() async {
    try {
      _permissionGranted = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      _canOverlay = await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
      _notifyGranted = await _channel.invokeMethod<bool>('hasNotifyPermission') ?? true;
      _available = true;
      _channel.setMethodCallHandler(_handleNativeCall);

      // 监听前后台切换：退到后台时告诉原生层改走唤起/横幅路径
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      if (_permissionGranted && _enabled) {
        // 拉取 App 未运行时累积的通知（含从唤起/横幅带进来的那笔）
        final raw = await _channel.invokeMethod<String>('ready');
        _consumeBatch(raw);
      }
    } on MissingPluginException {
      // 非 Android 平台（比如桌面调试），静默降级
      _available = false;
    } catch (_) {
      _available = false;
    }
  }

  /// App 前后台切换 → 同步给原生层
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_available) return;
    if (state == AppLifecycleState.paused) {
      // 退到后台：通知到达时原生层会把 App 拉起或发横幅
      _reportBackground();
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台：重新接管，并补发离开期间攒下的通知
      _reportForeground();
    }
  }

  Future<void> _reportBackground() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> _reportForeground() async {
    if (!_enabled) return;
    try {
      _permissionGranted = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      _canOverlay = await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
      if (_permissionGranted) {
        final raw = await _channel.invokeMethod<String>('ready');
        _consumeBatch(raw);
      }
      notifyListeners();
    } catch (_) {}
  }

  /// 重新检查权限（用户从设置页返回时调用）
  Future<bool> refreshPermission() async {
    if (!_available) return false;
    try {
      _permissionGranted = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      _canOverlay = await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
      _notifyGranted = await _channel.invokeMethod<bool>('hasNotifyPermission') ?? true;
      if (_permissionGranted && _enabled) {
        // 刚获得权限时，可能已经积压了一些通知
        final raw = await _channel.invokeMethod<String>('ready');
        _consumeBatch(raw);
      }
      notifyListeners();
      return _permissionGranted;
    } catch (_) {
      return false;
    }
  }

  /// 跳转到系统设置页开启通知使用权
  Future<void> openPermissionSettings() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<bool>('openSettings');
    } catch (_) {}
  }

  /// 跳转到悬浮窗权限设置页（付款时立即弹出确认框需要）
  Future<void> openOverlaySettings() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<bool>('openOverlaySettings');
    } catch (_) {}
  }

  /// 请求通知权限（Android 13+ 发横幅通知需要）。返回是否已授权。
  Future<bool> ensureNotifyPermission() async {
    if (!_available) return true;
    try {
      _notifyGranted =
          await _channel.invokeMethod<bool>('ensureNotifyPermission') ?? true;
      notifyListeners();
      return _notifyGranted;
    } catch (_) {
      return true;
    }
  }

  /// 开关感应功能
  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      if (v) {
        await _channel.invokeMethod('ready');
      } else {
        await _channel.invokeMethod('pause');
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 原生层推来的通知
  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onPayNotification') {
      final raw = call.arguments as String?;
      if (raw != null) _consumeOne(raw);
    }
  }

  /// 批量处理（App 启动时补发的缓存）
  void _consumeBatch(String? json) {
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List;
      for (final item in list) {
        _consumeOne(jsonEncode(item));
      }
    } catch (_) {}
  }

  /// 处理一条原始通知
  void _consumeOne(String jsonStr) {
    if (!_enabled) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final pkg = data['package'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final ts = data['postTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    final parsed = PayParser.parse(
      packageName: pkg,
      title: title,
      body: body,
    );

    // 去重指纹：来源 + 金额 + 原文
    // 微信有时同一笔支付连发多条，靠这个过滤
    final fp = _fingerprint(pkg, parsed?.amount, title, body);
    if (_isDuplicate(fp)) return;
    _markSeen(fp);

    if (parsed == null) {
      // 解析失败：保留原文，让用户自己判断
      // 但只在文本里"看起来有金额"时才留 —— 否则会把营销通知也塞满列表
      if (!_looksLikePayment(title, body)) return;
      _enqueue(PendingPay(
        amount: 0,
        type: 0,
        merchant: '',
        source: PayParser.sourceOf(pkg) ?? '',
        raw: '$title\n$body'.trim(),
        suggestedCategoryId: null,
        time: DateTime.fromMillisecondsSinceEpoch(ts),
        parsed: false,
        fingerprint: fp,
      ));
      return;
    }

    // 解析成功，匹配分类
    _enqueue(PendingPay(
      amount: parsed.amount,
      type: parsed.type,
      merchant: parsed.merchant,
      source: parsed.source,
      raw: parsed.raw,
      suggestedCategoryId: null, // 分类匹配是异步的，见 _enqueue
      time: DateTime.fromMillisecondsSinceEpoch(ts),
      parsed: true,
      fingerprint: fp,
    ));

    // 异步补上分类推荐
    _attachCategory(fp, parsed);
  }

  /// 异步查数据库，把推荐分类挂到队列里的那条记录上
  Future<void> _attachCategory(String fp, ParsedPay parsed) async {
    try {
      final cats = await Db.categories(type: parsed.type);

      // 先从商户名推，推不出来再拿原文推
      String? name = PayParser.suggestCategory(parsed.merchant, parsed.type);
      name ??= PayParser.suggestCategoryFromText(parsed.raw, parsed.type);

      if (name == null) return;

      // 找到同名分类的 id
      final hit = cats.where((c) => c.name == name).toList();
      if (hit.isEmpty) return;

      final idx = _queue.indexWhere((p) => p.fingerprint == fp);
      if (idx < 0) return;

      final old = _queue[idx];
      _queue[idx] = PendingPay(
        amount: old.amount,
        type: old.type,
        merchant: old.merchant,
        source: old.source,
        raw: old.raw,
        suggestedCategoryId: hit.first.id,
        time: old.time,
        parsed: old.parsed,
        fingerprint: old.fingerprint,
      );
      notifyListeners();
    } catch (_) {}
  }

  void _enqueue(PendingPay p) {
    _queue.add(p);
    notifyListeners();
    onNewPending?.call();
  }

  /// 用户确认后：从队列移除
  void resolve(PendingPay p) {
    _queue.removeWhere((e) => e.fingerprint == p.fingerprint);
    notifyListeners();
  }

  /// 忽略某条
  void dismiss(PendingPay p) => resolve(p);

  /// 清空队列
  void clear() {
    _queue.clear();
    notifyListeners();
  }

  /// 手动重新解析一条（用户在看的时候可能改动了原文？暂未使用，留扩展）
  void requeue(PendingPay p) {
    _queue.removeWhere((e) => e.fingerprint == p.fingerprint);
    _seen.remove(p.fingerprint);
    notifyListeners();
  }

  // ---------------- 去重 ----------------

  String _fingerprint(String pkg, double? amount, String title, String body) {
    // 金额参与指纹，但原文也参与 —— 避免"两笔都是 25 元"被误判为重复
    final core = '$pkg|${amount ?? '?'}|$title|$body';
    return core.hashCode.toString();
  }

  bool _isDuplicate(String fp) {
    _evictOld();
    return _seen.containsKey(fp);
  }

  void _markSeen(String fp) {
    _seen[fp] = DateTime.now();
  }

  /// 清掉过期的去重记录，避免内存无限增长
  void _evictOld() {
    final now = DateTime.now();
    _seen.removeWhere((_, t) => now.difference(t) > _dedupWindow);
  }

  /// 粗略判断一段文本是否像支付通知（用于解析失败时的取舍）
  ///
  /// 目的：不要把"红包即将过期"这种营销通知也塞进待处理列表。
  bool _looksLikePayment(String title, String body) {
    final t = '$title $body';
    final hasAmount = RegExp(r'[\d,]+(?:\.\d{1,2})?\s*元').hasMatch(t) ||
        RegExp(r'[¥￥]\s*[\d,]+').hasMatch(t);
    if (!hasAmount) return false;

    // 必须有"钱"的语义
    const moneyWords = [
      '付款', '支付', '支出', '消费', '收款', '收到', '退款',
      '扣款', '转账', '到账', '扣费', '已付',
    ];
    return moneyWords.any(t.contains);
  }
}
