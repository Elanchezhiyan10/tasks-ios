
package com.example.flutter_pgi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.flutter_pgi/task_widget"
        ).setMethodCallHandler { call, result ->

            if (call.method == "refreshTaskWidget") {
                val manager = AppWidgetManager.getInstance(this)
                val component = ComponentName(
                    this,
                    TaskWidgetProvider::class.java
                )
                val ids = manager.getAppWidgetIds(component)

                if (ids.isNotEmpty()) {
                    val intent = Intent(
                        this,
                        TaskWidgetProvider::class.java
                    ).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(
                            AppWidgetManager.EXTRA_APPWIDGET_IDS,
                            ids
                        )
                    }

                    sendBroadcast(intent)
                }

                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
