package ir.mhdolatabadi.farash

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** No storage permissions, cached file, private path or persisted URI grant. */
class ExportFileSaver(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var bytes: ByteArray? = null
    private val worker = Executors.newSingleThreadExecutor()
    private var disposed = false

    fun save(content: ByteArray?, result: MethodChannel.Result) {
        if (disposed || pending != null) {
            result.error("export_busy", "A document operation is already active.", null)
            return
        }
        if (content == null || content.isEmpty() || content.size > 32 * 1024 * 1024) {
            result.error("invalid_export", "Invalid export data.", null)
            return
        }
        pending = result
        bytes = content
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, "farash-export-v1.json")
            }
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: Exception) {
            finishError()
        }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending?.success(false)
            clear()
            return true
        }
        val content = bytes
        val uri = data.data!!
        if (content == null || pending == null) return true
        // Content providers may be remote. Never block the Flutter/UI thread.
        worker.execute {
            var succeeded = false
            try {
                activity.contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                    stream.write(content)
                    stream.flush()
                    succeeded = true
                }
            } catch (_: Exception) {
                // Deliberately do not log a private content URI or task bytes.
            }
            activity.runOnUiThread {
                if (!disposed) {
                    if (succeeded) pending?.success(true) else pending?.error("export_write_failed", "Could not save the document.", null)
                    clear()
                }
            }
        }
        return true
    }

    fun dispose() {
        disposed = true
        pending?.error("export_interrupted", "The document operation was interrupted.", null)
        clear()
        worker.shutdown()
    }

    private fun finishError() {
        pending?.error("export_unavailable", "No document provider is available.", null)
        clear()
    }

    private fun clear() {
        pending = null
        bytes = null
    }

    companion object {
        private const val REQUEST_CODE = 58142
    }
}
