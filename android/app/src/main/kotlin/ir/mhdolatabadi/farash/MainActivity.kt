package ir.mhdolatabadi.farash

import android.content.Intent
import android.net.Uri
import android.content.ActivityNotFoundException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exportSaver: ExportFileSaver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.mhdolatabadi.farash/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method != "authorize") {
                    result.notImplemented()
                } else {
                    val uri = (call.arguments as? String)?.let { Uri.parse(it) }
                    if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) {
                        result.error("invalid_url", "Invalid authorization address", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(null)
                        } catch (_: ActivityNotFoundException) {
                            result.error("browser_unavailable", "No browser is available", null)
                        } catch (_: SecurityException) {
                            result.error("browser_unavailable", "Browser could not open", null)
                        }
                    }
                }
            }
        exportSaver = ExportFileSaver(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.mhdolatabadi.farash/export")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveJson") {
                    exportSaver!!.save(call.arguments as? ByteArray, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Deprecated("Activity result forwarding for the system document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (exportSaver?.onResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        exportSaver?.dispose()
        super.onDestroy()
    }
}
