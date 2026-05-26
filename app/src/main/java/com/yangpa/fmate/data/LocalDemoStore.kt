package com.yangpa.fmate.data

import android.content.Context
import com.yangpa.fmate.model.MatchCardData
import com.yangpa.fmate.model.PlayerProfile
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime

data class DemoSnapshot(
    val matches: List<MatchCardData>,
    val joinedMatchIds: List<String>,
    val bookmarkedMatchIds: List<String>,
    val displayName: String,
    val profile: PlayerProfile,
    val enteredApp: Boolean,
)

class LocalDemoStore(context: Context) {
    private val preferences = context.getSharedPreferences("fmate_demo_state", Context.MODE_PRIVATE)

    fun load(): DemoSnapshot? {
        val raw = preferences.getString(KEY_STATE, null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            DemoSnapshot(
                matches = json.getJSONArray("matches").toMatchList(),
                joinedMatchIds = json.getJSONArray("joinedMatchIds").toStringList(),
                bookmarkedMatchIds = json.optJSONArray("bookmarkedMatchIds")?.toStringList().orEmpty(),
                displayName = json.optString("displayName", "홍길동"),
                profile = json.getJSONObject("profile").toProfile(),
                enteredApp = json.optBoolean("enteredApp", false),
            )
        }.getOrNull()
    }

    fun save(snapshot: DemoSnapshot) {
        val json = JSONObject()
            .put("matches", snapshot.matches.toMatchJsonArray())
            .put("joinedMatchIds", snapshot.joinedMatchIds.toStringJsonArray())
            .put("bookmarkedMatchIds", snapshot.bookmarkedMatchIds.toStringJsonArray())
            .put("displayName", snapshot.displayName)
            .put("profile", snapshot.profile.toJson())
            .put("enteredApp", snapshot.enteredApp)

        preferences.edit().putString(KEY_STATE, json.toString()).apply()
    }

    fun clear() {
        preferences.edit().remove(KEY_STATE).apply()
    }

    private fun JSONArray.toStringList(): List<String> = List(length()) { index -> getString(index) }

    private fun JSONArray.toMatchList(): List<MatchCardData> = List(length()) { index ->
        getJSONObject(index).toMatch()
    }

    private fun JSONObject.toProfile(): PlayerProfile = PlayerProfile(
        position = optString("position", "윙어"),
        skill = optString("skill", "중급"),
        timePreference = optString("timePreference", "야간"),
    )

    private fun JSONObject.toMatch(): MatchCardData {
        val matchId = getString("id")
        return MatchCardData(
            id = matchId,
            title = getString("title"),
            location = getString("location"),
            scheduledAt = LocalDateTime.parse(getString("scheduledAt")),
            level = getString("level"),
            timeTag = getString("timeTag"),
            roleFocus = getString("roleFocus"),
            surface = getString("surface"),
            capacity = getInt("capacity"),
            joinedCount = getInt("joinedCount"),
            hostType = getString("hostType"),
            notes = getString("notes"),
            hostName = getString("hostName"),
            hostRating = getDouble("hostRating"),
            distanceKm = getDouble("distanceKm"),
            createdByUser = optBoolean("createdByUser", false),
            fee = optInt("fee", 12000),
            reviewCount = optInt("reviewCount", 24),
            checkInCode = optString("checkInCode", "FM-${matchId.takeLast(3).uppercase()}"),
            amenities = optJSONArray("amenities")?.toStringList().orEmpty(),
        )
    }

    private fun MatchCardData.toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("location", location)
        .put("scheduledAt", scheduledAt.toString())
        .put("level", level)
        .put("timeTag", timeTag)
        .put("roleFocus", roleFocus)
        .put("surface", surface)
        .put("capacity", capacity)
        .put("joinedCount", joinedCount)
        .put("hostType", hostType)
        .put("notes", notes)
        .put("hostName", hostName)
        .put("hostRating", hostRating)
        .put("distanceKm", distanceKm)
        .put("createdByUser", createdByUser)
        .put("fee", fee)
        .put("reviewCount", reviewCount)
        .put("checkInCode", checkInCode)
        .put("amenities", amenities.toStringJsonArray())

    private fun PlayerProfile.toJson(): JSONObject = JSONObject()
        .put("position", position)
        .put("skill", skill)
        .put("timePreference", timePreference)

    private fun List<MatchCardData>.toMatchJsonArray(): JSONArray = JSONArray().also { array ->
        forEach { match -> array.put(match.toJson()) }
    }

    private fun List<String>.toStringJsonArray(): JSONArray = JSONArray().also { array ->
        forEach { value -> array.put(value) }
    }

    private companion object {
        const val KEY_STATE = "state"
    }
}
