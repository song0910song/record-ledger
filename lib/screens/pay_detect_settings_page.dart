import 'package:flutter/material.dart';

import '../services/pay_detect_service.dart';
import '../theme/app_theme.dart';

/// 自动记账设置页
///
/// 这个页面的核心任务：把「怎么开通知使用权」讲清楚。
/// 这个权限藏得深，光说"去设置里开"用户根本找不到。
class PayDetectSettingsPage extends StatefulWidget {
  const PayDetectSettingsPage({super.key});

  @override
  State<PayDetectSettingsPage> createState() => _PayDetectSettingsPageState();
}

class _PayDetectSettingsPageState extends State<PayDetectSettingsPage>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 从系统设置页返回时，自动重新检查权限状态
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户可能刚去设置里开了权限再切回来
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    await PayDetectService.instance.refreshPermission();
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    setState(() => _busy = true);
    await PayDetectService.instance.openPermissionSettings();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('请在列表里找到「记账」并打开开关');
  }

  Future<void> _openOverlaySettings() async {
    setState(() => _busy = true);
    await PayDetectService.instance.openOverlaySettings();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('请允许「记账」显示在其他应用上层');
  }

  Future<void> _ensureNotify() async {
    await PayDetectService.instance.ensureNotifyPermission();
    if (mounted) setState(() {});
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = PayDetectService.instance;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('感应支付',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _statusCard(svc),
          const SizedBox(height: 18),
          _sectionTitle('功能开关'),
          _card([
            SwitchListTile(
              value: svc.enabled && svc.permissionGranted,
              onChanged: svc.permissionGranted
                  ? (v) async {
                      await PayDetectService.instance.setEnabled(v);
                      if (mounted) setState(() {});
                    }
                  : null,
              activeThumbColor: AppColors.primary,
              title: const Text('检测到支付时提示我',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(
                svc.permissionGranted ? '关闭后不会再弹出确认框' : '需先开启通知使用权',
                style: const TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('弹出方式'),
          _card([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        svc.canOverlay
                            ? Icons.bolt
                            : Icons.notifications_active_outlined,
                        size: 18,
                        color:
                            svc.canOverlay ? AppColors.primary : AppColors.warn,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          svc.canOverlay ? '付款后立即弹出' : '横幅提醒',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    svc.canOverlay
                        ? '付款或到账的瞬间，确认框会直接弹到屏幕上，不用你找 App。'
                        : '付款后屏幕顶部会弹出一条横幅，点一下就进入确认框。\n'
                            '想做到「不用点开 App、确认框直接弹到屏幕上」？'
                            '开启悬浮窗权限即可。',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSub, height: 1.6),
                  ),
                  if (!svc.canOverlay) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _openOverlaySettings,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('开启悬浮窗权限，付款立即弹出'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '注：小米/红米还需在「应用管理 → 记账」里允许「后台弹出界面」，'
                      '否则系统仍会拦截。',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.warn, height: 1.5),
                    ),
                  ],
                  if (!svc.notifyGranted && !svc.canOverlay) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _ensureNotify,
                        icon:
                            const Icon(Icons.notifications_outlined, size: 16),
                        label: const Text('允许横幅通知权限'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('工作原理'),
          _card([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _step(1, '你扫码付款后，支付宝/微信会发一条系统通知'),
                  _step(2, '本 App 读取这条通知，从中识别金额和商户'),
                  _step(3, '确认框立即弹到屏幕上（或顶部横幅提醒）'),
                  _step(4, '你点「确认记账」才会真正入库'),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '全程在本机完成，通知内容不会上传到任何服务器。',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMain,
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('常见问题'),
          _card([
            _faq(
              '付款后多久会弹出提示？',
              '开启悬浮窗权限后：付款或到账的瞬间，确认框直接弹到屏幕上。\n'
                  '没开悬浮窗权限：屏幕顶部弹一条横幅，点一下进入确认框。\n'
                  '两条路都走不通时（比如权限没给全），通知会暂存起来，'
                  '你下次打开 App 时自动补弹。',
            ),
            _divider(),
            _faq(
              '小米/红米开了悬浮窗权限还是不弹？',
              'MIUI 把「后台弹出界面」做成了独立权限：\n'
                  '设置 → 应用设置 → 应用管理 → 记账 → 权限管理 → '
                  '打开「后台弹出界面」，同时建议允许「自启动」。',
            ),
            _divider(),
            _faq(
              '为什么有时候没反应？',
              '三种可能：\n'
                  '① 支付宝/微信的通知文案变了，解析规则没跟上\n'
                  '② 系统省电策略把 App 限制了，需要加入后台白名单\n'
                  '③ 支付通知本身没弹出来（有些免密支付不发通知）',
            ),
            _divider(),
            _faq(
              '会不会重复记账？',
              '不会。同一笔支付在 3 分钟内只处理一次，'
                  '即使支付宝/微信连发多条通知也只会弹一次。',
            ),
            _divider(),
            _faq(
              '识别错了怎么办？',
              '弹窗里所有内容都可以改 —— 金额、分类、备注都能编辑。'
                  '如果实在不想记，点「略过」即可。',
            ),
            _divider(),
            _faq(
              '会不会误记营销通知？',
              '不会。「优惠券即将过期」「账单已出」「支付失败」'
                  '这类通知会被直接忽略，不会打扰你。',
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('权限说明'),
          _card([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本功能需要「通知使用权」——这是 Android 系统级权限，'
                    'App 无法自行申请，必须由你手动开启。',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textMain, height: 1.6),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '你可以随时在系统设置里关闭它，关闭后本功能立即失效。',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub, height: 1.6),
                  ),
                  if (!svc.permissionGranted) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _openSettings,
                        icon: const Icon(Icons.settings_outlined, size: 17),
                        label: const Text('去系统设置开启'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// 顶部状态卡 —— 一眼看出当前能不能用
  Widget _statusCard(PayDetectService svc) {
    final ok = svc.permissionGranted && svc.enabled;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ok
              ? [AppColors.primary, const Color(0xFF00A383)]
              : [AppColors.textSub, AppColors.textSub.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                ok ? '已开启' : '未开启',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ok
                ? (svc.canOverlay
                    ? '支付宝/微信付款后，确认框立即弹到屏幕上'
                    : '支付宝/微信付款后，顶部横幅提醒你确认记账')
                : '需要开启「通知使用权」才能感应支付',
            style: const TextStyle(
                fontSize: 12.5, color: Colors.white70, height: 1.5),
          ),
          if (!ok) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: _busy ? null : _openSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: Text(
                  _busy ? '正在打开…' : '去开启',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: AppColors.divider),
      );

  Widget _step(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textMain, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _faq(String q, String a) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          const SizedBox(height: 6),
          Text(a,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSub, height: 1.65)),
        ],
      ),
    );
  }
}
