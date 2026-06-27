package com.twalitso.padue

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory
import java.io.File
import android.content.Context
import android.database.Cursor
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    private val channel = "com.twalitso.padue/photo_picker"
    private var resultChannel: MethodChannel.Result? = null
    private val PICK_PHOTO_REQUEST = 1
    private val PICK_DOCUMENT_REQUEST = 2
    private val PICK_PHOTOS_REQUEST = 3

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FirebaseAppCheck.getInstance().installAppCheckProviderFactory(
            PlayIntegrityAppCheckProviderFactory.getInstance()
        )
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            resultChannel = result
            when (call.method) {
                "pickPhoto" -> {
                    val intent = Intent(MediaStore.ACTION_PICK_IMAGES)
                    startActivityForResult(intent, PICK_PHOTO_REQUEST)
                }
                "pickDocument" -> {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, PICK_DOCUMENT_REQUEST)
                }
                "pickPhotos" -> {
                    val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
                    val intent = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                        putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                    }
                    startActivityForResult(intent, PICK_PHOTOS_REQUEST)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == RESULT_OK) {
            when (requestCode) {
                PICK_PHOTO_REQUEST, PICK_DOCUMENT_REQUEST -> {
                    val uri: Uri? = data?.data
                    val path = uri?.let { getRealPathFromUri(it) }
                    resultChannel?.success(path)
                }
                PICK_PHOTOS_REQUEST -> {
                    if (data?.clipData != null) {
                        val paths = mutableListOf<String>()
                        for (i in 0 until data.clipData!!.itemCount) {
                            val uri = data.clipData!!.getItemAt(i).uri
                            val path = getRealPathFromUri(uri)
                            if (path != null) paths.add(path)
                        }
                        resultChannel?.success(paths)
                    } else if (data?.data != null) {
                        val path = getRealPathFromUri(data.data!!)
                        resultChannel?.success(path?.let { listOf(it) })
                    } else {
                        resultChannel?.success(null)
                    }
                }
                else -> {
                    resultChannel?.success(null)
                }
            }
        } else {
            resultChannel?.success(null)
        }
        resultChannel = null
    }

    private fun getRealPathFromUri(uri: Uri): String? {
        // Try querying MediaStore
        val projection = arrayOf(MediaStore.Images.Media.DATA)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                return cursor.getString(columnIndex)
            }
        }

        // Fallback: Copy to cache and return path
        return try {
            val inputStream = contentResolver.openInputStream(uri)
            val file = File(cacheDir, "temp_${System.currentTimeMillis()}.jpg")
            inputStream?.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}