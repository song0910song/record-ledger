# 记账 v1.2.0

一个**纯本地离线**的安卓记账 App。预算管控版，界面清爽浅色，记完立刻看到预算进度。

**Flutter 3.0 · Android 5.0+ · 无网络权限 · 无广告无账号**

![界面预览](截图/界面预览.png)

> **v1.2.0 更新**：**总预算现在可以自己设了**（以前是各分类额度自动相加，设不了）。
> 分类预算改成**按需添加** —— 只显示你真正在管的分类，不再把十个分类全铺出来。
>
> **v1.1.1 改进**：支付感应**真正即时** —— 付款或到账的**瞬间**确认框直接弹到屏幕上，
> 不再需要先打开 App。
>
> **v1.1.0 新增**：**支付自动感应** —— 支付宝 / 微信付款或收款时，App 自动弹出确认框，
> 金额、分类、备注都已预填好，你点一下「保存」就记完了。
>
> **v1.0.2 更新**：记完一笔后，账单 / 统计 / 预算 / 我的四个页面**全部自动刷新**。
>
> **v1.0.1 修复**：v1.0.0 安装后闪退，原因是 Android 工程漏配 Kotlin 编译插件。
> 详见文末「版本记录」。

---

## 从源码构建

```bash
flutter pub get
flutter build apk --release --no-tree-shake-icons
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

需要 **Flutter 3.0** 和 **JDK 17**（JDK 20+ 会报 `Unsupported class file major version 64`）。

> **为什么必须带 `--no-tree-shake-icons`？**
> 分类图标存在数据库里，代码中通过 `IconData(codePoint, ...)` 动态构造（见 `lib/models/models.dart`）。
> 编译期无法推断用到哪些图标，图标树摇会报错或漏字形。加这个参数直接打包完整字体（多约 1.4MB），最稳妥。

国内网络构建时加上镜像环境变量：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 一、安装到手机

1. 把 `记账-v1.2.0.apk` 传到手机（微信文件传输 / QQ / 数据线均可）
2. 手机上点开这个 apk 文件
3. 系统会提示「禁止安装未知来源应用」→ 点**设置** → 允许来自此来源
4. 继续安装 → 桌面出现绿色图标「记账」

> 支持 Android 5.0 及以上（minSdk 21）。  
> 已内置 arm64-v8a / armeabi-v7a / x86_64 三种架构，绝大多数手机都是 arm64，直接装即可。

**从旧版升级**：直接安装即可覆盖，**数据会保留**（包名和签名都没变）。
若系统提示签名冲突，先卸载旧版再装 —— 但那样会清空数据，建议先「我的 → 导出 CSV」备份。

**为什么会被拦截？** 因为这个 APK 是**自签名**的（不是从应用商店下载的）。自用完全没问题，签名只是为了系统能识别应用身份。

---

## 二、30 秒上手

```
打开 App
  ↓
点底部中间的大绿加号「+」
  ↓
输金额（自带数字键盘，不用调系统输入法）
  ↓
点一个分类（比如"餐饮"）
  ↓
点「保存」
  ↓
回到首页 —— 顶部立刻能看到本月预算进度条
```

**核心循环就这一个**：记一笔 → 立刻看到还剩多少 → 心里有数。

---

## 三、四个页面分别干什么

| 页面     | 作用       | 关键信息                           |
| ------ | -------- | ------------------------------ |
| **账单** | 看这个月花了多少 | 本月结余大数字 + **预算进度条** + 按日分组的流水  |
| **统计** | 钱花在哪了    | 三个克制视图：支出环形图 / 分类排行 / 近 6 月柱状图 |
| **预算** | 事前规划     | **总预算** + 按需设置的分类额度 + **今天还可花多少钱** |
| **我的** | 数据管理     | 导出 CSV/JSON、管理分类、支付感应设置、清空数据   |

### 预算进度条的颜色规则

这是整个 App 的核心设计，一眼就能判断状态：

| 颜色             | 条件        | 含义       |
| -------------- | --------- | -------- |
| 🟢 绿 `#00B894` | 已花 < 80%  | 健康，放心花   |
| 🟠 橙 `#F5A623` | 已花 ≥ 80%  | 接近上限，收着点 |
| 🔴 红 `#E84C3D` | 已花 > 100% | 超支了      |

预算页顶部还有一句「**今天还可花 ¥113**」，算法是：

```
今日可用额度 =（总预算 - 当月已花）/ 本月剩余天数
```

把月度预算拆成每天能花的钱，比一个笼统的总数更有约束力。

---

## 四、预算怎么用（v1.2.0 重做）

预算分两层，**互不干扰，各管一段**：

### 总预算 —— 管整体

点击预算页顶部的彩色卡片就能设，比如「这个月最多花 7000」。

- **按月独立**：9 月设了 7000，10 月不设就自动沿用 7000
- 界面上会标出「沿用自 2026年8月」，数字从哪来的看得清
- 想给某个月单独设不同额度，切到那个月改一下就行

> 关于「沿用」的规则：只**往前找**最近一次设置。
> 给 12 月设了额度不会穿越回来影响 9 月 —— 否则你为年底设的数会莫名改掉当月预算。

### 分类预算 —— 管细节

**只显示你设过额度的分类**，没设的不占地方。

比如你只想管住「餐饮」和「购物」，那列表里就只有这两条，剩下八个分类不会铺在屏幕上。
想给新分类设额度，点底部「**+ 添加分类预算**」，弹出分类选择器。

> **为什么要这么改？** 之前的版本把十个支出分类全列出来，每个都写着"设置额度"。
> 看着满屏待办事项，反而不知道从哪下手，最后干脆一个都不设。
> 现在只列你在管的，加的时候主动选 —— 决策成本低得多。

### 两层预算的关系

**完全独立**：总预算是总预算，分类额度是分类额度，两者不互相约束。

给分类设额度时，如果累计超过总预算，只会在标题旁边提示「已分配 8,200 / 7,000」，**但不阻止保存**。

理由是：分类额度更像「意图分配」，月初拍脑袋分出来的数字经常要调。硬拦着只会让人放弃设分类预算，反而失去意义。总预算才是真正的闸门。

### 首页的进度条用哪个口径？

**总预算 vs 当月全部支出** —— 不是「只有设了额度的分类」。

这点很关键：如果你只给「餐饮」设了额度，那买衣服花的钱也必须计入进度条。
否则进度条会一直显得很宽松，等你发现的时候已经严重超支了。

---

## 五、支付自动感应（v1.1.0 新增，v1.1.1 增强）

支付宝 / 微信付完款，通知栏弹出「支付成功 ¥28.50」的**那一刻**，确认框就弹到你面前 ——
不用你打开记账 App，不用输金额。

### 弹出方式（v1.1.1 核心改进）

通知到达时，App 按三级策略把确认框送到你面前：

```
支付宝/微信付款通知到达
  ↓
① App 正在前台？
   是 → 直接弹确认框
  ↓ 否
② 有「悬浮窗权限」？
   是 → 付款瞬间，确认框直接弹到屏幕上（不用你找 App）
  ↓ 否
③ 发一条高优先级横幅通知 → 点一下横幅，直达确认框
  ↓ （连横幅权限都没有）
  通知暂存，下次打开 App 自动补弹
```

**想要 ② 的效果（推荐）**：App 里「我的 → 支付自动记账 → 弹出方式 → 开启悬浮窗权限」。
这是 Android 的系统机制 —— 10.0 之后系统禁止后台 App 自行弹出界面，
但**持有悬浮窗权限的应用会被豁免**。你只需要开一次。

| 手机 | 悬浮窗权限路径 |
|---|---|
| 原生 Android | 设置 → 应用 → 特殊应用权限 → 显示在其他应用上层 |
| 小米 / Redmi | 设置 → 应用管理 → 记账 → 权限管理 → 显示悬浮窗；**另需打开「后台弹出界面」** |
| 华为 / 荣耀 | 设置 → 应用 → 应用管理 → 记账 → 权限 → 悬浮窗 |
| OPPO / 一加 | 设置 → 应用管理 → 记账 → 权限管理 → 悬浮窗 |
| vivo / iQOO | 设置 → 应用管理 → 记账 → 权限 → 悬浮窗 |

> **小米/红米特别注意**：MIUI 把「后台弹出界面」做成了独立权限，
> 光开悬浮窗不够，两个都要开，并建议允许「自启动」。

### 效果长这样

```
你扫码付了 28.5 元买奶茶
  ↓
支付宝弹出通知："支付成功 ¥28.50"
  ↓（同一秒）
记账确认框直接弹到屏幕上：
  ┌──────────────────────────────┐
  │  检测到一笔支出                │
  │  ¥ 28.50                      │
  │  分类：餐饮  [可改]            │
  │  备注：支付成功 ¥28.50         │
  │  来源：支付宝                  │
  │  ────────────────────────────  │
  │   [ 忽略 ]      [ 保存 ]       │
  └──────────────────────────────┘
  ↓
点「保存」→ 记完了，账单页立刻更新
```

**它不会偷偷记账** —— 每一笔都要你点确认。识别错了就点「忽略」。

### 怎么开启

这是 Android 的系统级权限，**必须你手动开一次**，任何 App 都无法用代码申请：

> **设置 → 应用 → 特殊应用权限 → 通知使用权 → 找到「记账」→ 打开**

不同手机路径略有差异，几个常见 ROM：

| 手机 | 路径 |
|---|---|
| 原生 Android | 设置 → 应用 → 特殊应用权限 → 通知使用权 |
| 小米 / Redmi | 设置 → 应用设置 → 应用管理 → 记账 → 通知使用权 |
| 华为 / 荣耀 | 设置 → 应用 → 应用管理 → 记账 → 通知使用权 |
| OPPO / 一加 | 设置 → 应用管理 → 记账 → 通知使用权 |
| vivo / iQOO | 设置 → 应用管理 → 记账 → 权限管理 → 通知使用权 |

**懒人做法**：打开 App →「我的」→「支付自动记账」→ 点「去开启」，
App 会直接跳到系统设置页，你只要找到「记账」打开开关就行。

### 它是怎么工作的

```
支付宝/微信发通知
      ↓
PayNotificationListener（安卓系统服务，常驻）
      ↓  只挑这两个 App 的通知，其他一律不看
      ├─ App 在前台 → MethodChannel → Flutter 弹确认框
      ├─ 有悬浮窗权限 → startActivity 把确认框拉到屏幕上
      └─ 都没有 → 发 heads-up 横幅，点击直达确认框
      ↓
PayDetectService（Dart 层调度：去重 / 分类匹配 / 排队）
      ↓
PayConfirmSheet（弹窗，预填好金额分类，等你点确认）
      ↓
你点「保存」→ 写进本地数据库
```

**几个关键设计**：

- **只监听支付宝和微信** —— 包名白名单硬编码，其他 App 的通知连读都不读
- **前后台状态同步** —— App 退到后台时 Dart 主动告诉原生层"我看不见了"，
  原生层收到通知后改走唤起/横幅路径，实现付款即弹
- **3 分钟去重** —— 同一条通知可能被系统重复推送，用「包名+金额+标题+正文」做指纹，3 分钟内只处理一次
- **缓存补发双保险** —— 通知到达时无论走哪条弹出路径，都会先存进本地缓存（最多 50 条）。
  就算唤起失败、横幅也没看到，下次打开 App 照样补弹，不会漏记
- **解析不了就保留原文** —— 实在认不出的通知，弹窗里会显示原始文案，你自己判断是不是一笔账

### 它认得出什么

**支出**（会弹确认框）：支付成功、付款、消费、扣款、转出、扣费……

**收入**（会弹确认框，方向自动识别）：收款、收到、退款、已到账、转入、红包到账……

**直接忽略**（不打扰你）：零钱通收益、余额宝收益、优惠券到账、账单已出、还款提醒、验证码、待支付、支付失败、交易关闭、已取消……

**自动猜分类**：根据商户名猜，比如「星巴克 / 麦当劳 / 美团」→ 餐饮，「滴滴 / 地铁 / 加油」→ 交通，「京东 / 淘宝」→ 购物。猜错了在弹窗里改一下就行。

### 已知限制（说在明处）

- **「立即弹出」依赖悬浮窗豁免** —— 这是 Android 提供的唯一合法通道。
  不给悬浮窗权限就降级为横幅提醒（体验也不差，就是多点一下）
- **MIUI 有额外的「后台弹出界面」权限** —— 小米/红米用户需要单独打开，
  这是 MIUI 自己的限制，App 无法代为申请
- **国产 ROM 可能杀掉后台服务** —— 需要在「电池 / 省电策略」里把「记账」设为**不受限制**，
  并允许自启动，否则息屏久了可能收不到通知
- **通知文案会变** —— 支付宝和微信随时可能改文案格式，解析规则在 `lib/services/pay_parser.dart` 里集中维护，改一个文件就行
- **不是 100% 准确** —— 有些通知（比如「您有一笔待支付订单」）语义模糊，所以设计成**必须你确认**，而不是自动记账
- **只有支付宝和微信** —— 云闪付、银行 App 的通知暂不支持

### 关掉它

「我的」→「支付自动记账」→ 关掉总开关。
彻底不想要的话，去系统设置里关掉「通知使用权」即可 —— 关掉后 App 完全收不到任何通知。

---

## 六、数据安全

- **无网络权限** —— 代码里根本没申请 `INTERNET` 权限，想上传也上传不了
- **无广告、无账号、无登录**
- 所有数据存在手机本地的 SQLite 数据库里
- 换手机时：用「我的 → 导出 CSV」把数据导出来，Excel 直接能打开
- **导出功能永久免费** —— 不搞"导出要开会员"那套

---

## 七、源码结构

```
源码/
├── lib/
│   ├── main.dart                     入口
│   ├── models/models.dart            4 个数据模型
│   ├── services/
│   │   ├── db.dart                   SQLite 数据层（含导出）
│   │   ├── data_bus.dart             数据变更广播器（页面自动刷新）
│   │   ├── pay_parser.dart           支付通知解析器（纯函数，可单测）
│   │   └── pay_detect_service.dart   支付感应调度（去重/分类/排队）
│   ├── theme/app_theme.dart          设计令牌（颜色全在这）
│   ├── utils/fmt.dart                金额/日期格式化
│   └── screens/
│       ├── home_shell.dart           四 Tab 框架 + 中心 FAB
│       ├── home_page.dart            账单页
│       ├── add_txn_page.dart         记一笔（核心交互）
│       ├── stats_page.dart           统计页
│       ├── budget_page.dart          预算页
│       ├── settings_page.dart        我的页
│       ├── txn_detail_page.dart      账单详情/编辑/删除
│       ├── category_manage_page.dart 分类管理
│       ├── pay_confirm_sheet.dart    支付确认弹窗
│       └── pay_detect_settings_page.dart  支付感应设置/权限引导
├── android/
│   └── app/src/main/kotlin/com/example/record_ledger/
│       ├── MainActivity.kt           入口 Activity + MethodChannel
│       └── PayNotificationListener.kt 通知监听服务
├── test/
│   ├── data_bus_test.dart            广播机制测试
│   ├── pay_parser_test.dart          支付解析测试（34 条）
│   └── total_budget_test.dart        总预算沿用规则测试（17 条）
├── pubspec.yaml                      依赖清单
└── README.md
```

### 数据库表结构

| 表 | 存什么 | 说明 |
|---|---|---|
| `category` | 分类 | 名称 / 图标 / 颜色 / 收支类型 / 排序 |
| `txn` | 账单流水 | 金额 / 类型 / 分类 / 备注 / 时间戳 |
| `budget` | **分类**月度额度 | `UNIQUE(category_id, month)` |
| `total_budget` | **总**月度预算 | `UNIQUE(month)`，v1.2.0 新增 |

`budget` 和 `total_budget` 是两张独立的表 —— 总预算不属于任何分类，
塞进 `budget` 表得用 `category_id = -1` 之类的魔法值，查询和迁移都要特判。

### 技术栈

- **Flutter 3.0** / Dart 2.17
- **sqflite** —— 本地 SQLite
- **fl_chart** —— 环形图与柱状图
- **share_plus** —— 导出时调系统分享
- **intl** —— 金额千分位与中文日期
- **NotificationListenerService** —— 支付通知感应（安卓原生）
- **MethodChannel** —— Kotlin ↔ Dart 通信

---

## 八、想自己改点什么

### 改主色调

打开 `lib/theme/app_theme.dart`，改 `AppColors` 里的常量：

```dart
static const Color primary = Color(0xFF00B894);  // 换成你喜欢的色
```

改完重新打包即可，全 App 的配色会跟着变。

### 加一个自己的分类

不用改代码 —— 打开 App 的「我的 → 管理分类」，直接加。  
内置了 33 个图标 + 8 色调色盘可选。

### 改预置分类（首次安装时就有）

编辑 `lib/services/db.dart` 里的 `_seedCategories()` 方法：

```dart
final expenses = <List<dynamic>>[
  ['餐饮', Icons.restaurant.codePoint, c[3], 0],
  ['交通', Icons.directions_bus.codePoint, c[1], 1],
  // 在这里加你自己的
];
```

### 重新打包 APK

```bash
cd 源码
flutter pub get

# 注意：必须带 --no-tree-shake-icons
flutter build apk --release --no-tree-shake-icons
# 产物在 build/app/outputs/flutter-apk/app-release.apk
```

> **为什么要加 `--no-tree-shake-icons`？**  
> 分类图标存在数据库里，代码里通过 `IconData(codePoint, ...)` 动态构造  
> （见 `lib/models/models.dart`）。编译期无法推断用到哪些图标，  
> 图标树摇会报错或漏掉字形。加这个参数直接打包完整字体（多约 1.4MB），最稳妥。

> 需要装 Flutter SDK 和 **JDK 17**（JDK 20+ 会报 `Unsupported class file major version 64`）。  
> 如果构建时卡在下载依赖，加上国内镜像环境变量：
>
> ```bash
> export PUB_HOSTED_URL=https://pub.flutter-io.cn
> export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
> ```

---

## 九、已知边界

- **只做了安卓版** —— 没做 iOS。iOS 打包需要 Mac + 苹果开发者账号（￥688/年）
- **没有云同步** —— 这是刻意的设计选择。数据只在你手机里，不经过任何服务器
- **没有多账本** —— 单账本，够用且不复杂
- **没有记账提醒** —— 需要的话可以加，但自用场景容易变成骚扰

---

## 十、为什么这么设计

调研了一圈市面上的记账 App，发现两类问题：

1. **功能堆砌型**（随手记、鲨鱼记账）—— 开屏广告、会员弹窗、社区、理财推荐，  
   记一笔要跳三层页面
2. **极简到没用型** —— 只记不分析，记完还是不知道钱花哪了

所以这个 App 只解决一件事：**让"这个月还能花多少"随时可见**。

具体的取舍：

- **不做开屏广告、不做会员** —— 自用工具，没有必要
- **不做云同步** —— 省掉账号体系和服务器，隐私也更好
- **统计只保留 3 个视图** —— 图表多了反而没人看
- **记账流程压到 3 步（输金额→点分类→保存）** —— 记账这件事，摩擦越小越容易坚持
- **预算进度条放首页顶部** —— 打开 App 第一眼就能看到，不用点进去

---

## 十一、版本记录

### v1.2.0 — 总预算可独立设置 + 分类预算按需添加

**用户反馈**：预算页的总预算设不了；分类预算把十个分类全列出来，太乱。

**问题一：总预算设不了**

看这行代码就明白了：

```dart
double get _totalBudget => _views.fold(0.0, (a, b) => a + b.budget);
```

总预算是**各分类额度的被动求和**，根本不是一个可存储的值。
所以界面能显示 ¥7,000，但没有任何地方能改它 —— 只有给分类逐个设额度，总数才会变。

**修复**：新建 `total_budget` 表独立存储。

```sql
CREATE TABLE total_budget(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount REAL NOT NULL,
  month TEXT NOT NULL UNIQUE
)
```

> **为什么不复用 `budget` 表？** 那张表的语义是「某分类的额度」，
> 主键和外键都指向 `category_id`。总预算不属于任何分类，
> 混进去得用 `category_id = -1` 这类魔法值，查询、导出、迁移处处要特判，得不偿失。

数据库版本 1 → 2，`onUpgrade` 里补建新表。**老用户升级不会丢数据** ——
账单、分类、已有分类额度全部保留，只是总预算初始为空，需要你自己设一次。

**「下月自动沿用」的实现**：

```sql
SELECT amount, month FROM total_budget
WHERE month <= ? ORDER BY month DESC LIMIT 1
```

只**往前**找最近一次设置。为什么不取绝对值最接近的？因为那样给 12 月设了额度会穿越回来影响 9 月，太反直觉。

返回值带上来源月份，界面显示「沿用自 2026年8月」，让用户知道这个数字哪来的。

**问题二：分类预算列表太乱**

改前：遍历全部分类，每个都渲染一张卡片，没设额度的显示「设置额度」。

改后：
- 列表只渲染 `budget > 0` 的分类
- 底部常驻「**+ 添加分类预算**」，点击弹出分类选择器（已设的不再出现）
- 一个都没设时显示引导空状态，直接给按钮

> 这个改动的出发点：十个分类全列出来、每个都说"设置额度"，
> 视觉上像十件待办事项，反而让人不知道从哪下手，最后干脆一个都不设。
> 只列在管的、加的时候主动选，决策成本低得多。

**问题三（顺带修正）：首页进度条口径错了**

改前统计的是「**设了额度的分类**的支出之和」：

```dart
double get _totalSpentInBudget =>
    _budgets.keys.fold(0.0, (a, k) => a + (_spentByCat[k] ?? 0));
```

后果：只给「餐饮」设了额度，那买衣服花的钱不计入进度。
进度条会一直显得很宽松，等发现时已经严重超支 —— 恰恰是预算功能最该避免的事。

改后统一用 `_expense`（当月全部支出），与预算页口径一致。

**改动清单**：

| 文件 | 改动 |
|---|---|
| `lib/services/db.dart` | 新增 `total_budget` 表 + 版本迁移；新增 `setTotalBudget` / `totalBudgetExact` / `totalBudgetOf` / `hasOwnTotalBudget`；`clearAll` 补清总预算 |
| `lib/screens/budget_page.dart` | 重写：总预算卡片可点击编辑；分类列表只显示已设额度；新增分类选择器、空状态引导、分配比例提示；抽出复用的金额输入弹窗 |
| `lib/screens/home_page.dart` | 进度条改用总预算；修正统计口径 |
| `test/total_budget_test.dart` | **新增** —— 17 条测试覆盖沿用规则、进度口径、分配提示 |

**测试覆盖的关键边界**（沿用规则容易写错，重点测）：

```
✓ 当月有设置 —— 用当月的，来源就是当月
✓ 当月没设 —— 沿用上个月
✓ 跨多个月 —— 沿用最近的那次，不是最早的
✓ 当月有设置时不看历史值
✓ 只看过去 —— 未来月份的设置不影响当前月
✓ 只有未来月份的设置 —— 当前月视为未设置
✓ 完全没设过 —— 返回 0 且无来源
✓ 跨年沿用 —— 去年 12 月的值能被今年 1 月沿用
✓ 字符串比较在 yyyy-MM 格式下等价于时间先后
✓ 未设总预算时进度为 0，界面不显示进度条
✓ 80% 是「接近上限」的阈值
✓ 分类额度之和超出总预算 —— 提示但不阻止保存
```

**验证**：

```
flutter test     → 53 条全通过（新增 17 条）
flutter analyze  → 0 error, 0 warning
APK 校验：versionCode=6 / versionName=1.2.0
         三架构 / 签名 / 图标字体完整 / 无 INTERNET 权限
         MainActivity + PayNotificationListener 均在 dex
```

### v1.1.1 — 付款瞬间弹出，不再等打开 App

**用户反馈**：v1.1.0 的支付感应只有打开记账 App 时才弹确认框 ——
付完款还要记得去开 App，体验断了一截。

**系统约束**：Android 10+ 禁止后台应用自行弹出界面（`Background Activity Start` 限制），
这是系统级行为，任何 App 都无法绕过。但系统留了两个口子：

1. **悬浮窗权限豁免** —— 持有 `SYSTEM_ALERT_WINDOW`（显示在其他应用上层）权限的应用，
   被允许从后台启动 Activity
2. **高优先级通知** —— `IMPORTANCE_HIGH` 渠道的 heads-up 横幅，
   可以即时出现在屏幕上，点击后直达目标页面

**实现的三级分发**：

```
通知到达 PayNotificationListener
  ↓
dartReady?（Dart 上报的前后台状态）
  ├─ true  → MethodChannel 直推 → Flutter 弹确认框
  └─ false → 先写入本地缓存（补发保险）
       ↓
     canDrawOverlays()?
       ├─ true  → startActivity 直接把确认框拉到屏幕上
       │          （失败时 catch 降级为横幅）
       └─ false → postHeadsUp() 发 IMPORTANCE_HIGH 横幅
                  （Android 13+ 需 POST_NOTIFICATIONS，没有则跳过，
                   反正缓存里有，打开 App 会补弹）
```

**改动清单**：

| 文件 | 改动 |
|---|---|
| `PayNotificationListener.kt` | 通知分发改为三级策略；新增 `launchApp()`（悬浮窗豁免唤起）、`postHeadsUp()`（高优先级横幅 + NotificationChannel） |
| `MainActivity.kt` | `onCreate`/`onNewIntent` 读取 `pay_payload` extra；`ready` 时合并补发；新增 `canDrawOverlays` / `openOverlaySettings` / `ensureNotifyPermission` / `hasNotifyPermission` 四个通道方法 |
| `AndroidManifest.xml` | 新增 `POST_NOTIFICATIONS` 权限（Android 13+ 发横幅必需） |
| `pay_detect_service.dart` | 实现 `WidgetsBindingObserver`：退后台调 `pause`、回前台调 `ready` 并补发缓存；新增悬浮窗/通知权限的状态查询与引导 |
| `home_shell.dart` | **修冷启动弹窗丢失 bug**：`init()` 在 `runApp` 之前跑完，缓存通知进队列时弹窗回调还没注册。首帧渲染后主动检查队列 |
| `pay_detect_settings_page.dart` | 新增「弹出方式」区块：悬浮窗权限引导 + 横幅权限请求 + MIUI 特别提示；FAQ 重写 |

**顺带修掉的存量 bug**：

> v1.1.0 里 `PayDetectService.instance.init()` 在 `main()` 的 `runApp` **之前**调用，
> `ready` 拉回缓存通知时 `home_shell` 的 `onNewPending` 回调还没赋值，
> 冷启动补发的通知会永远躺在队列里不弹。
> v1.1.0 靠「用户切 Tab 后刷新权限」碰巧掩盖了这个问题，
> v1.1.1 的唤起链路把冷启动变成主路径，这个 bug 就藏不住了，一并修掉。

**验证**：

```
flutter test     → 36 条全通过
flutter analyze  → 0 error, 0 warning
APK 校验：
  versionCode=5 / versionName=1.1.1
  MainActivity + PayNotificationListener 均在 dex
  canDrawOverlays / openOverlaySettings / ensureNotifyPermission 符号均在 dex
  POST_NOTIFICATIONS 权限已声明
  三架构 / 签名 / 图标字体完整 / 无 INTERNET 权限
```

> **构建环境注意**：AGP 7.4 用 zipflinger 写 APK，老版本 `unzip`（Info-ZIP）
> 可能报 `cannot find zipfile directory` —— 这是工具兼容问题，不是包损坏。
> 用 `python zipfile` / `aapt` / Android 系统安装验证均正常。

### v1.1.0 — 支付自动感应

**新增能力**：支付宝 / 微信付款或收款时，App 监听系统通知，自动弹出确认框并预填好金额、分类、备注。点「保存」即完成记账。

**为什么不做成全自动**：通知文案的语义存在歧义（「您有一笔待支付订单」到底算不算账？），自动记账一旦错记，用户很难发现。所以设计成**必须人工确认**——每次感应到都弹窗，你点「保存」才写入，点「忽略」就丢弃。

**链路设计**：

```
NotificationListenerService (Kotlin)
  ↓ 只收支付宝/微信的通知，包名白名单
MethodChannel 'record_ledger/pay'
  ↓
PayDetectService (Dart)
  ↓ 去重 → 分类匹配 → 队列
PayConfirmSheet (弹窗)
  ↓ 用户确认
Db.addTxn() → DataBus.notify() → 全页面刷新
```

**几个关键实现细节**：

1. **离线缓存** —— `PayNotificationListener` 里维护一个最多 50 条的 `ArrayDeque`。App 被系统杀掉时通知照样进缓存，等 Dart 侧调 `ready` 时一次性补发。避免了「付款时 App 在后台，打开后什么都看不到」。

2. **去重指纹** —— 同一条通知系统可能重复推送多次（尤其是微信）。用 `包名 + 金额 + 标题 + 正文` 拼成指纹，3 分钟窗口内只处理一次。

3. **来源词剔除（重要缺陷修复）** —— 初版解析器把标题 `支付宝` 里的「**支付**」二字误判成支出关键词，导致**所有**支付宝通知都被判成支出，包括收款。
   修复方式：判定方向前先剔除 `支付宝`/`微信`/`微信支付`/`Alipay`/`WeChat` 等来源词，再做关键词匹配。
   这个 bug 是写单测时暴露出来的——`test/pay_parser_test.dart` 里有一条「关于 25.00 元的通知」，期望是「无法判断」，实际返回「支出」。

4. **解析失败保留原文** —— 认不出方向的通知不丢弃，弹窗里显示通知原文，让用户自己判断。宁可多问一次，不可漏记。

**改动清单**：

| 文件 | 改动 |
|---|---|
| `lib/services/pay_parser.dart` | **新增** —— 纯函数解析器，无副作用，可完整单测 |
| `lib/services/pay_detect_service.dart` | **新增** —— 调度层：去重 / 分类 / 队列 / 权限状态 |
| `lib/screens/pay_confirm_sheet.dart` | **新增** —— 支付确认底部弹窗 |
| `lib/screens/pay_detect_settings_page.dart` | **新增** —— 权限引导页（4 步说明 + FAQ） |
| `android/.../PayNotificationListener.kt` | **新增** —— 通知监听服务 |
| `android/.../MainActivity.kt` | 重写 —— 加 MethodChannel，4 个方法 |
| `android/app/src/main/AndroidManifest.xml` | 声明 service + `BIND_NOTIFICATION_LISTENER_SERVICE` |
| `lib/screens/home_shell.dart` | 监听新通知，队列化弹窗（含防重入） |
| `lib/screens/settings_page.dart` | 加「支付自动记账」入口 |
| `test/pay_parser_test.dart` | **新增** —— 34 条解析测试 |

**测试**：

```
flutter test
  ✓ DataBus 广播              (2 条)
  ✓ 来源识别
  ✓ 支出解析 / 收入解析
  ✓ 应忽略的通知（零钱通、账单提醒、验证码…）
  ✓ 解析失败场景
  ✓ 分类推荐
  ✓ 端到端：从通知到可用的记账建议
  All tests passed!  (36 条)

flutter analyze → 0 error, 0 warning
```

> **构建踩坑**：Kotlin 侧 `extractPayload(notification, pkg)` 传的是 `StatusBarNotification`，但形参声明是 `Notification`，编译报
> `Type mismatch: inferred type is StatusBarNotification but Notification was expected`。
> 改成 `notification.notification` 即可。

### v1.0.2 — 记账后自动刷新全部页面

**现象**：记完一笔回到账单页，数据没变；切到统计页、预算页，也还是记账前的旧数字。要下拉才能看到最新数据。

**根因**：四个页面用 `IndexedStack` 管理 —— 它们**一直活在内存里，只切换显示**，所以只在 `initState` 时加载一次数据，之后不会重新查询。而 `AddTxnPage` 保存后虽然 `Navigator.pop(context, true)` 返回了成功标志，但 `HomeShell` 里的 `await Navigator.push(...)` **把这个返回值丢掉了**，没有任何后续动作。

**修复方案**：在数据层加一个变更广播器（`lib/services/data_bus.dart`），所有写操作完成后自动广播，页面订阅后重载。好处是不依赖页面之间的调用关系 —— 以后加新页面，只要订阅一下就自动生效。

```
写操作                     广播                    订阅页面
─────────                ──────                ──────────
Db.addTxn()      ──┐
Db.updateTxn()   ──┤
Db.deleteTxn()   ──┼──►  DataBus.notify()  ──┬──►  HomePage.load()
Db.setBudget()   ──┤                          ├──►  StatsPage.load()
Db.addCategory() ──┤                          ├──►  BudgetPage.load()
Db.clearAll()    ──┘                          └──►  SettingsPage._loadCount()
```

**改动清单**：

| 文件 | 改动 |
|---|---|
| `lib/services/data_bus.dart` | **新增** —— 全局变更广播器 |
| `lib/services/db.dart` | 7 个写操作加 `DataBus.notify()` |
| `lib/screens/home_page.dart` | 订阅广播 + 异常保护 |
| `lib/screens/stats_page.dart` | 订阅广播 + 异常保护 |
| `lib/screens/budget_page.dart` | 订阅广播 + 异常保护 |
| `lib/screens/settings_page.dart` | 订阅广播（累计记录数） |
| `lib/screens/category_manage_page.dart` | 订阅广播 + 异常保护 |
| `lib/screens/home_shell.dart` | 记完账自动切回账单页 |
| `lib/screens/add_txn_page.dart` | 保存加异常保护 |
| `test/data_bus_test.dart` | **新增** —— 广播机制单元测试 |

**顺带改进**：记完一笔会自动切回**账单页**，这样你能立刻看到预算进度条的变化 —— 这正是当初选"记完能立刻看进度"的初衷。

**验证**：

```
flutter test
  ✓ DataBus 广播能通知所有订阅者
  ✓ 版本号随广播递增
  All tests passed!

flutter analyze
  0 errors
```

### v1.0.1 — 修复启动闪退

**现象**：安装后点开图标，闪一下就退回桌面。

**根因**：Android 工程缺少 Kotlin 编译插件配置。

细节：`android/app/build.gradle` 里没有 `apply plugin: 'kotlin-android'`，  
根 `build.gradle` 的 classpath 也没引入 `kotlin-gradle-plugin`。  
结果 `MainActivity.kt` 被构建系统完全忽略，**没有编译进 `classes.dex`**。  
而 `AndroidManifest.xml` 里把 `.MainActivity` 声明为启动入口：

```xml
<activity android:name=".MainActivity" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
</activity>
```

系统拉起这个 Activity 时找不到类定义 → `ClassNotFoundException` → 直接崩溃。

**验证方式**：解包 APK，检查 `classes.dex` 里的类：

```bash
# 修复前：只有 R / BuildConfig，没有 MainActivity
strings classes.dex | grep "record_ledger"
# 'Lcom/example/record_ledger/BuildConfig;
# "Lcom/example/record_ledger/R$attr;
# ...（无 MainActivity）

# 修复后：
strings classes.dex | grep "record_ledger/MainActivity"
# (Lcom/example/record_ledger/MainActivity;
# MainActivity.kt
```

**修复内容**：

1. `android/build.gradle` — 加入 `classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.7.22"`
2. `android/app/build.gradle` — 加入 `apply plugin: 'kotlin-android'`、  
   `kotlinOptions { jvmTarget = '1.8' }`、`sourceSets` 声明 kotlin 源目录
3. 构建时加 `--no-tree-shake-icons`，避免图标字体被错误裁剪
4. 顺带加固：`lib/main.dart` 在数据库初始化失败时显示明确的错误界面，  
   而不是让用户对着永远的转圈等待

**本次发布前校验项**：

| 检查项 | 结果 |
|---|---|
| 压缩包完整性（`unzip -t`） | 通过 |
| APK 签名（CERT.RSA / CERT.SF / MANIFEST.MF） | 通过 |
| 三架构 native 库 | arm64-v8a / armeabi-v7a / x86_64 |
| **入口类 `MainActivity` 存在于 dex** | **通过（本次修复的关键）** |
| 图标字体完整（1,614,500 字节，未裁剪） | 通过 |
| 无 `INTERNET` 权限 | 通过 |

### v1.0.0 — 首个版本

预算管控版，四个 Tab（账单 / 统计 / 预算 / 我的），纯本地 SQLite 存储。
**已知问题**：启动闪退、记账后不刷新（均已在新版修复）。

---

## 十二、发布前校验清单

每次打包后都会跑这七项：

| 检查项 | 说明 |
|---|---|
| 压缩包完整性 | `unzip -t` 无错误 |
| **入口类在 dex 中** | **v1.0.0 闪退的教训，必查** |
| APK 签名 | CERT.RSA / CERT.SF / MANIFEST.MF 齐全 |
| 三架构 native 库 | arm64-v8a / armeabi-v7a / x86_64 |
| 图标字体完整 | 1,614,500 字节（未裁剪） |
| 无 INTERNET 权限 | 兑现"数据不出手机"的承诺 |
| 单元测试 | `flutter test` 全绿 |

---

*你的数据，永远归你。*
