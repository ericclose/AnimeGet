package com.animeget.anime_get

import android.app.DownloadManager
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "com.animeget/media_remux"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "remuxTsToMp4" -> {
                        val inputPath = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        thread {
                            val ok = remuxTsToMp4(inputPath, outputPath)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path")
                        result.success(openFolder(path))
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        result.success(openFile(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openFile(path: String?): Boolean {
        return try {
            val targetFile = if (!path.isNullOrEmpty()) File(path) else null
            if (targetFile != null && targetFile.exists() && targetFile.isFile) {
                val uri: Uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    targetFile
                )
                val ext = targetFile.extension.lowercase()
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "video/*"
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(intent)
                return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun openFolder(path: String?): Boolean {
        return try {
            val targetFile = if (!path.isNullOrEmpty()) File(path) else null
            val targetDir = if (targetFile != null && targetFile.isDirectory) {
                targetFile
            } else {
                targetFile?.parentFile
            }
            if (targetDir != null && targetDir.exists()) {
                val canonical = targetDir.canonicalPath
                val extRoot = Environment.getExternalStorageDirectory().canonicalPath
                val relPath = when {
                    canonical.startsWith("$extRoot/") -> canonical.removePrefix("$extRoot/")
                    canonical == extRoot -> ""
                    canonical.startsWith("/sdcard/") -> canonical.removePrefix("/sdcard/")
                    canonical == "/sdcard" -> ""
                    canonical.startsWith("/storage/emulated/0/") -> canonical.removePrefix("/storage/emulated/0/")
                    else -> null
                }
                if (relPath != null) {
                    val docId = if (relPath.isEmpty()) "primary:" else "primary:$relPath"
                    val docUri = DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents",
                        docId
                    )
                    val docIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(docUri, "vnd.android.document/directory")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(docIntent)
                    return true
                }

                val dirUri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    targetDir
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(dirUri, "resource/folder")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(intent)
                return true
            }
            startActivity(
                Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun remuxTsToMp4(inputPath: String, outputPath: String): Boolean {
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        return try {
            extractor = MediaExtractor().apply { setDataSource(inputPath) }
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val trackIndexMap = mutableMapOf<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    extractor.selectTrack(i)
                    trackIndexMap[i] = muxer.addTrack(format)
                }
            }

            if (trackIndexMap.isEmpty()) {
                return false
            }

            muxer.start()
            val buffer = ByteBuffer.allocate(1024 * 1024)
            val bufferInfo = MediaCodec.BufferInfo()

            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                val trackIndex = extractor.sampleTrackIndex
                val muxerTrack = trackIndexMap[trackIndex]
                if (muxerTrack != null) {
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = extractor.sampleTime
                    bufferInfo.flags = extractor.sampleFlags
                    muxer.writeSampleData(muxerTrack, buffer, bufferInfo)
                }
                extractor.advance()
            }

            muxer.stop()
            true
        } catch (_: Exception) {
            false
        } finally {
            try {
                extractor?.release()
            } catch (_: Exception) {}
            try {
                muxer?.release()
            } catch (_: Exception) {}
        }
    }
}
