import 'package:flutter_test/flutter_test.dart';
import 'package:record_ledger/services/data_bus.dart';

void main() {
  test('DataBus 广播能通知所有订阅者', () {
    int a = 0, b = 0, c = 0;
    void onA() => a++;
    void onB() => b++;
    void onC() => c++;

    DataBus.instance.addListener(onA);
    DataBus.instance.addListener(onB);
    DataBus.instance.addListener(onC);

    expect(a, 0);
    expect(b, 0);
    expect(c, 0);

    // 模拟"记一笔"触发广播
    DataBus.notify();

    expect(a, 1, reason: '账单页应被通知');
    expect(b, 1, reason: '统计页应被通知');
    expect(c, 1, reason: '预算页应被通知');

    DataBus.notify();
    expect(a, 2);
    expect(b, 2);
    expect(c, 2);

    // 退订后不应再收到
    DataBus.instance.removeListener(onB);
    DataBus.notify();
    expect(a, 3);
    expect(b, 2, reason: '已退订，不应再收到通知');
    expect(c, 3);

    DataBus.instance.removeListener(onA);
    DataBus.instance.removeListener(onC);
  });

  test('版本号随广播递增', () {
    final v0 = DataBus.instance.version;
    DataBus.notify();
    expect(DataBus.instance.version, v0 + 1);
    DataBus.notify();
    expect(DataBus.instance.version, v0 + 2);
  });
}
