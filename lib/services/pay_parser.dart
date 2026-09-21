/// 支付通知解析器
///
/// 从支付宝/微信的通知文本里提取：金额、收支方向、商户名。
///
/// 设计原则：
/// 1. **宁可解析失败，也不要解析错** —— 金额错了比不记更糟
/// 2. 规则集中在这里，支付宝/微信改文案时只改这个文件
/// 3. 解析不出来就返回 null，由上层保留原文交给用户判断
library pay_parser;

/// 解析结果
class ParsedPay {
  /// 金额（始终为正数）
  final double amount;

  /// 0=支出 1=收入
  final int type;

  /// 商户/对方名称，可能为空
  final String merchant;

  /// 命中的来源：支付宝 / 微信
  final String source;

  /// 原始通知文本，用于回溯核对
  final String raw;

  const ParsedPay({
    required this.amount,
    required this.type,
    required this.merchant,
    required this.source,
    required this.raw,
  });

  bool get isExpense => type == 0;
}

class PayParser {
  /// 通知来源 App 的包名
  static const String pkgAlipay = 'com.eg.android.AlipayGphone';
  static const String pkgWechat = 'com.tencent.mm';

  /// 判断包名是否是我们关心的支付来源
  static String? sourceOf(String packageName) {
    if (packageName == pkgAlipay) return '支付宝';
    if (packageName == pkgWechat) return '微信';
    return null;
  }

  /// 关键词 —— 用于判定收支方向
  ///
  /// 注意顺序：先判断"收入"再判断"支出"，
  /// 因为"收到退款"这类文本同时含两边关键词，退款应算收入。
  static const List<String> _incomeKeys = [
    '收款', '收到', '收入', '退款', '已到账', '转入', '红包到账', '退还',
  ];

  static const List<String> _expenseKeys = [
    '支出', '付款', '支付', '消费', '已付', '扣款', '转出', '扣费', '支付成功',
  ];

  /// 明显不该记的类型 —— 直接跳过，不打扰用户
  static const List<String> _skipKeys = [
    // 自己的账户间操作
    '零钱通', '余额宝', '转入转出',
    // 营销/系统类
    '优惠券', '红包即将过期', '活动', '账单已出', '还款提醒', '积分',
    '安全提醒', '登录', '验证码', '更新', '邀请',
    // 未完成的操作
    '待支付', '待付款', '支付失败', '交易关闭', '已取消', '订单待',
  ];

  /// 金额正则：支持 12.50 / 1,234.56 / 12 元 / 12.5元
  ///
  /// 拆解：
  ///   ([\d,]+(?:\.\d{1,2})?)  —— 数字主体，允许千分位逗号、最多两位小数
  ///   \s*元?                  —— 可选的"元"字
  static final RegExp _amountRe = RegExp(
    r'([\d,]+(?:\.\d{1,2})?)\s*元',
    caseSensitive: false,
  );

  /// 带货币符号的金额（¥ 或 ￥）
  static final RegExp _symbolAmountRe = RegExp(
    r'[¥￥]\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// 解析一条通知。解析不出来返回 null。
  ///
  /// [title] 和 [body] 分别对应通知的标题与正文，
  /// 有些支付通知金额在标题里，有些在正文里，两处都要找。
  static ParsedPay? parse({
    required String packageName,
    required String title,
    required String body,
  }) {
    final source = sourceOf(packageName);
    if (source == null) return null;

    // 合并标题和正文一起分析 —— 金额可能出现在任意一处
    final text = '$title $body'.trim();
    if (text.isEmpty) return null;

    // 1. 先看是否属于该跳过的类型
    for (final k in _skipKeys) {
      if (text.contains(k)) return null;
    }

    // 2. 提取金额：优先找带 ¥ 符号的（更明确），再退回找带"元"的
    double? amount = _extractAmount(text);
    if (amount == null) return null;

    // 金额为 0 或异常大（超过 100 万）视为解析错误
    if (amount <= 0 || amount > 1000000) return null;

    // 3. 判定收支方向
    //
    // 关键：判断前必须剔除"支付宝""微信"这类来源词。
    // 因为"支付宝"里含"支付"二字，不剔除的话
    // 任何一条支付宝通知都会被误判成支出。
    final forDirection = _stripSourceWords(text);
    final type = _detectType(forDirection);
    if (type == null) return null;

    // 4. 提取商户名
    final merchant = _extractMerchant(forDirection, source);

    return ParsedPay(
      amount: amount,
      type: type,
      merchant: merchant,
      source: source,
      raw: text,
    );
  }

  /// 剔除来源词，避免"支付宝"里的"支付"干扰方向判断
  static String _stripSourceWords(String text) {
    var s = text;
    for (final w in _sourceWords) {
      s = s.replaceAll(w, ' ');
    }
    return s;
  }

  static const List<String> _sourceWords = [
    '支付宝', '微信支付', '微信', 'Alipay', 'WeChat', 'alipay', 'wechat',
  ];

  /// 从文本里抽金额
  static double? _extractAmount(String text) {
    // 优先：带货币符号，最不容易误判
    final m1 = _symbolAmountRe.firstMatch(text);
    if (m1 != null) {
      final v = _toDouble(m1.group(1));
      if (v != null) return v;
    }

    // 退回：带"元"字的
    final m2 = _amountRe.firstMatch(text);
    if (m2 != null) {
      return _toDouble(m2.group(1));
    }

    return null;
  }

  static double? _toDouble(String? s) {
    if (s == null) return null;
    // 去掉千分位逗号
    final cleaned = s.replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  /// 判定收支方向。无法判定时返回 null（宁可让用户手动选）。
  static int? _detectType(String text) {
    // 先看收入：退款等场景会同时含收支关键词，收入优先
    for (final k in _incomeKeys) {
      if (text.contains(k)) return 1;
    }
    for (final k in _expenseKeys) {
      if (text.contains(k)) return 0;
    }
    return null;
  }

  /// 抽取商户名
  ///
  /// 微信常见格式："微信支付凭证" + "向 XX 付款 25.00 元"
  /// 支付宝常见格式："支付宝" + "你有一笔 25.00 元的支出"
  ///
  /// 这里只做保守的启发式提取，抽不到就返回空字符串 ——
  /// 商户名只影响分类推荐，错了也不致命。
  static String _extractMerchant(String text, String source) {
    // 常见模式："向 XXX 付款" / "在 XXX 消费" / "XXX 收款"
    final patterns = [
      RegExp(r'向\s*([^\s，,。的]{2,20})\s*(?:付款|转账|支付)'),
      RegExp(r'在\s*([^\s，,。的]{2,20})\s*(?:消费|支付|付款)'),
      RegExp(r'([^\s，,。的]{2,20})\s*(?:收款|已收款)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final v = m.group(1)?.trim();
        if (v != null && v.isNotEmpty && !_isNoise(v)) return v;
      }
    }
    return '';
  }

  /// 过滤掉明显不是商户名的词
  static bool _isNoise(String s) {
    const noise = [
      '支付宝', '微信', '微信支付', '你', '您', '本人', '对方', '该笔',
      '本次', '当前', '此笔', '余额', '零钱', '银行卡', '花呗',
    ];
    return noise.contains(s);
  }

  // ---------------- 商户 → 分类 智能推荐 ----------------

  /// 关键词 → 分类名 的映射表。
  ///
  /// 命中后会把对应分类预选上，用户点确认即可，不用再挑分类。
  /// 这张表是可以随时扩充的 —— 你发现哪个商户没匹配上，加一条就行。
  static const Map<String, List<String>> _merchantToCategory = {
    '餐饮': [
      '美团', '饿了么', '肯德基', '麦当劳', '星巴克', '瑞幸', '喜茶', '奈雪',
      '海底捞', '沙县', '兰州', '快餐', 'food', '餐', '饭', '食', '茶',
      '蜜雪冰城', 'coco', '一点点', '本味', '咖啡',
    ],
    '交通': [
      '滴滴', '地铁', '公交', '铁路', '12306', '高德', '曹操', 'T3',
      '出租', '航空', '机票', '加油', '中石化', '中石油', '停车', '哈啰',
      '青桔', '共享单车',
    ],
    '购物': [
      '淘宝', '天猫', '京东', '拼多多', '唯品会', '苏宁', '盒马',
      '超市', '便利店', '罗森', '全家', '永辉', '山姆', '沃尔玛',
      '优衣库', '旗舰店', '商城',
    ],
    '居住': [
      '房租', '物业', '水费', '电费', '燃气', '天然气', '供暖',
      '国家电网', '自来水',
    ],
    '娱乐': [
      '电影', '猫眼', '淘票票', 'steam', '游戏', '腾讯视频', '爱奇艺',
      '优酷', '网易云', 'qq音乐', 'b站', '哔哩哔哩', 'ktv', '剧本',
    ],
    '医疗': [
      '医院', '药房', '药店', '诊所', '挂号', '体检', '大药房', '卫生院',
    ],
    '通讯': [
      '话费', '流量', '中国移动', '中国联通', '中国电信', '宽带',
    ],
    '人情': [
      '红包', '转账', '礼金', '份子',
    ],
    '学习': [
      '书店', '图书', '当当', '得到', '知识', '学费', '培训', '网课',
    ],
  };

  /// 收入侧的关键词映射
  static const Map<String, List<String>> _incomeToCategory = {
    '工资': ['工资', '薪资', '薪酬', '代发'],
    '奖金': ['奖金', '年终', '绩效'],
    '兼职': ['兼职', '外快', '稿费'],
    '理财': ['收益', '利息', '基金', '股票', '分红'],
    '红包': ['红包', '礼金'],
    '报销': ['报销', '退款', '退还'],
  };

  /// 根据商户名推荐分类名。推荐不出来返回 null。
  static String? suggestCategory(String merchant, int type) {
    if (merchant.isEmpty) return null;
    final lower = merchant.toLowerCase();

    final table = type == 1 ? _incomeToCategory : _merchantToCategory;
    for (final entry in table.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw.toLowerCase())) return entry.key;
      }
    }
    return null;
  }

  /// 连通知原文一起看，扩大匹配范围
  /// （有时商户名抽不出来，但原文里有"美团"这种关键词）
  static String? suggestCategoryFromText(String text, int type) {
    final lower = text.toLowerCase();
    final table = type == 1 ? _incomeToCategory : _merchantToCategory;
    for (final entry in table.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw.toLowerCase())) return entry.key;
      }
    }
    return null;
  }
}
