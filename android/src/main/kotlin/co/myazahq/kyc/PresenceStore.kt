package co.myazahq.kyc

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistence for the background presence tier: the armed config, the open
 * ENTER timestamp, and the pending per-day queue. SharedPreferences because
 * the geofence receiver runs with no Flutter engine — this must be readable
 * from a cold broadcast. Only per-day aggregates are ever stored; a location
 * trace never exists anywhere. Mirrors the RN SDK's background-store.ts.
 */
class PresenceStore(context: Context) {
  private val prefs: SharedPreferences =
    context.applicationContext.getSharedPreferences("myaza_kyc_presence", Context.MODE_PRIVATE)

  data class Config(
    val lat: Double,
    val lng: Double,
    val radius: Double,
    val baseUrl: String,
    val apiKey: String,
    val externalUserId: String,
  )

  fun saveConfig(config: Config) {
    val json = JSONObject()
      .put("lat", config.lat)
      .put("lng", config.lng)
      .put("radius", config.radius)
      .put("baseUrl", config.baseUrl)
      .put("apiKey", config.apiKey)
      .put("externalUserId", config.externalUserId)
    prefs.edit().putString("config", json.toString()).putBoolean("armed", true).apply()
  }

  fun loadConfig(): Config? {
    val raw = prefs.getString("config", null) ?: return null
    return try {
      val json = JSONObject(raw)
      Config(
        lat = json.getDouble("lat"),
        lng = json.getDouble("lng"),
        radius = json.optDouble("radius", 250.0),
        baseUrl = json.getString("baseUrl"),
        apiKey = json.getString("apiKey"),
        externalUserId = json.getString("externalUserId"),
      )
    } catch (_: Exception) {
      null
    }
  }

  fun clear() {
    prefs.edit().clear().apply()
  }

  /** The foreground-service tier's durable intent: the boot receiver restarts
   *  the service when this is set, and a refused startForeground clears it. */
  var serviceEnabled: Boolean
    get() = prefs.getBoolean("serviceEnabled", false)
    set(value) {
      prefs.edit().putBoolean("serviceEnabled", value).apply()
    }

  /** The persistent notification's content — the host's words, persisted so
   *  a START_STICKY restart or a boot can rebuild it with no Dart running. */
  data class NotificationConfig(
    val title: String,
    val body: String,
    val channelId: String,
    val channelName: String,
    val channelDescription: String?,
    val color: Int?,
  )

  fun saveNotification(n: NotificationConfig) {
    val json = JSONObject()
      .put("title", n.title)
      .put("body", n.body)
      .put("channelId", n.channelId)
      .put("channelName", n.channelName)
      .put("channelDescription", n.channelDescription ?: JSONObject.NULL)
      .put("color", n.color ?: JSONObject.NULL)
    prefs.edit().putString("notification", json.toString()).apply()
  }

  fun loadNotification(): NotificationConfig {
    val fallback = NotificationConfig(
      title = "Address verification in progress",
      body = "Open the app to see your progress.",
      channelId = "myaza_kyc_presence",
      channelName = "Address verification",
      channelDescription = null,
      color = null,
    )
    val raw = prefs.getString("notification", null) ?: return fallback
    return try {
      val json = JSONObject(raw)
      NotificationConfig(
        title = json.optString("title", fallback.title),
        body = json.optString("body", fallback.body),
        channelId = json.optString("channelId", fallback.channelId),
        channelName = json.optString("channelName", fallback.channelName),
        channelDescription = if (json.isNull("channelDescription")) null else json.optString("channelDescription"),
        color = if (json.isNull("color")) null else json.optInt("color"),
      )
    } catch (_: Exception) {
      fallback
    }
  }

  var armed: Boolean
    get() = prefs.getBoolean("armed", false)
    set(value) {
      prefs.edit().putBoolean("armed", value).apply()
    }

  var enterAt: Long?
    get() = prefs.getLong("enterAt", -1L).takeIf { it > 0 }
    set(value) {
      if (value == null) prefs.edit().remove("enterAt").apply()
      else prefs.edit().putLong("enterAt", value).apply()
    }

  /** Merge fresh day aggregates into the queue: same day → sum dwell, OR
   *  night, sum samples. The RN tier's mergeIntoQueue, verbatim. */
  fun queueDays(days: List<PresenceFold.DayAggregate>) {
    val byDay = LinkedHashMap<String, JSONObject>()
    val existing = JSONArray(prefs.getString("queue", "[]") ?: "[]")
    for (i in 0 until existing.length()) {
      val o = existing.getJSONObject(i)
      byDay[o.getString("day")] = o
    }
    for (d in days) {
      val prior = byDay[d.day]
      if (prior == null) {
        byDay[d.day] = JSONObject()
          .put("day", d.day)
          .put("dwellMinutes", d.dwellMinutes)
          .put("nightPresent", d.nightPresent)
          .put("samples", 1)
      } else {
        prior.put("dwellMinutes", prior.getInt("dwellMinutes") + d.dwellMinutes)
        prior.put("nightPresent", prior.getBoolean("nightPresent") || d.nightPresent)
        prior.put("samples", prior.getInt("samples") + 1)
      }
    }
    val next = JSONArray()
    byDay.values.forEach { next.put(it) }
    prefs.edit().putString("queue", next.toString()).apply()
  }

  /** A mocked fix's day: merged into the queue with no dwell and the
   *  mock-location flag set — evidence OF fraud is worth more to the watch
   *  than silence. The flag survives a later merge (the RN tier's rule). */
  fun queueFlagged(day: String, nightPresent: Boolean) {
    val byDay = LinkedHashMap<String, JSONObject>()
    val existing = pendingQueue()
    for (i in 0 until existing.length()) {
      val o = existing.getJSONObject(i)
      byDay[o.getString("day")] = o
    }
    val prior = byDay[day]
    val integrity = JSONObject().put("mockLocation", true)
    if (prior == null) {
      byDay[day] = JSONObject()
        .put("day", day)
        .put("dwellMinutes", 0)
        .put("nightPresent", nightPresent)
        .put("samples", 1)
        .put("integrity", integrity)
    } else {
      prior.put("nightPresent", prior.getBoolean("nightPresent") || nightPresent)
      prior.put("samples", prior.getInt("samples") + 1)
      prior.put("integrity", integrity)
    }
    val next = JSONArray()
    byDay.values.forEach { next.put(it) }
    prefs.edit().putString("queue", next.toString()).apply()
  }

  fun pendingQueue(): JSONArray = try {
    JSONArray(prefs.getString("queue", "[]") ?: "[]")
  } catch (_: Exception) {
    JSONArray()
  }

  fun clearQueue() {
    prefs.edit().putString("queue", "[]").apply()
  }
}
