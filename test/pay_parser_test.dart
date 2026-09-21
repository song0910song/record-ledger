import 'package:flutter_test/flutter_test.dart';
import 'package:record_ledger/services/pay_parser.dart';

void main() {
  const alipay = PayParser.pkgAlipay;
  const wechat = PayParser.pkgWechat;

  group('来源识别', () {
    test('识别支付宝和微信', () {
      expect(PayParser.sourceOf(alipay), '支付宝');
      expect(PayParser.sourceOf(wechat), '微信');
    });

    test('其他 App 的通知一律忽略', () {
      expect(PayParser.sourceOf('com.android.systemui'), isNull);
      expect(PayParser.sourceOf('com.taobao.taobao'), isNull);
      expect(PayParser.sourceOf('com.eg.android.AlipayGphone2'), isNull);
    });
  });

  group('支出解析', () {
    test('微信：向商户付款', () {
      final r = PayParser.parse(
        packageName: wechat,
        title: '微信支付凭证',
        body: '向 美团 付款 25.50 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 25.50);
      expect(r.type, 0, reason: '应该是支出');
      expect(r.source, '微信');
      expect(r.merchant, '美团');
    });

    test('微信：¥ 符号金额', () {
      final r = PayParser.parse(
        packageName: wechat,
        title: '微信支付',
        body: '微信支付收款 ¥12.50',
      );
      // 注意：这里含"收款"，应判为收入
      expect(r, isNotNull);
      expect(r!.amount, 12.50);
      expect(r.type, 1, reason: '收款应判为收入');
    });

    test('支付宝：消费', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '你有一笔 38.00 元的支出',
      );
      expect(r, isNotNull);
      expect(r!.amount, 38.00);
      expect(r.type, 0);
      expect(r.source, '支付宝');
    });

    test('支付宝：在商户消费', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '在 星巴克 消费 45.00 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 45.00);
      expect(r.type, 0);
      expect(r.merchant, '星巴克');
    });

    test('支持千分位金额', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '付款 1,234.56 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 1234.56);
    });

    test('整数金额没有小数点', () {
      final r = PayParser.parse(
        packageName: wechat,
        title: '微信',
        body: '支付 100 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 100.0);
      expect(r.type, 0);
    });
  });

  group('收入解析', () {
    test('微信：收款', () {
      final r = PayParser.parse(
        packageName: wechat,
        title: '微信支付凭证',
        body: '微信支付收款 200.00 元',
      );
      expect(r, isNotNull);
      expect(r!.type, 1);
      expect(r.amount, 200.00);
    });

    test('支付宝：已到账', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '转账 500.00 元 已到账',
      );
      expect(r, isNotNull);
      expect(r!.type, 1);
      expect(r.amount, 500.00);
    });

    test('退款优先判为收入（同时含收支关键词）', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '退款 25.00 元 已原路退回',
      );
      expect(r, isNotNull);
      expect(r!.type, 1, reason: '退款应算收入');
    });
  });

  group('应该被忽略的通知', () {
    test('营销活动', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '优惠券即将过期，快来使用',
        ),
        isNull,
      );
    });

    test('账单提醒', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '你的花呗账单已出，请及时还款提醒',
        ),
        isNull,
      );
    });

    test('支付失败', () {
      expect(
        PayParser.parse(
          packageName: wechat,
          title: '微信支付',
          body: '支付失败 25.00 元',
        ),
        isNull,
      );
    });

    test('待支付', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '待支付 99.00 元',
        ),
        isNull,
      );
    });

    test('验证码/登录提醒', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '验证码 123456，请勿泄露',
        ),
        isNull,
      );
    });

    test('零钱通内部转账', () {
      expect(
        PayParser.parse(
          packageName: wechat,
          title: '微信',
          body: '零钱通 转入 1000.00 元',
        ),
        isNull,
      );
    });
  });

  group('解析失败的场景（应返回 null，交给用户判断）', () {
    test('没有金额', () {
      expect(
        PayParser.parse(
          packageName: wechat,
          title: '微信支付',
          body: '你有一笔新的交易',
        ),
        isNull,
      );
    });

    test('没有收支方向关键词', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '关于 25.00 元的通知',
        ),
        isNull,
      );
    });

    test('金额为 0', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '支出 0.00 元',
        ),
        isNull,
      );
    });

    test('金额异常大', () {
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '支出 99999999.00 元',
        ),
        isNull,
      );
    });

    test('空文本', () {
      expect(
        PayParser.parse(packageName: alipay, title: '', body: ''),
        isNull,
      );
    });

    test('"支付宝"这个标题本身不应被当成支出关键词', () {
      // 回归测试：曾经因为"支付宝"里含"支付"二字，
      // 导致所有支付宝通知都被误判成支出。
      expect(
        PayParser.parse(
          packageName: alipay,
          title: '支付宝',
          body: '关于 25.00 元的通知',
        ),
        isNull,
        reason: '"支付宝"里的"支付"不能作为支出依据',
      );
    });

    test('"微信支付"标题同样不应干扰判断', () {
      expect(
        PayParser.parse(
          packageName: wechat,
          title: '微信支付',
          body: '你有一笔新的交易 25.00 元',
        ),
        isNull,
      );
    });
  });

  group('分类智能推荐', () {
    test('美团 → 餐饮', () {
      expect(PayParser.suggestCategory('美团', 0), '餐饮');
    });

    test('滴滴 → 交通', () {
      expect(PayParser.suggestCategory('滴滴出行', 0), '交通');
    });

    test('地铁 → 交通', () {
      expect(PayParser.suggestCategory('', 0) == null, isTrue);
      expect(PayParser.suggestCategoryFromText('地铁 3.00 元', 0), '交通');
    });

    test('淘宝 → 购物', () {
      expect(PayParser.suggestCategory('淘宝', 0), '购物');
    });

    test('星巴克 → 餐饮', () {
      expect(PayParser.suggestCategory('星巴克', 0), '餐饮');
    });

    test('工资 → 工资（收入侧）', () {
      expect(PayParser.suggestCategory('公司代发', 1), '工资');
    });

    test('未知商户返回 null', () {
      expect(PayParser.suggestCategory('某个没见过的店', 0), isNull);
    });

    test('空商户返回 null', () {
      expect(PayParser.suggestCategory('', 0), isNull);
    });
  });

  group('端到端：从通知到可用的记账建议', () {
    test('微信支付美团外卖', () {
      final r = PayParser.parse(
        packageName: wechat,
        title: '微信支付凭证',
        body: '向 美团 付款 32.00 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 32.00);
      expect(r.type, 0);
      final cat = PayParser.suggestCategory(r.merchant, r.type) ??
          PayParser.suggestCategoryFromText(r.raw, r.type);
      expect(cat, '餐饮', reason: '美团外卖应推荐到餐饮');
    });

    test('支付宝地铁乘车码', () {
      final r = PayParser.parse(
        packageName: alipay,
        title: '支付宝',
        body: '地铁乘车码扣款 3.00 元',
      );
      expect(r, isNotNull);
      expect(r!.amount, 3.00);
      expect(r.type, 0, reason: '"扣款"应判为支出');
      final cat = PayParser.suggestCategoryFromText(r.raw, r.type);
      expect(cat, '交通');
    });
  });
}
