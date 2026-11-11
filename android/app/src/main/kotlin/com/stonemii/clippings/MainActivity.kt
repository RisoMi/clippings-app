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
 * 3) 把导出的 Markdown / TXT 通过 FileProvider 分享出去。
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

        // 冷启动：把启动它的分享 Intent 暂存起来
        collectShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectShare(intent)
        // 热启动：直接把新分享推给 Dart 层
        val payload = pendingShare
        if (payload != null) {
            channel?.invokeMethod("onShare", payload)
            pendingShare = null
        }
    }

    @Suppress("DEPRECATION")
    private fun collectShare(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val type = intent.type ?: "text/plain"
        val title = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""

        if (type.startsWith("image/")) {
            val uri: Uri? = if (action == Intent.ACTION_SEND_MULTIPLE) {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.firstOrNull()
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            val localPath = uri?.let { copyToPrivateDir(it) }
            if (localPath == null) {
                // 拿不到图片就退化成文本分享
                if (text.isEmpty()) return
                pendingShare = mapOf(
                    "type" to "text",
                    "title" to title,
                    "text" to text,
                    "url" to ""
                )
                return
            }
            pendingShare = mapOf(
                "type" to "image",
                "title" to title,
                "text" to text,
                "url" to "",
                "imagePath" to localPath
            )
        } else {
            if (text.isEmpty()) return
            pendingShare = mapOf(
                "type" to "text",
                "title" to title,
                "text" to text,
                "url" to ""
            )
        }
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
