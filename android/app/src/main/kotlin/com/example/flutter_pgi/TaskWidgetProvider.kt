
package com.example.flutter_pgi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import android.util.Log
import java.util.Date

class TaskWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        Log.d("TaskWidget","onUpdate() called")
        for (id in ids) {
            showLoading(context, manager, id)
            loadTasks(context, manager, id)
        }
    }

    private fun showLoading(
        context: Context,
        manager: AppWidgetManager,
        id: Int
    ) {
        val views = RemoteViews(
            context.packageName,
            R.layout.task_widget
        )
        views.setTextViewText(R.id.widget_title, "TASK FOCUS")
        views.setTextViewText(R.id.widget_task_1, "Loading tasks...")
        views.setTextViewText(R.id.widget_task_2, "")
        views.setTextViewText(R.id.widget_task_3, "")
        views.setTextViewText(R.id.widget_status, "Your daily priorities")
        manager.updateAppWidget(id, views)
    }

    private fun loadTasks(
        context: Context,
        manager: AppWidgetManager,
        id: Int
    ) {
        Thread {
            var tasks = emptyList<JSONObject>()
            var message = "Open the app and log in to view tasks."

            try {
                // Values saved by Flutter shared_preferences.
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )

                val token = prefs.getString(
                    "flutter.task_widget_token", null
                )
                val baseUrl = prefs.getString(
    "flutter.task_widget_base_url",
    "https://tasks-reminder.onrender.com"
)
                Log.d("TaskWidget", "Token available: ${!token.isNullOrBlank()}")
Log.d("TaskWidget", "Base URL: $baseUrl")

                if (!token.isNullOrBlank() && !baseUrl.isNullOrBlank()) {
                    val connection = URL(
                        "${baseUrl.trimEnd('/')}/tasks"
                    ).openConnection() as HttpURLConnection

                    try {
                        connection.requestMethod = "GET"
                        connection.connectTimeout = 10000
                        connection.readTimeout = 10000
                        connection.setRequestProperty(
                            "Authorization", "Bearer $token"
                        )
                        connection.setRequestProperty(
                            "Accept", "application/json"
                        )

                        
val statusCode = connection.responseCode

val responseStream = if (statusCode in 200..299) {
    connection.inputStream
} else {
    connection.errorStream
}

val response = responseStream?.bufferedReader()
    ?.use { it.readText() } ?: ""

android.util.Log.d(
    "TaskWidget",
    "HTTP $statusCode response: $response"
)

if (statusCode in 200..299) {
   val array = try {
    org.json.JSONArray(response)
} catch (e: Exception) {
    JSONObject(response).optJSONArray("tasks")
}

    if (array != null) {
        val list = mutableListOf<JSONObject>()

        for (i in 0 until array.length()) {
            val task = array.optJSONObject(i) ?: continue

            if (task.optString("occurrence_status") == "pending") {
                list.add(task)
            }
        }

        val rank = mapOf("high" to 0, "medium" to 1, "low" to 2)

        tasks = list.sortedWith(
            compareBy<JSONObject> {
                rank[it.optString("priority").lowercase()] ?: 3
            }.thenBy {
                it.optString("scheduled_at")
            }
        ).take(3)

        message = if (tasks.isEmpty()) {
            "You're all caught up! Great work."
        } else {
            "Your top ${tasks.size} pending task(s)"
        }
    } else {
        message = "API response has no 'tasks' array."
    }
} else {
    message = "API error: HTTP $statusCode"
}

                    } finally {
                        connection.disconnect()
                    }
                }
            } catch (e: Exception) {
    Log.e("TaskWidget", "Failed to load tasks", e)
    message = "Couldn't load tasks. Open the app."
}

            Handler(Looper.getMainLooper()).post {
                render(context, manager, id, tasks, message)
            }
        }.start()
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        tasks: List<JSONObject>,
        message: String
    ) {
        val views = RemoteViews(
            context.packageName,
            R.layout.task_widget
        )

        views.setTextViewText(R.id.widget_title, "TASK FOCUS")

        val taskViews = listOf(
            R.id.widget_task_1,
            R.id.widget_task_2,
            R.id.widget_task_3
        )

        for (i in taskViews.indices) {
            if (i < tasks.size) {
                val task = tasks[i]
                val title = task.optString("title", "Untitled task")
                val priority = task.optString("priority", "medium")
                    .uppercase()
                val time = formatTime(task.optString("scheduled_at"))

                views.setTextViewText(
                    taskViews[i],
                    "${i + 1}. [$priority] $title · $time"
                )
                views.setViewVisibility(taskViews[i], View.VISIBLE)
            } else {
                views.setTextViewText(taskViews[i], "")
                views.setViewVisibility(taskViews[i], View.GONE)
            }
        }

        views.setTextViewText(R.id.widget_status, message)

        // Tapping the widget opens the app.
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)

        if (launchIntent != null) {
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(
                R.id.widget_container,
                pendingIntent
            )
        }

        manager.updateAppWidget(id, views)
    }

    private fun formatTime(value: String): String {
        return try {
            val input = SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss",
                Locale.US
            )
            val output = SimpleDateFormat("h:mm a", Locale.US)
            output.format(input.parse(value) ?: Date())
        } catch (e: Exception) {
            value
        }
    }
}
