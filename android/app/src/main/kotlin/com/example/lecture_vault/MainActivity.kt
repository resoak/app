package com.example.lecture_vault

import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "native_libs")
            .setMethodCallHandler { call, result ->
                if (call.method == "getNativeLibDir") {
                    val dir = applicationInfo.nativeLibraryDir
                    Log.d("MAIN", "nativeLibDir: $dir")
                    result.success(dir)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lecture_vault/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareFiles") {
                    shareFiles(call, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun shareFiles(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val text = call.argument<String>("text").orEmpty()
        val subject = call.argument<String>("subject").orEmpty()
        val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()

        if (text.isBlank() && filePaths.isEmpty()) {
            result.error("empty_payload", "沒有可分享的內容。", null)
            return
        }

        try {
            val uris = filePaths.map { path ->
                val file = File(path)
                if (!file.exists()) {
                    throw IllegalStateException("找不到要分享的檔案：$path")
                }
                FileProvider.getUriForFile(
                    this,
                    "$packageName.lecturevault.shareprovider",
                    file,
                )
            }

            val shareIntent = if (uris.size > 1) {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                }
            } else {
                Intent(Intent.ACTION_SEND).apply {
                    if (uris.isNotEmpty()) {
                        putExtra(Intent.EXTRA_STREAM, uris.first())
                    }
                }
            }

            shareIntent.apply {
                type = resolveMimeType(filePaths)
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_SUBJECT, subject)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = buildClipData(uris)
            }

            startActivity(Intent.createChooser(shareIntent, subject.ifBlank { "LectureVault 匯出" }))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "無法開啟分享面板。", null)
        }
    }

    private fun buildClipData(uris: List<android.net.Uri>): ClipData? {
        if (uris.isEmpty()) {
            return null
        }

        val clipData = ClipData.newRawUri("LectureVault export", uris.first())
        uris.drop(1).forEach { uri ->
            clipData.addItem(ClipData.Item(uri))
        }
        return clipData
    }

    private fun resolveMimeType(filePaths: List<String>): String {
        if (filePaths.isEmpty()) {
            return "text/plain"
        }
        if (filePaths.size > 1) {
            return "*/*"
        }

        val extension = MimeTypeMap.getFileExtensionFromUrl(filePaths.first())
            ?.lowercase()
            ?.takeIf { it.isNotBlank() }
            ?: return "*/*"

        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
    }
}
