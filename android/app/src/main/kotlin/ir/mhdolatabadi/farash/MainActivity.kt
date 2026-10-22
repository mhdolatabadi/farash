package ir.mhdolatabadi.farash

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exportSaver: ExportFileSaver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
