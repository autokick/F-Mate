package com.yangpa.fmate.ui

import com.yangpa.fmate.data.ChatMessageData
import com.yangpa.fmate.data.sendMessageToFirebase
import com.yangpa.fmate.data.listenMessagesFromFirebase
import com.yangpa.fmate.data.saveUserToFirebase
import com.yangpa.fmate.data.UserProfile
import com.yangpa.fmate.data.loadUsersFromFirebase
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material.icons.filled.AssistantDirection
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.StackedBarChart
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Button
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yangpa.fmate.data.DemoSnapshot
import com.yangpa.fmate.data.LocalDemoStore
import com.yangpa.fmate.model.MatchCardData
import com.yangpa.fmate.model.MatchFilter
import com.yangpa.fmate.model.PlayerProfile
import com.yangpa.fmate.model.sampleMatches
import com.yangpa.fmate.ui.theme.CitrusOrange
import com.yangpa.fmate.ui.theme.FMateTheme
import com.yangpa.fmate.ui.theme.FieldGreen
import com.yangpa.fmate.ui.theme.FreshGreen
import com.yangpa.fmate.ui.theme.Ink
import com.yangpa.fmate.ui.theme.MutedInk
import com.yangpa.fmate.ui.theme.PitchDark
import com.yangpa.fmate.ui.theme.TeamBlue
import com.yangpa.fmate.ui.theme.WarmSand
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import com.yangpa.fmate.data.updateUserProfileToFirebase
import com.yangpa.fmate.data.addFriendToFirebase
import com.yangpa.fmate.data.loadFriendsFromFirebase

@Composable
internal fun MatchListScreen(
    matches: List<MatchCardData>,
    joinedMatchIds: List<String>,
    bookmarkedMatchIds: List<String>,
    profile: PlayerProfile,
    scoreMatch: (MatchCardData) -> Int,
    onOpenMatch: (MatchCardData) -> Unit,
    onToggleJoin: (MatchCardData) -> Unit,
    onToggleBookmark: (MatchCardData) -> Unit,
    onCreateClick: () -> Unit,
) {
    var selectedFilter by remember { mutableStateOf(MatchFilter.All) }
    var searchQuery by remember { mutableStateOf("") }
    var selectedSurface by remember { mutableStateOf("전체 구장") }
    var showBookmarkedOnly by remember { mutableStateOf(false) }
    val rankedMatches = matches.sortedByDescending(scoreMatch)
    val bestMatch = rankedMatches.firstOrNull()
    val surfaceOptions = listOf("전체 구장") + matches.map { it.surface }.distinct()
    val filteredMatches = rankedMatches.filter { match ->
        val matchesLevel = when (selectedFilter) {
            MatchFilter.All -> true
            MatchFilter.Beginner -> match.level == "초급"
            MatchFilter.Intermediate -> match.level == "중급"
            MatchFilter.Night -> match.timeTag == "야간"
        }
        val matchesSearch = searchQuery.isBlank() ||
            match.title.contains(searchQuery, ignoreCase = true) ||
            match.location.contains(searchQuery, ignoreCase = true) ||
            match.hostName.contains(searchQuery, ignoreCase = true)
        val matchesSurface = selectedSurface == "전체 구장" || match.surface == selectedSurface
        val matchesBookmark = !showBookmarkedOnly || bookmarkedMatchIds.contains(match.id)

        matchesLevel && matchesSearch && matchesSurface && matchesBookmark
    }

    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (bestMatch != null) {
            item {
                FeaturedMatchCard(
                    match = bestMatch,
                    score = scoreMatch(bestMatch),
                    profile = profile,
                    joined = joinedMatchIds.contains(bestMatch.id),
                    bookmarked = bookmarkedMatchIds.contains(bestMatch.id),
                    scheduledCount = joinedMatchIds.size,
                    onOpen = { onOpenMatch(bestMatch) },
                    onJoin = { onToggleJoin(bestMatch) },
                    onBookmark = { onToggleBookmark(bestMatch) },
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                MetricCard("참가 일정", joinedMatchIds.size.toString(), FieldGreen, modifier = Modifier.weight(1f))
                MetricCard("개설 매치", matches.count { it.createdByUser }.toString(), CitrusOrange, modifier = Modifier.weight(1f))
                MetricCard("최고 점수", "${bestMatch?.let(scoreMatch) ?: 0}%", TeamBlue, modifier = Modifier.weight(1f))
            }
        }

        item {
            SectionHeading(
                subtitle = "Discover",
                title = "추천 매치",
                caption = "검색, 구장 타입, 관심 매치, 추천 점수를 조합해 실제 서비스처럼 탐색합니다.",
            )
        }

        item {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("매치, 장소, 호스트 검색") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
            )
        }

        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = showBookmarkedOnly,
                    onClick = { showBookmarkedOnly = !showBookmarkedOnly },
                    label = { Text("관심 매치") },
                    leadingIcon = {
                        Icon(
                            if (showBookmarkedOnly) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                    },
                )
                MatchFilter.entries.forEach { filter ->
                    FilterChip(
                        selected = selectedFilter == filter,
                        onClick = { selectedFilter = filter },
                        label = { Text(filter.label) },
                    )
                }
            }
        }

        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                surfaceOptions.forEach { surface ->
                    FilterChip(
                        selected = selectedSurface == surface,
                        onClick = { selectedSurface = surface },
                        label = { Text(surface) },
                    )
                }
            }
        }

        if (filteredMatches.isEmpty()) {
            item {
                EmptyCard(
                    title = "조건에 맞는 매치가 없습니다.",
                    description = "검색어나 필터를 조금 풀어보면 추천 후보를 다시 찾을 수 있습니다.",
                )
            }
        } else {
            items(filteredMatches, key = { it.id }) { match ->
                MatchCard(
                    match = match,
                    joined = joinedMatchIds.contains(match.id),
                    bookmarked = bookmarkedMatchIds.contains(match.id),
                    score = scoreMatch(match),
                    onTap = { onOpenMatch(match) },
                    onJoin = { onToggleJoin(match) },
                    onBookmark = { onToggleBookmark(match) },
                )
            }
        }

        item {
            FlowCard(onCreateClick = onCreateClick)
        }
    }
}

@Composable
internal fun FeaturedMatchCard(
    match: MatchCardData,
    score: Int,
    profile: PlayerProfile,
    joined: Boolean,
    bookmarked: Boolean,
    scheduledCount: Int,
    onOpen: () -> Unit,
    onJoin: () -> Unit,
    onBookmark: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(30.dp),
        colors = CardDefaults.cardColors(containerColor = PitchDark),
        elevation = CardDefaults.cardElevation(defaultElevation = 10.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(pitchGradient)
                .padding(22.dp),
        ) {
            PitchLines(alpha = 0.16f)
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TagChip("MATCHDAY PICK", bright = true)
                    Spacer(modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = onBookmark,
                        colors = IconButtonDefaults.filledTonalIconButtonColors(
                            containerColor = Color.White.copy(alpha = 0.14f),
                            contentColor = Color.White,
                        ),
                    ) {
                        Icon(
                            if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                            contentDescription = "관심 매치",
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        "$scheduledCount GAMES ON",
                        color = Color(0xFFE4F8E8),
                        fontWeight = FontWeight.Bold,
                    )
                }
                Spacer(modifier = Modifier.height(18.dp))
                Text(
                    match.title,
                    color = Color.White,
                    style = MaterialTheme.typography.headlineLarge,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "${profile.position} 포지션과 ${profile.timePreference} 선호를 반영해 가장 적합한 매치입니다.",
                    color = Color(0xFFDDF7E4),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(modifier = Modifier.height(14.dp))
                TagRow(
                    tags = listOf("$score% 적합", matchStatus(match).label, match.level, match.timeTag, match.roleFocus),
                    bright = true,
                )
                Spacer(modifier = Modifier.height(18.dp))
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.10f)),
                    shape = RoundedCornerShape(22.dp),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("KICK OFF", color = Color(0xFFE1FFE9), fontWeight = FontWeight.Bold)
                            Text(
                                formatMatchDateTime(match.scheduledAt),
                                color = Color.White,
                                style = MaterialTheme.typography.titleMedium,
                            )
                        }
                        Box(
                            modifier = Modifier
                                .size(58.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(score.toString(), color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 24.sp)
                        }
                    }
                }
                Spacer(modifier = Modifier.height(18.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = onOpen,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = FieldGreen),
                    ) {
                        Text("상세 보기")
                    }
                    OutlinedButton(
                        onClick = onJoin,
                        enabled = joined || match.joinedCount < match.capacity,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    ) {
                        Text(
                            when {
                                joined -> "참가 취소"
                                match.joinedCount >= match.capacity -> "모집 마감"
                                else -> "바로 참가"
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun MatchCard(
    match: MatchCardData,
    joined: Boolean,
    bookmarked: Boolean,
    score: Int,
    onTap: () -> Unit,
    onJoin: () -> Unit,
    onBookmark: () -> Unit,
) {
    val status = matchStatus(match)

    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap),
        shape = RoundedCornerShape(26.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            DateBadge(match.scheduledAt)
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        match.hostType,
                        modifier = Modifier.weight(1f),
                        color = MutedInk,
                        fontWeight = FontWeight.Bold,
                    )
                    IconButton(
                        onClick = onBookmark,
                        modifier = Modifier.size(40.dp),
                    ) {
                        Icon(
                            if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                            contentDescription = "관심 매치",
                            tint = if (bookmarked) CitrusOrange else MutedInk,
                        )
                    }
                    TagChip("$score% 적합")
                }
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    match.title,
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(match.location, color = MutedInk, style = MaterialTheme.typography.bodyMedium)
                Spacer(modifier = Modifier.height(10.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFFF5F1E6))
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "${match.joinedCount}/${match.capacity}명 모집",
                        modifier = Modifier.weight(1f),
                        fontWeight = FontWeight.Bold,
                    )
                    Text(status.label, color = status.color, fontWeight = FontWeight.ExtraBold)
                }
                Spacer(modifier = Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Payments, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(18.dp))
                    Text("${match.fee}원", color = FieldGreen, fontWeight = FontWeight.Bold)
                    Text("· ${match.hostRating}점 (${match.reviewCount})", color = MutedInk)
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    match.notes,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color(0xFF2A302A),
                )
                Spacer(modifier = Modifier.height(12.dp))
                TagRow(tags = match.tags)
                Spacer(modifier = Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    FilledTonalButton(
                        onClick = onJoin,
                        enabled = joined || match.joinedCount < match.capacity,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(
                            when {
                                joined -> "참가 취소"
                                match.joinedCount >= match.capacity -> "모집 마감"
                                else -> "참가 신청"
                            },
                        )
                    }
                    IconButton(
                        onClick = onTap,
                        colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = WarmSand),
                    ) {
                        Icon(Icons.Filled.ArrowOutward, contentDescription = "상세 보기")
                    }
                }
            }
        }
    }
}

@Composable
internal fun ScheduleScreen(matches: List<MatchCardData>) {
    val scheduledMatches = matches.sortedBy { it.scheduledAt }

    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionHeading(
                subtitle = "Schedule",
                title = "참가 일정",
                caption = "${scheduledMatches.size}개의 매치가 내 일정에 연결되어 있습니다.",
            )
        }
        if (scheduledMatches.isEmpty()) {
            item {
                EmptyCard(
                    title = "아직 참가한 매치가 없습니다.",
                    description = "매치 탭에서 참가 신청을 누르면 일정이 자동으로 생성됩니다.",
                )
            }
        } else {
            item {
                ScheduleSummaryCard(
                    nextMatch = scheduledMatches.first(),
                    totalCount = scheduledMatches.size,
                )
            }
            items(scheduledMatches, key = { it.id }) { match ->
                ScheduleCard(
                    match = match,
                    statusLabel = if (scheduledMatches.indexOf(match) == 0) "확정" else "대기",
                )
            }
        }
    }
}

@Composable
internal fun CreateMatchScreen(
    displayName: String,
    profile: PlayerProfile,
    onCreateMatch: (MatchCardData) -> Unit,
    showMessage: (String) -> Unit,
) {
    val dateOptions = remember {
        val today = LocalDate.now()
        listOf(today.plusDays(1), today.plusDays(2), today.plusDays(4))
    }
    val timeOptions = listOf("10:00", "19:30", "20:30", "21:00")
    val levels = listOf("초급", "중급", "상급")
    val capacities = listOf(8, 10, 12, 14)
    val feeOptions = listOf(8000, 10000, 12000, 15000)

    var title by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var selectedDate by remember { mutableStateOf(dateOptions.first()) }
    var selectedTime by remember { mutableStateOf("20:30") }
    var selectedLevel by remember { mutableStateOf("중급") }
    var selectedCapacity by remember { mutableStateOf(10) }
    var selectedFee by remember { mutableStateOf(12000) }

    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionHeading(
                subtitle = "Host",
                title = "새 매치 만들기",
                caption = "입력한 매치는 생성 즉시 내 일정에 들어가도록 구성했습니다.",
            )
        }

        item {
            HostPreviewCard(
                title = title.ifBlank { "아직 이름이 없는 새 매치" },
                date = selectedDate,
                time = selectedTime,
                level = selectedLevel,
                capacity = selectedCapacity,
                fee = selectedFee,
            )
        }

        item {
            ElevatedCard(
                colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
                shape = RoundedCornerShape(26.dp),
            ) {
                Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("매치 이름") },
                        placeholder = { Text("예: 잠실 금요 심야전") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = location,
                        onValueChange = { location = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("장소") },
                        placeholder = { Text("예: 잠실 종합운동장 풋살장") },
                        singleLine = true,
                    )

                    OptionSection("레벨", levels, selectedLevel, onSelect = { selectedLevel = it })
                    OptionSection("날짜", dateOptions, selectedDate, label = ::formatDateOnly, onSelect = { selectedDate = it })
                    OptionSection("시간", timeOptions, selectedTime, onSelect = { selectedTime = it })
                    OptionSection("모집 인원", capacities, selectedCapacity, label = { "${it}명" }, onSelect = { selectedCapacity = it })
                    OptionSection("참가비", feeOptions, selectedFee, label = { "${it}원" }, onSelect = { selectedFee = it })

                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("메모") },
                        placeholder = { Text("준비물, 분위기, 유니폼 색상 등을 적어주세요.") },
                        minLines = 3,
                    )

                    Button(
                        onClick = {
                            if (title.isBlank() || location.isBlank()) {
                                showMessage("매치 이름과 장소는 꼭 입력해야 합니다.")
                                return@Button
                            }
                            val localTime = LocalTime.parse(selectedTime)
                            val match = MatchCardData(
                                id = System.currentTimeMillis().toString(),
                                title = title.trim(),
                                location = location.trim(),
                                scheduledAt = LocalDateTime.of(selectedDate, localTime),
                                level = selectedLevel,
                                timeTag = if (localTime.hour >= 18) "야간" else "주간",
                                roleFocus = profile.position,
                                surface = "직접 생성",
                                capacity = selectedCapacity,
                                joinedCount = 1,
                                hostType = "내가 만든 매치",
                                notes = notes.ifBlank { "직접 만든 시연용 매치입니다." },
                                hostName = displayName,
                                hostRating = 5.0,
                                distanceKm = 1.2,
                                createdByUser = true,
                                fee = selectedFee,
                                reviewCount = 0,
                                checkInCode = "FM-${System.currentTimeMillis().toString().takeLast(4)}",
                                amenities = listOf("직접 생성", "호스트 확인", selectedLevel),
                            )
                            onCreateMatch(match)
                            title = ""
                            location = ""
                            notes = ""
                            selectedDate = dateOptions.first()
                            selectedTime = "20:30"
                            selectedLevel = "중급"
                            selectedCapacity = 10
                            selectedFee = 12000
                        },
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        Text("매치 생성하고 일정에 추가")
                    }
                }
            }
        }
    }
}

@Composable
internal fun MatchDetailScreen(
    match: MatchCardData,
    joined: Boolean,
    score: Int,
    bookmarked: Boolean,
    onBack: () -> Unit,
    onJoin: () -> Unit,
    onBookmark: () -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            Button(
                onClick = onJoin,
                enabled = joined || match.joinedCount < match.capacity,
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (joined) TeamBlue else FieldGreen,
                ),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                Text(
                    when {
                        joined -> "참가 취소하기"
                        match.joinedCount >= match.capacity -> "모집 마감"
                        else -> "이 매치 참가하기"
                    },
                )
            }
        },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(appBackground)
                .padding(innerPadding),
            contentPadding = PaddingValues(bottom = 20.dp),
        ) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(320.dp)
                        .background(pitchGradient)
                        .statusBarsPadding()
                        .padding(20.dp),
                ) {
                    PitchLines(alpha = 0.16f)
                    IconButton(
                        onClick = onBack,
                        colors = IconButtonDefaults.filledTonalIconButtonColors(
                            containerColor = Color.White.copy(alpha = 0.18f),
                            contentColor = Color.White,
                        ),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "뒤로")
                    }
                    IconButton(
                        onClick = onBookmark,
                        modifier = Modifier.align(Alignment.TopEnd),
                        colors = IconButtonDefaults.filledTonalIconButtonColors(
                            containerColor = Color.White.copy(alpha = 0.18f),
                            contentColor = Color.White,
                        ),
                    ) {
                        Icon(
                            if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                            contentDescription = "관심 매치",
                        )
                    }
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(bottom = 8.dp),
                    ) {
                        Text(match.hostType.uppercase(), color = Color(0xFFDDF5E3), fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(match.title, color = Color.White, style = MaterialTheme.typography.headlineLarge)
                        Spacer(modifier = Modifier.height(12.dp))
                        TagRow(
                            tags = listOf("$score% 적합", matchStatus(match).label, match.level, match.timeTag, match.roleFocus),
                            bright = true,
                        )
                    }
                }
            }

            item {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    InfoGrid(match = match, score = score)
                    DetailSection(title = "참가 안내") {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            DetailInfoRow(Icons.Filled.QrCode2, "현장 체크인 코드", match.checkInCode)
                            DetailInfoRow(Icons.Filled.Payments, "참가비", "${match.fee}원 · 현장 결제")
                            DetailInfoRow(Icons.Filled.Groups, "모집 상태", "${match.joinedCount}/${match.capacity}명 · ${matchStatus(match).label}")
                        }
                    }
                    DetailSection(title = "매치 설명") {
                        Text(match.notes, style = MaterialTheme.typography.bodyLarge, color = Color(0xFF314032))
                    }
                    DetailSection(title = "호스트 정보") {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(54.dp)
                                    .clip(RoundedCornerShape(18.dp))
                                    .background(Color(0xFFEDF7EF)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Filled.VerifiedUser, contentDescription = null, tint = FieldGreen)
                            }
                            Spacer(modifier = Modifier.width(14.dp))
                            Column {
                                Text(match.hostName, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    "매너 점수 ${"%.1f".format(match.hostRating)} / 5.0 · 리뷰 ${match.reviewCount}개 · 응답 빠름",
                                    color = MutedInk,
                                )
                            }
                        }
                    }
                    DetailSection(title = "시설 정보") {
                        TagRow(tags = match.amenities.ifEmpty { listOf(match.surface, "조끼", "주차 확인 필요") })
                    }
                }
            }
        }
    }
}

@Composable
internal fun InfoGrid(match: MatchCardData, score: Int) {
    val items = listOf(
        "일정" to formatMatchDateTime(match.scheduledAt),
        "장소" to match.location,
        "거리" to "${"%.1f".format(match.distanceKm)}km",
        "모집" to "${match.joinedCount}/${match.capacity}명",
        "실력대" to match.level,
        "추천도" to "${score}점",
    )

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.chunked(2).forEach { rowItems ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                rowItems.forEach { item ->
                    Card(
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(20.dp),
                        colors = CardDefaults.cardColors(containerColor = Color.White),
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(104.dp)
                                .padding(14.dp),
                        ) {
                            Text(item.first, color = MutedInk, fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.weight(1f))
                            Text(
                                item.second,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Bold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
                if (rowItems.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
internal fun DetailSection(title: String, content: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(22.dp),
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            content()
        }
    }
}

@Composable
internal fun DetailInfoRow(icon: ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFEDF7EF)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(20.dp))
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(label, color = MutedInk, style = MaterialTheme.typography.bodyMedium)
            Text(value, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
internal fun HostPreviewCard(title: String, date: LocalDate, time: String, level: String, capacity: Int, fee: Int) {
    Card(
        colors = CardDefaults.cardColors(containerColor = PitchDark),
        shape = RoundedCornerShape(26.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Brush.linearGradient(listOf(PitchDark, Color(0xFF223A26))))
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(width = 86.dp, height = 96.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color.White.copy(alpha = 0.10f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    formatDateOnly(date),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    fontWeight = FontWeight.ExtraBold,
                )
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text("HOST PREVIEW", color = Color(0xFFDDF5E3), fontWeight = FontWeight.Bold)
                Text(title, color = Color.White, style = MaterialTheme.typography.titleLarge)
                Spacer(modifier = Modifier.height(4.dp))
                Text("$time · $level · ${capacity}명 모집 · ${fee}원", color = Color(0xFFDDF7E4))
            }
        }
    }
}

@Composable
internal fun ScheduleSummaryCard(nextMatch: MatchCardData, totalCount: Int) {
    Card(
        colors = CardDefaults.cardColors(containerColor = PitchDark),
        shape = RoundedCornerShape(26.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Brush.linearGradient(listOf(PitchDark, FieldGreen)))
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(62.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.White.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.CalendarMonth, contentDescription = null, tint = Color.White)
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text("NEXT MATCH", color = Color(0xFFDDF5E3), fontWeight = FontWeight.Bold)
                Text(nextMatch.title, color = Color.White, style = MaterialTheme.typography.titleLarge)
                Text(
                    "${formatMatchDateTime(nextMatch.scheduledAt)} · 체크인 ${nextMatch.checkInCode}",
                    color = Color(0xFFDDF7E4),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(totalCount.toString(), color = Color.White, fontWeight = FontWeight.ExtraBold)
            }
        }
    }
}

@Composable
internal fun ScheduleCard(match: MatchCardData, statusLabel: String) {
    ElevatedCard(
        colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
        shape = RoundedCornerShape(26.dp),
    ) {
        Row(
            modifier = Modifier.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            DateBadge(match.scheduledAt, compact = true)
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(match.title, style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "${formatMatchDateTime(match.scheduledAt)} | ${match.location}",
                    color = MutedInk,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.QrCode2, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("체크인 ${match.checkInCode}", color = FieldGreen, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("참가비 ${match.fee}원", color = MutedInk)
                }
            }
            Spacer(modifier = Modifier.width(10.dp))
            TagChip(statusLabel)
        }
    }
}
