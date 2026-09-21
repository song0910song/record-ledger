import 'package:intl/intl.dart';

/// 金额格式化：¥1,234.50，去掉多余的 .00
String fmtMoney(double v, {bool withSymbol = true}) {
  final s = NumberFormat('#,##0.##', 'en_US').format(v);
  return withSymbol ? '¥$s' : s;
}

/// 紧凑格式：1.2万 / 1234
String fmtCompact(double v) {
  if (v.abs() >= 10000) {
    final w = v / 10000;
    return '${NumberFormat('#,##0.##', 'en_US').format(w)}万';
  }
  return NumberFormat('#,##0.##', 'en_US').format(v);
}

/// 友好的日期
String fmtDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff == 2) return '前天';
  if (d.year == now.year) return DateFormat('M月d日 EEEE', 'zh_CN').format(d);
  return DateFormat('yyyy年M月d日', 'zh_CN').format(d);
}

String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);

/// 中文星期
String weekdayCn(DateTime d) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return '周${names[d.weekday - 1]}';
}
