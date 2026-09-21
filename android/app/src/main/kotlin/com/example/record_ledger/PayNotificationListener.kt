package com.example.record_ledger

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject

/**
 * 支付通知监听服务
 *
 * 监听支付宝 / 微信的通知，把标题和正文交给 Dart 层解析。
 *
 * 通知到达时的三级分发策略：
 *   1. App 在前台（dartReady）—— MethodChannel 直推，Flutter 弹确认框
 *   2. App 不在前台但有「悬浮窗权限」—— 直接 startActivity 把确认框拉到屏幕上
 *      （Android 10+ 禁止后台弹界面，但持有 SYSTEM_ALERT_WINDOW 的应用被系统豁免）
 *   3. 以上都不行 —— 发一条高优先级 heads-up 横幅通知，用户点击后直达确认框
 *
 * 注意几个现实约束：
 * 1. 通知使用权必须由用户在系统设置里手动开启，无法通过代码申请
 * 2. 国产 ROM 的省电策略可能杀掉本服务，需要用户加白名单
 * 3. MIUI 等 ROM 的「后台弹出界面」是独立权限，悬浮窗权限不一定够用
 * 4. 支付宝/微信的通知文案随时可能变，解析规则在 Dart 层维护
 */
class PayNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PayNotify"

        /** heads-up 通知的渠道 id 与 id 种子 */
        private const val CHANNEL_ID = "pay_detect"
        private var notifyIdSeed = 7000

        /** 我们关心的包名 */
        private val WATCHED = setOf(
            "com.eg.android.AlipayGphone", // 支付宝
            "com.tencent.mm",              // 微信
        )

        /**
         * 缓存最近收到的通知。
         *
         * 为什么要缓存？因为通知到达时 Flutter 引擎可能还没启动
         * （App 在后台被杀掉了）。缓存下来，等 Dart 层连上来时一起补发。
         */
        private val pending = ArrayDeque<JSONObject>()
        private const val MAX_PENDING = 50

        /** 当前是否已有 Dart 侧连接（Dart 在前台时为 true） */
        @Volatile
        var dartReady = false

        /** 取出并清空缓存 */
        @Synchronized
        fun drainPending(): List<JSONObject> {
            val out = pending.toList()
            pending.clear()
            return out
        }

        /**
         * 通知使用权是否已开启
         *
         * 这个判断在国产 ROM 上不一定 100% 准确，
         * 所以只作为「给用户看的提示」，不作为硬性门禁。
         */
        fun isPermissionGranted(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false

            val me = ComponentName(context, PayNotificationListener::class.java)
            return flat.split(":").any {
                val cn = ComponentName.unflattenFromString(it)
                cn != null && cn == me
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        val pkg = notification.packageName ?: return

        // 只关心支付宝和微信
        if (pkg !in WATCHED) return

        // 忽略自己发的通知（避免自触发循环）
        if (pkg == packageName) return

        val payload = extractPayload(notification.notification, pkg) ?: return

        Log.d(TAG, "捕获支付通知: $pkg -> ${payload.optString("title")} | ${payload.optString("body")}")

        if (dartReady) {
            // Dart 层在线（App 前台），直接转发，Flutter 弹确认框
            MainActivity.sendPayNotification(payload)
            return
        }

        // Dart 不在线：先缓存（打开 App 时会补发，双保险），再想办法把用户叫回来
        synchronized(PayNotificationListener::class.java) {
            if (pending.size >= MAX_PENDING) pending.removeFirst()
            pending.addLast(payload)
        }

        if (canDrawOverlays()) {
            // 有悬浮窗权限：系统豁免后台启动限制，直接把确认框拉到屏幕上
            launchApp(payload)
        } else {
            // 降级：发 heads-up 横幅通知，用户点击后直达确认框
            postHeadsUp(payload)
        }
    }

    /** 从通知里抽出标题、正文、时间 */
    private fun extractPayload(n: Notification, pkg: String): JSONObject? {
        val extras = n.extras ?: return null

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""

        // 有些通知把内容放在 subText 或大文本里
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""

        // 合并所有可能的文本来源
        val body = listOf(text, subText, bigText)
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString(" ")

        // 标题和正文都空，说明这条通知没有可用信息
        if (title.isEmpty() && body.isEmpty()) return null

        return JSONObject().apply {
            put("package", pkg)
            put("title", title)
            put("body", body)
            put("postTime", n.`when`)
        }
    }

    // ---------------- 把用户叫回来的两条路 ----------------

    /** 悬浮窗权限（显示在其他应用上层）是否已授予 */
    private fun canDrawOverlays(): Boolean {
        return try {
            Settings.canDrawOverlays(this)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 直接拉起 App —— 需要悬浮窗权限做系统豁免。
     *
     * 拉起后 MainActivity 从 intent extra 里取出 payload，
     * Flutter 就绪后自动弹确认框。
     * 失败时（部分 ROM 仍有自己的后台弹窗限制）降级为横幅通知。
     */
    private fun launchApp(payload: JSONObject) {
        try {
            val i = packageManager.getLaunchIntentForPackage(packageName) ?: run {
                postHeadsUp(payload)
                return
            }
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            i.putExtra(MainActivity.EXTRA_PAY_PAYLOAD, payload.toString())
            startActivity(i)
            Log.d(TAG, "已通过悬浮窗豁免拉起 App")
        } catch (e: Exception) {
            Log.w(TAG, "拉起 App 失败，降级为横幅通知: ${e.message}")
            postHeadsUp(payload)
        }
    }

    /**
     * 发一条高优先级横幅通知（heads-up）。
     *
     * 不需要悬浮窗权限，但 Android 13+ 需要 POST_NOTIFICATIONS 运行时权限；
     * 没有就静默放弃 —— 反正通知已缓存，用户打开 App 时会补发。
     */
    private fun postHeadsUp(payload: JSONObject) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.d(TAG, "无通知权限，跳过横幅（已缓存，打开 App 补发）")
            return
        }

        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            ensureChannel(nm)

            val src = when (payload.optString("package")) {
                "com.eg.android.AlipayGphone" -> "支付宝"
                "com.tencent.mm" -> "微信"
                else -> "支付"
            }
            val title = payload.optString("title").ifEmpty { "检测到一笔支付" }
            val body = payload.optString("body")

            // 点击横幅 → 打开 App 并带上 payload，Flutter 直接弹确认框
            val open = packageManager.getLaunchIntentForPackage(packageName)!!.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(MainActivity.EXTRA_PAY_PAYLOAD, payload.toString())
            }
            val pi = PendingIntent.getActivity(
                this, notifyIdSeed, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }

            val n = builder
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle("记账 · $src")
                .setContentText(if (body.isEmpty()) title else "$title  $body")
                .setAutoCancel(true)
                .setContentIntent(pi)
                .setDefaults(Notification.DEFAULT_ALL) // 声音+振动是 heads-up 弹出的必要条件
                .build()

            nm.notify(notifyIdSeed++, n)
            Log.d(TAG, "已发出 heads-up 横幅通知")
        } catch (e: Exception) {
            Log.w(TAG, "发横幅通知失败: ${e.message}")
        }
    }

    /** 建通知渠道（Android 8+）。IMPORTANCE_HIGH 才会 heads-up 弹出。 */
    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= 26 &&
            nm.getNotificationChannel(CHANNEL_ID) == null
        ) {
            val ch = NotificationChannel(
                CHANNEL_ID, "支付提醒", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "检测到支付宝/微信付款或收款时提醒"
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "通知监听已连接")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "通知监听已断开")
        dartReady = false
    }
}
