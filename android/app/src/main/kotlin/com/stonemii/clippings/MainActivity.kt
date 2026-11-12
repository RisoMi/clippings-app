package com.stonemii.clippings

import android.app.Activity
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
 * 3) 把导出的 Markdown / TXT / ZIP 通过 FileProvider 分享出去；
 * 4) 打开系统文件选择器挑备份包并复制到私有目录（导入用）。
 *
 * 关键设计：分享内容是「暂存 + 通知」，由 Dart 主动来取。
 * 不在 onNewIntent 里直接塞 payload，是因为 Dart 侧 handler 未注册时
 * invokeMethod 会静默丢弃，那次分享就永久丢了。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.stonemii.clippings/bridge"
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null
    private var pendingPick: MethodChannel.Result? = null

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

                "pickBackupFile" -> pickBackupFile(result)

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

    /* ------------------------------ 分享接收 ------------------------------ */

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
        return copyUriTo(uri, "share_incoming", "shared_${System.currentTimeMillis()}.jpg")
    }

    /* ------------------------------ 导入备份 ------------------------------ */

    private fun pickBackupFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "已有文件选择正在进行中", null)
            return
        }
        pendingPick = result
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")
            )
        }
        try {
            startActivityForResult(picker, REQ_PICK_BACKUP)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", "无法打开文件选择器", e.message)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_BACKUP) return

        val result = pendingPick
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result?.success(null)
            return
        }
        result?.success(importBackup(uri))
    }

    /**
     * 导入用的复制：超过上限时返回哨兵字符串而不是 null，
     * 这样 Dart 侧能把「用户取消」和「文件太大」分开提示。
     */
    private fun importBackup(uri: Uri): String {
        return try {
            val dir = File(filesDir, "imports").apply { mkdirs() }
            val target = File(dir, "backup_${System.currentTimeMillis()}.zip")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.length() > MAX_IMPORT_BYTES) {
                target.delete()
                "too_large"
            } else {
                target.absolutePath
            }
        } catch (e: Exception) {
            ""
        }
    }

    /** 把内容 Uri 复制到私有目录（图片用） */
    private fun copyUriTo(uri: Uri, dirName: String, fileName: String): String? {
        return try {
            val dir = File(filesDir, dirName).apply { mkdirs() }
            val target = File(dir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /* ------------------------------ 导出分享 ------------------------------ */

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

    private companion object {
        const val REQ_PICK_BACKUP = 1001
        const val MAX_IMPORT_BYTES = 200L * 1024 * 1024
    }
}
