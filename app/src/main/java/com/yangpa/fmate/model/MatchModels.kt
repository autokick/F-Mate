package com.yangpa.fmate.model

import java.time.LocalDateTime

data class MatchCardData(
    val id: String,
    val title: String,
    val location: String,
    val scheduledAt: LocalDateTime,
    val level: String,
    val timeTag: String,
    val roleFocus: String,
    val surface: String,
    val capacity: Int,
    val joinedCount: Int,
    val hostType: String,
    val notes: String,
    val hostName: String,
    val hostRating: Double,
    val distanceKm: Double,
    val createdByUser: Boolean = false,
) {
    val tags: List<String>
        get() = listOf(timeTag, "$roleFocus 모집", surface)
}

data class PlayerProfile(
    val position: String,
    val skill: String,
    val timePreference: String,
)

enum class MatchFilter(val label: String) {
    All("전체"),
    Beginner("초급"),
    Intermediate("중급"),
    Night("야간"),
}

fun sampleMatches(now: LocalDateTime = LocalDateTime.now()): List<MatchCardData> {
    val baseDate = now.toLocalDate()

    return listOf(
        MatchCardData(
            id = "m1",
            title = "성수 수요 야간 5v5",
            location = "성수 서울숲 풋살파크",
            scheduledAt = baseDate.plusDays(2).atTime(20, 30),
            level = "중급",
            timeTag = "야간",
            roleFocus = "윙어",
            surface = "실내",
            capacity = 10,
            joinedCount = 7,
            hostType = "추천 매치",
            notes = "퇴근 후 바로 참여하는 직장인 중심 매치입니다. 패스 템포가 빠르고 분위기가 깔끔한 편입니다.",
            hostName = "TEAM Onion",
            hostRating = 4.9,
            distanceKm = 2.4,
        ),
        MatchCardData(
            id = "m2",
            title = "건대 루프탑 목요전",
            location = "건대입구 루프탑 경기장",
            scheduledAt = baseDate.plusDays(3).atTime(20, 0),
            level = "중급",
            timeTag = "야간",
            roleFocus = "피보",
            surface = "실외",
            capacity = 12,
            joinedCount = 10,
            hostType = "인기 매치",
            notes = "혼자 와도 바로 팀 배정이 가능한 매치입니다. 현재 참가 중인 경기로 일정 탭에 표시됩니다.",
            hostName = "건대 FC",
            hostRating = 4.8,
            distanceKm = 3.1,
        ),
        MatchCardData(
            id = "m3",
            title = "강남 토요 아침 풋살",
            location = "강남 탄천 풋살센터",
            scheduledAt = baseDate.plusDays(5).atTime(10, 0),
            level = "초급",
            timeTag = "주간",
            roleFocus = "수비",
            surface = "실외",
            capacity = 10,
            joinedCount = 6,
            hostType = "입문자 추천",
            notes = "가볍게 몸을 풀며 즐기는 초급자 중심 매치입니다. 풋살 입문자에게 맞는 템포입니다.",
            hostName = "Morning Kickers",
            hostRating = 4.7,
            distanceKm = 5.3,
        ),
        MatchCardData(
            id = "m4",
            title = "마포 금요 경쟁전",
            location = "마포구민체육센터",
            scheduledAt = baseDate.plusDays(4).atTime(21, 0),
            level = "상급",
            timeTag = "야간",
            roleFocus = "골키퍼",
            surface = "실내",
            capacity = 10,
            joinedCount = 8,
            hostType = "도전 매치",
            notes = "강한 압박과 빠른 전환을 선호하는 상급자 중심 경기입니다.",
            hostName = "Mapo Rush",
            hostRating = 4.9,
            distanceKm = 4.6,
        ),
    )
}
