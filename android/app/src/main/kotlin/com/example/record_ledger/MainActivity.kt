package com.example.record_ledger

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "record_ledger/pay"

        /** intent extra 的 key：从后台唤起/横幅通知带过来的支付数据 */
        const val EXTRA_PAY_PAYLOAD = "pay_payload"

        /**
         * 静态引用，供 PayNotificationListener 回调时使用。
         *
         * 通知服务是系统托管的，可能在 Activity 不存在时收到通知，
         * 所以这里必须做空判断。
         */
        @Volatile
        private var currentChannel: MethodChannel? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * 从启动 intent 里读出来、还没被 Dart 取走的支付数据。
         * 场景：App 被悬浮窗豁免/横幅通知拉起时，Flutter 引擎还在启动，
         * 先存着，等 Dart 调 ready 时一起给它。
         */
        @Volatile
        private var launchPayload: String? = null

        /** 通知服务 → Flutter：把捕获到的支付通知推过去 */
        fun sendPayNotification(payload: JSONObject) {
            mainHandler.post {
                try {
                    currentChannel?.invokeMethod("onPayNotification", payload.toString())
                } catch (_: Exception) {
                    // Flutter 侧可能已经销毁，忽略即可
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readLaunchPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readLaunchPayload(intent)

        // App 已经在运行（比如点横幅通知时它在后台）：
        // Dart 在线就直接推过去，不用等它下次调 ready
        val p = launchPayload
        if (p != null && PayNotificationListener.dartReady) {
            launchPayload = null
            try {
                sendPayNotification(JSONObject(p))
            } catch (_: Exception) {
            }
        }
    }

    /** 从 intent 里取出支付数据，取完即清，避免旋屏重建时重复消费 */
    private fun readLaunchPayload(intent: Intent?) {
        val s = intent?.getStringExtra(EXTRA_PAY_PAYLOAD) ?: return
        launchPayload = s
        intent.removeExtra(EXTRA_PAY_PAYLOAD)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        currentChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {

                /** 查询通知使用权是否已开启 */
                "hasPermission" -> {
                    result.success(
                        PayNotificationListener.isPermissionGranted(this)
                    )
                }

                /** 跳转到系统的通知使用权设置页 */
                "openSettings" -> {
                    result.success(openNotificationListenerSettings())
                }

                /**
                 * Dart 侧就绪（进入前台）：
                 * 把缓存的通知 + 启动参数里的通知一次性给它
                 */
                "ready" -> {
                    PayNotificationListener.dartReady = true
                    val arr = JSONArray()
                    PayNotificationListener.drainPending().forEach { arr.put(it) }
                    launchPayload?.let {
                        try {
                            arr.put(JSONObject(it))
                        } catch (_: Exception) {
                        }
                        launchPayload = null
                    }
                    result.success(arr.toString())
                }

                /** Dart 侧不可见（App 进入后台）：通知改走唤起/横幅路径 */
                "pause" -> {
                    PayNotificationListener.dartReady = false
                    result.success(null)
                }

                /** 悬浮窗权限（用于豁免后台弹界面限制，付款时立即弹出确认框） */
                "canDrawOverlays" -> {
                    result.success(
                        try {
                            Settings.canDrawOverlays(this)
                        } catch (_: Exception) {
                            false
                        }
                    )
                }

                /** 跳转到悬浮窗权限设置页 */
                "openOverlaySettings" -> {
                    val ok = tryStart(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    )
                    result.success(ok)
                }

                /**
                 * 通知权限（Android 13+ 发 heads-up 横幅需要）。
                 * 返回 true 表示已有权限；false 表示没有（已顺带发起系统请求弹窗）。
                 */
                "ensureNotifyPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        try {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001
                            )
                        } catch (_: Exception) {
                        }
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }

                /** 只查询通知权限，不发起请求 */
                "hasNotifyPermission" -> {
                    result.success(
                        Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        currentChannel = null
        PayNotificationListener.dartReady = false
        super.onDestroy()
    }

    /**
     * 打开「通知使用权」设置页。
     *
     * 不同 ROM 的入口不一样，这里按优先级逐个尝试，
     * 实在打不开就退回应用详情页，让用户自己找。
     */
    private fun openNotificationListenerSettings(): Boolean {
        val candidates = listOf(
            // 原生 Android
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
            // 部分 ROM 用这个
            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"),
        )

        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (tryStart(intent)) return true
        }

        // 退回：应用详情页，用户可以从「权限」里找
        return tryStart(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    private fun tryStart(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
