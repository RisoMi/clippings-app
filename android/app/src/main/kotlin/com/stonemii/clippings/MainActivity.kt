package com.stonemii.clippings

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 原生桥：
 * 1) 接收系统分享（ACTION_SEND / SEND_MULTIPLE），把文本或图片交给 Dart；
 * 2) 提供应用私有目录路径；
 * 3) 把导出的 Markdown / TXT / ZIP 通过 FileProvider 分享出去。
 *
 * 关键设计：分享内容是「暂存 + 通知」，由 Dart 主动来取。
 * 不在 onNewIntent 里直接塞 payload，是因为 Dart 侧 handler 未注册时
 * invokeMethod 会静默丢弃，那次分享就永久丢了。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.stonemii.clippings/bridge"
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDir" -> result.success(filesDir.absolutePath)

                "takePendingShare" -> {
                    val payload = pendingShare
                    pendingShare = null
                    result.success(payload)
                }

                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime") ?: "text/plain"
                    val title = call.argument<String>("title")
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        result.success(shareFile(path, mime, title))
                    }
                }

                else -> result.notImplemented()
            }
        }

        // 冷启动：把启动它的分享 Intent 暂存起来，等 Dart 起来后自己来取
        collectShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!collectShare(intent)) return
        // 热启动：只发信号，内容留在 pendingShare 里等 Dart 调 takePendingShare
        channel?.invokeMethod("onShare", null)
    }

    /** 解析分享 Intent 存入 pendingShare；不是分享 Intent 时返回 false */
    private fun collectShare(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: return false
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return false

        val type = intent.type ?: "text/plain"
        val title = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""

        if (type.startsWith("image/")) {
            val uri: Uri? = if (action == Intent.ACTION_SEND_MULTIPLE) {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.firstOrNull()
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            val localPath = uri?.let { copyToPrivateDir(it) }
            if (localPath == null) {
                // 图片拿不到就退化成文本分享
                if (text.isEmpty() && title.isEmpty()) return false
                pendingShare = mapOf(
                    "type" to "text",
                    "title" to title,
                    "text" to text,
                    "url" to ""
                )
                return true
            }
            pendingShare = mapOf(
                "type" to "image",
                "title" to title,
                "text" to text,
                "url" to "",
                "imagePath" to localPath
            )
            return true
        }

        if (text.isEmpty() && title.isEmpty()) return false
        pendingShare = mapOf(
            "type" to "text",
            "title" to title,
            "text" to text,
            "url" to ""
        )
        return true
    }

    /** 把分享进来的图片复制到私有目录，避免原 Uri 授权过期 */
    private fun copyToPrivateDir(uri: Uri): String? {
        return try {
            val dir = File(filesDir, "share_incoming").apply { mkdirs() }
            val target = File(dir, "shared_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun shareFile(path: String, mime: String, title: String?): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!title.isNullOrEmpty()) putExtra(Intent.EXTRA_SUBJECT, title)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, "发送到"))
            true
        } catch (e: Exception) {
            false
        }
    }
}
