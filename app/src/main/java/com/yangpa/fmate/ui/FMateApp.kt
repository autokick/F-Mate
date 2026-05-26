package com.yangpa.fmate.ui

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
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

private val appBackground = Brush.verticalGradient(
    listOf(Color(0xFFF8F3E8), Color(0xFFF1EADB)),
)

private val pitchGradient = Brush.linearGradient(
    listOf(FieldGreen, Color(0xFF0E612F), PitchDark),
)

private val dateTimeFormatter = DateTimeFormatter.ofPattern("MM.dd (E) HH:mm", Locale.KOREAN)
private val dateOnlyFormatter = DateTimeFormatter.ofPattern("MM.dd (E)", Locale.KOREAN)

@Composable
fun FMateApp() {
    FMateTheme {
        Surface(color = WarmSand) {
            val matches = remember {
                mutableStateListOf<MatchCardData>().apply {
                    addAll(sampleMatches())
                }
            }
            val joinedMatchIds = remember { mutableStateListOf("m2", "m3") }
            val snackbarHostState = remember { SnackbarHostState() }
            val scope = rememberCoroutineScope()

            var enteredApp by remember { mutableStateOf(false) }
            var displayName by remember { mutableStateOf("이민수") }
            var profile by remember {
                mutableStateOf(
                    PlayerProfile(
                        position = "윙어",
                        skill = "중급",
                        timePreference = "야간",
                    ),
                )
            }
            var selectedMatchId by remember { mutableStateOf<String?>(null) }

            fun showMessage(text: String) {
                scope.launch {
                    snackbarHostState.showSnackbar(text)
                }
            }

            fun scoreMatch(match: MatchCardData): Int {
                var score = 58
                if (match.level == profile.skill) score += 18
                if (match.timeTag == profile.timePreference) score += 12
                if (match.roleFocus == profile.position) score += 10
                if (match.level == "상급" && profile.skill == "초급") score -= 10
                if (match.level == "초급" && profile.skill == "상급") score -= 8
                return score.coerceIn(46, 97)
            }

            fun toggleJoin(match: MatchCardData) {
                val index = matches.indexOfFirst { it.id == match.id }
                if (index == -1) return

                val alreadyJoined = joinedMatchIds.contains(match.id)
                if (!alreadyJoined && match.joinedCount >= match.capacity) {
                    showMessage("이 매치는 이미 모집이 마감되었습니다.")
                    return
                }

                if (alreadyJoined) {
                    joinedMatchIds.remove(match.id)
                    matches[index] = match.copy(joinedCount = match.joinedCount - 1)
                    showMessage("참가를 취소했습니다.")
                } else {
                    joinedMatchIds.add(match.id)
                    matches[index] = match.copy(joinedCount = match.joinedCount + 1)
                    showMessage("매치가 일정에 추가되었습니다.")
                }
            }

            val selectedMatch = selectedMatchId?.let { id -> matches.firstOrNull { it.id == id } }

            when {
                !enteredApp -> EntryFlow(
                    onComplete = { name ->
                        displayName = name.ifBlank { "이민수" }
                        enteredApp = true
                    },
                )

                selectedMatch != null -> MatchDetailScreen(
                    match = selectedMatch,
                    joined = joinedMatchIds.contains(selectedMatch.id),
                    score = scoreMatch(selectedMatch),
                    onBack = { selectedMatchId = null },
                    onJoin = { toggleJoin(selectedMatch) },
                    snackbarHostState = snackbarHostState,
                )

                else -> MainShell(
                    displayName = displayName,
                    matches = matches,
                    joinedMatchIds = joinedMatchIds,
                    profile = profile,
                    scoreMatch = ::scoreMatch,
                    onProfileChange = { profile = it },
                    onOpenMatch = { selectedMatchId = it.id },
                    onToggleJoin = ::toggleJoin,
                    onCreateMatch = { match ->
                        matches.add(0, match)
                        joinedMatchIds.add(match.id)
                        showMessage("새 매치를 만들고 일정에 바로 추가했습니다.")
                    },
                    snackbarHostState = snackbarHostState,
                    showMessage = ::showMessage,
                )
            }
        }
    }
}

@Composable
private fun EntryFlow(onComplete: (String) -> Unit) {
    val slides = remember {
        listOf(
            OnboardingSlide(
                title = "매치 탐색을\n진짜 빠르게",
                body = "필터와 추천 점수로 단톡방을 뒤지지 않고 바로 경기 후보를 찾습니다.",
                icon = Icons.Filled.Explore,
                accent = FieldGreen,
            ),
            OnboardingSlide(
                title = "참가부터 일정까지\n한 흐름으로",
                body = "참가 버튼 한 번이면 일정 탭에 자동 반영되어 매치 관리가 끊기지 않습니다.",
                icon = Icons.Filled.CalendarMonth,
                accent = CitrusOrange,
            ),
            OnboardingSlide(
                title = "프로필 기반 추천으로\n고민 줄이기",
                body = "포지션, 실력, 선호 시간에 맞춰 잘 맞는 경기부터 위로 끌어올립니다.",
                icon = Icons.Filled.AutoAwesome,
                accent = TeamBlue,
            ),
        )
    }

    var pageIndex by remember { mutableStateOf(0) }
    var showLogin by remember { mutableStateOf(false) }
    var nickname by remember { mutableStateOf("이민수") }
    var email by remember { mutableStateOf("20220000@univ.ac.kr") }

    if (showLogin) {
        LoginScreen(
            nickname = nickname,
            email = email,
            onNicknameChange = { nickname = it },
            onEmailChange = { email = it },
            onBack = { showLogin = false },
            onEnter = { onComplete(nickname.trim()) },
        )
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(appBackground)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "F-MATE",
                style = MaterialTheme.typography.headlineMedium,
                color = Ink,
            )
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = { showLogin = true }) {
                Text("건너뛰기")
            }
        }

        Spacer(modifier = Modifier.height(18.dp))

        OnboardingVisual(
            slide = slides[pageIndex],
            modifier = Modifier.weight(1f),
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = slides[pageIndex].body,
            color = MutedInk,
            style = MaterialTheme.typography.bodyLarge,
        )

        Spacer(modifier = Modifier.height(18.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
        ) {
            slides.forEachIndexed { index, _ ->
                Box(
                    modifier = Modifier
                        .padding(horizontal = 4.dp)
                        .size(width = if (index == pageIndex) 30.dp else 10.dp, height = 10.dp)
                        .clip(RoundedCornerShape(99.dp))
                        .background(if (index == pageIndex) PitchDark else Color(0x22000000)),
                )
            }
        }

        Spacer(modifier = Modifier.height(18.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(
                onClick = { showLogin = true },
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                Text("바로 보기")
            }
            Button(
                onClick = {
                    if (pageIndex == slides.lastIndex) {
                        showLogin = true
                    } else {
                        pageIndex += 1
                    }
                },
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                Text(if (pageIndex == slides.lastIndex) "시작하기" else "다음")
            }
        }
    }
}

@Composable
private fun OnboardingVisual(slide: OnboardingSlide, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(34.dp))
            .background(Brush.linearGradient(listOf(slide.accent, PitchDark))),
    ) {
        PitchLines(alpha = 0.12f)
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(24.dp)
                .size(150.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f)),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(24.dp),
        ) {
            Text(
                text = "PLAY SMART",
                color = Color.White.copy(alpha = 0.78f),
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.6.sp,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = slide.title,
                    modifier = Modifier.weight(1f),
                    color = Color.White,
                    style = MaterialTheme.typography.headlineLarge,
                )
                Box(
                    modifier = Modifier
                        .size(86.dp)
                        .clip(RoundedCornerShape(26.dp))
                        .background(Color.White.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(slide.icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(40.dp))
                }
            }
        }
    }
}

@Composable
private fun LoginScreen(
    nickname: String,
    email: String,
    onNicknameChange: (String) -> Unit,
    onEmailChange: (String) -> Unit,
    onBack: () -> Unit,
    onEnter: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(PitchDark, FieldGreen)))
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(20.dp),
    ) {
        IconButton(
            onClick = onBack,
            colors = IconButtonDefaults.filledTonalIconButtonColors(),
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "뒤로")
        }
        Spacer(modifier = Modifier.height(22.dp))
        Text(
            text = "TEAM READY?\n들어가자.",
            color = Color.White,
            style = MaterialTheme.typography.headlineLarge,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "실제 인증 대신 발표용 입장 화면입니다. 학교 이메일과 닉네임만 넣고 바로 MVP 화면으로 들어갑니다.",
            color = Color(0xFFDDF7E4),
            style = MaterialTheme.typography.bodyLarge,
        )
        Spacer(modifier = Modifier.height(28.dp))
        ElevatedCard(
            colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
            shape = RoundedCornerShape(28.dp),
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                OutlinedTextField(
                    value = email,
                    onValueChange = onEmailChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("학교 이메일") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = nickname,
                    onValueChange = onNicknameChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("프로필 이름") },
                    singleLine = true,
                )
                Button(
                    onClick = onEnter,
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(vertical = 16.dp),
                ) {
                    Icon(Icons.AutoMirrored.Filled.Login, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("프로토타입 입장")
                }
            }
        }
    }
}

@Composable
private fun MainShell(
    displayName: String,
    matches: List<MatchCardData>,
    joinedMatchIds: List<String>,
    profile: PlayerProfile,
    scoreMatch: (MatchCardData) -> Int,
    onProfileChange: (PlayerProfile) -> Unit,
    onOpenMatch: (MatchCardData) -> Unit,
    onToggleJoin: (MatchCardData) -> Unit,
    onCreateMatch: (MatchCardData) -> Unit,
    snackbarHostState: SnackbarHostState,
    showMessage: (String) -> Unit,
) {
    var selectedTab by remember { mutableStateOf(FMateTab.Matches) }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            NavigationBar(
                modifier = Modifier.navigationBarsPadding(),
                containerColor = Color.White.copy(alpha = 0.94f),
            ) {
                FMateTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = {
                            Icon(
                                imageVector = if (selectedTab == tab) tab.selectedIcon else tab.icon,
                                contentDescription = tab.label,
                            )
                        },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(appBackground)
                .padding(innerPadding),
        ) {
            AppHeader(
                displayName = displayName,
                onProfileClick = { selectedTab = FMateTab.Profile },
            )

            when (selectedTab) {
                FMateTab.Matches -> MatchListScreen(
                    matches = matches,
                    joinedMatchIds = joinedMatchIds,
                    profile = profile,
                    scoreMatch = scoreMatch,
                    onOpenMatch = onOpenMatch,
                    onToggleJoin = onToggleJoin,
                    onCreateClick = { selectedTab = FMateTab.Create },
                )

                FMateTab.Schedule -> ScheduleScreen(
                    matches = matches.filter { joinedMatchIds.contains(it.id) },
                )

                FMateTab.Create -> CreateMatchScreen(
                    displayName = displayName,
                    profile = profile,
                    onCreateMatch = { match ->
                        onCreateMatch(match)
                        selectedTab = FMateTab.Schedule
                    },
                    showMessage = showMessage,
                )

                FMateTab.Profile -> ProfileScreen(
                    displayName = displayName,
                    profile = profile,
                    bestScore = matches.maxOfOrNull(scoreMatch) ?: 0,
                    onProfileChange = onProfileChange,
                )
            }
        }
    }
}

@Composable
private fun AppHeader(displayName: String, onProfileClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(start = 20.dp, top = 16.dp, end = 20.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Brush.linearGradient(listOf(FieldGreen, FreshGreen))),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.SportsSoccer, contentDescription = null, tint = Color.White)
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text("F-MATE", style = MaterialTheme.typography.titleLarge, color = Ink)
            Text(
                "$displayName 님을 위한 매치데이 추천",
                style = MaterialTheme.typography.bodyMedium,
                color = MutedInk,
            )
        }
        IconButton(
            onClick = onProfileClick,
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = Color(0xFFD7F2DD),
                contentColor = FieldGreen,
            ),
        ) {
            Icon(Icons.Filled.Tune, contentDescription = "프로필 설정")
        }
    }
}

@Composable
private fun MatchListScreen(
    matches: List<MatchCardData>,
    joinedMatchIds: List<String>,
    profile: PlayerProfile,
    scoreMatch: (MatchCardData) -> Int,
    onOpenMatch: (MatchCardData) -> Unit,
    onToggleJoin: (MatchCardData) -> Unit,
    onCreateClick: () -> Unit,
) {
    var selectedFilter by remember { mutableStateOf(MatchFilter.All) }
    val rankedMatches = matches.sortedByDescending(scoreMatch)
    val bestMatch = rankedMatches.firstOrNull()
    val filteredMatches = rankedMatches.filter { match ->
        when (selectedFilter) {
            MatchFilter.All -> true
            MatchFilter.Beginner -> match.level == "초급"
            MatchFilter.Intermediate -> match.level == "중급"
            MatchFilter.Night -> match.timeTag == "야간"
        }
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
                    scheduledCount = joinedMatchIds.size,
                    onOpen = { onOpenMatch(bestMatch) },
                    onJoin = { onToggleJoin(bestMatch) },
                )
            }
        }

        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                MetricCard("참가 중 일정", joinedMatchIds.size.toString(), FieldGreen)
                MetricCard("직접 만든 매치", matches.count { it.createdByUser }.toString(), CitrusOrange)
                MetricCard("추천 최고 점수", "${bestMatch?.let(scoreMatch) ?: 0}%", TeamBlue)
            }
        }

        item {
            SectionHeading(
                subtitle = "Discover",
                title = "추천 매치",
                caption = "프로필에 맞는 매치를 먼저 보여주고 참가 버튼은 일정 탭에 바로 반영됩니다.",
            )
        }

        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                MatchFilter.entries.forEach { filter ->
                    FilterChip(
                        selected = selectedFilter == filter,
                        onClick = { selectedFilter = filter },
                        label = { Text(filter.label) },
                    )
                }
            }
        }

        items(filteredMatches, key = { it.id }) { match ->
            MatchCard(
                match = match,
                joined = joinedMatchIds.contains(match.id),
                score = scoreMatch(match),
                onTap = { onOpenMatch(match) },
                onJoin = { onToggleJoin(match) },
            )
        }

        item {
            FlowCard(onCreateClick = onCreateClick)
        }
    }
}

@Composable
private fun FeaturedMatchCard(
    match: MatchCardData,
    score: Int,
    profile: PlayerProfile,
    joined: Boolean,
    scheduledCount: Int,
    onOpen: () -> Unit,
    onJoin: () -> Unit,
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
                    tags = listOf("$score% 적합", match.level, match.timeTag, match.roleFocus),
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
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    ) {
                        Text(if (joined) "참가 취소" else "바로 참가")
                    }
                }
            }
        }
    }
}

@Composable
private fun MatchCard(
    match: MatchCardData,
    joined: Boolean,
    score: Int,
    onTap: () -> Unit,
    onJoin: () -> Unit,
) {
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
                    Text(match.level, color = CitrusOrange, fontWeight = FontWeight.ExtraBold)
                }
                Spacer(modifier = Modifier.height(10.dp))
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
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(if (joined) "참가 취소" else "참가 신청")
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
private fun ScheduleScreen(matches: List<MatchCardData>) {
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
private fun CreateMatchScreen(
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

    var title by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var selectedDate by remember { mutableStateOf(dateOptions.first()) }
    var selectedTime by remember { mutableStateOf("20:30") }
    var selectedLevel by remember { mutableStateOf("중급") }
    var selectedCapacity by remember { mutableStateOf(10) }

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
                            )
                            onCreateMatch(match)
                            title = ""
                            location = ""
                            notes = ""
                            selectedDate = dateOptions.first()
                            selectedTime = "20:30"
                            selectedLevel = "중급"
                            selectedCapacity = 10
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
private fun ProfileScreen(
    displayName: String,
    profile: PlayerProfile,
    bestScore: Int,
    onProfileChange: (PlayerProfile) -> Unit,
) {
    val positions = listOf("윙어", "피보", "수비", "골키퍼")
    val levels = listOf("초급", "중급", "상급")
    val timePreferences = listOf("주간", "야간")
    val reasons = listOf(
        "${profile.skill} 실력대와 맞는 매치를 우선 추천합니다.",
        "${profile.timePreference} 시간대 선호가 추천도에 반영됩니다.",
        "${profile.position} 포지션 수요가 있는 매치가 상단에 노출됩니다.",
    )

    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionHeading(
                subtitle = "Profile",
                title = "내 프로필",
                caption = "프로필을 바꾸면 추천 매치 우선순위가 즉시 갱신됩니다.",
            )
        }

        item {
            ElevatedCard(
                colors = CardDefaults.elevatedCardColors(containerColor = Color(0xFFFFF9ED)),
                shape = RoundedCornerShape(28.dp),
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(62.dp)
                                .clip(RoundedCornerShape(20.dp))
                                .background(Color(0x140F8F43)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Person, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(34.dp))
                        }
                        Spacer(modifier = Modifier.width(14.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(displayName, style = MaterialTheme.typography.headlineMedium)
                            Text(
                                "${profile.position} | ${profile.skill} | ${profile.timePreference} 선호",
                                color = MutedInk,
                            )
                        }
                    }

                    TagRow(
                        tags = listOf(profile.position, profile.skill, profile.timePreference, "추천 ${bestScore}점"),
                    )

                    OptionSection("포지션", positions, profile.position, onSelect = {
                        onProfileChange(profile.copy(position = it))
                    })
                    OptionSection("실력", levels, profile.skill, onSelect = {
                        onProfileChange(profile.copy(skill = it))
                    })
                    OptionSection("선호 시간", timePreferences, profile.timePreference, onSelect = {
                        onProfileChange(profile.copy(timePreference = it))
                    })
                }
            }
        }

        item {
            SectionHeading(
                subtitle = "Insight",
                title = "추천 사유",
                caption = "발표 때는 이 점수 로직을 간단히 설명하면 됩니다.",
            )
        }

        items(reasons) { reason ->
            InsightCard(text = reason)
        }
    }
}

@Composable
private fun MatchDetailScreen(
    match: MatchCardData,
    joined: Boolean,
    score: Int,
    onBack: () -> Unit,
    onJoin: () -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            Button(
                onClick = onJoin,
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (joined) TeamBlue else FieldGreen,
                ),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                Text(if (joined) "참가 취소하기" else "이 매치 참가하기")
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
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(bottom = 8.dp),
                    ) {
                        Text(match.hostType.uppercase(), color = Color(0xFFDDF5E3), fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(match.title, color = Color.White, style = MaterialTheme.typography.headlineLarge)
                        Spacer(modifier = Modifier.height(12.dp))
                        TagRow(tags = listOf("$score% 적합", match.level, match.timeTag, match.roleFocus), bright = true)
                    }
                }
            }

            item {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    InfoGrid(match = match, score = score)
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
                                    "매너 점수 ${"%.1f".format(match.hostRating)} / 5.0 · 응답 빠름",
                                    color = MutedInk,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoGrid(match: MatchCardData, score: Int) {
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
private fun DetailSection(title: String, content: @Composable () -> Unit) {
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
private fun HostPreviewCard(title: String, date: LocalDate, time: String, level: String, capacity: Int) {
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
                Text("$time · $level · ${capacity}명 모집", color = Color(0xFFDDF7E4))
            }
        }
    }
}

@Composable
private fun ScheduleCard(match: MatchCardData, statusLabel: String) {
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
            }
            Spacer(modifier = Modifier.width(10.dp))
            TagChip(statusLabel)
        }
    }
}

@Composable
private fun InsightCard(text: String) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(22.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color(0x140F8F43)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(18.dp))
            }
            Spacer(modifier = Modifier.width(12.dp))
            Text(text, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun FlowCard(onCreateClick: () -> Unit) {
    val steps = listOf(
        "01" to "매치 탐색",
        "02" to "즉시 참가",
        "03" to "일정 반영",
        "04" to "직접 개설",
    )

    Card(
        colors = CardDefaults.cardColors(containerColor = PitchDark),
        shape = RoundedCornerShape(26.dp),
    ) {
        Column(
            modifier = Modifier
                .background(Brush.linearGradient(listOf(PitchDark, Color(0xFF223A26))))
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(
                subtitle = "Prototype Scope",
                title = "시연 흐름",
                caption = "탐색, 상세, 참가, 일정 반영, 생성 흐름을 한 번에 확인합니다.",
                bright = true,
            )
            steps.forEach { (number, label) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(alpha = 0.10f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(number, color = Color.White, fontWeight = FontWeight.ExtraBold)
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(label, color = Color.White, style = MaterialTheme.typography.titleMedium)
                }
            }
            Button(
                onClick = onCreateClick,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = FieldGreen),
            ) {
                Text("새 매치 만들기")
            }
        }
    }
}

@Composable
private fun EmptyCard(title: String, description: String) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(26.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Icons.Filled.EventAvailable, contentDescription = null, tint = FieldGreen, modifier = Modifier.size(42.dp))
            Spacer(modifier = Modifier.height(12.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.height(6.dp))
            Text(description, color = MutedInk, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun MetricCard(label: String, value: String, accent: Color) {
    Card(
        modifier = Modifier.width(158.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(22.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(label, color = MutedInk, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))
            Text(value, color = accent, style = MaterialTheme.typography.headlineMedium)
        }
    }
}

@Composable
private fun SectionHeading(subtitle: String, title: String, caption: String, bright: Boolean = false) {
    val titleColor = if (bright) Color.White else Ink
    val mutedColor = if (bright) Color(0xFFD5DDD3) else MutedInk

    Column {
        Text(
            subtitle.uppercase(),
            color = mutedColor,
            fontSize = 13.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 1.2.sp,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(title, color = titleColor, style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(6.dp))
        Text(caption, color = mutedColor, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun DateBadge(dateTime: LocalDateTime, compact: Boolean = false) {
    val width = if (compact) 72.dp else 88.dp
    val height = if (compact) 82.dp else 112.dp

    Column(
        modifier = Modifier
            .size(width = width, height = height)
            .clip(RoundedCornerShape(22.dp))
            .background(Brush.verticalGradient(listOf(PitchDark, FieldGreen)))
            .padding(vertical = 10.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = dateTime.format(DateTimeFormatter.ofPattern("MM.dd", Locale.KOREAN)),
            color = Color.White,
            fontWeight = FontWeight.ExtraBold,
            fontSize = if (compact) 18.sp else 22.sp,
        )
        Text(
            text = dateTime.format(DateTimeFormatter.ofPattern("E", Locale.KOREAN)),
            color = Color(0xFFD4F5DF),
            fontWeight = FontWeight.Bold,
        )
        if (!compact) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = dateTime.format(DateTimeFormatter.ofPattern("HH:mm")),
                color = Color(0xFFFFE9D7),
                fontWeight = FontWeight.ExtraBold,
            )
        }
    }
}

@Composable
private fun TagRow(tags: List<String>, bright: Boolean = false) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        tags.forEach { tag ->
            TagChip(label = tag, bright = bright)
        }
    }
}

@Composable
private fun TagChip(label: String, bright: Boolean = false) {
    AssistChip(
        onClick = {},
        label = { Text(label, fontWeight = FontWeight.Bold) },
        colors = androidx.compose.material3.AssistChipDefaults.assistChipColors(
            containerColor = if (bright) Color.White.copy(alpha = 0.14f) else Color(0xFFEDF7EF),
            labelColor = if (bright) Color.White else FieldGreen,
        ),
        border = null,
    )
}

@Composable
private fun <T> OptionSection(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String = { it.toString() },
    onSelect: (T) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { option ->
                FilterChip(
                    selected = option == selected,
                    onClick = { onSelect(option) },
                    label = { Text(label(option)) },
                    leadingIcon = if (option == selected) {
                        { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else {
                        null
                    },
                )
            }
        }
    }
}

@Composable
private fun PitchLines(alpha: Float) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val paint = Stroke(width = 1.6.dp.toPx())
        val color = Color.White.copy(alpha = alpha)
        drawRoundRect(
            color = color,
            topLeft = Offset(14.dp.toPx(), 14.dp.toPx()),
            size = Size(size.width - 28.dp.toPx(), size.height - 28.dp.toPx()),
            cornerRadius = CornerRadius(26.dp.toPx(), 26.dp.toPx()),
            style = paint,
        )
        drawLine(
            color = color,
            start = Offset(size.width / 2, 14.dp.toPx()),
            end = Offset(size.width / 2, size.height - 14.dp.toPx()),
            strokeWidth = 1.6.dp.toPx(),
        )
        drawCircle(
            color = color,
            radius = size.width * 0.12f,
            center = Offset(size.width / 2, size.height / 2),
            style = paint,
        )
        drawRoundRect(
            color = color,
            topLeft = Offset(14.dp.toPx(), size.height * 0.32f),
            size = Size(size.width * 0.16f, size.height * 0.36f),
            cornerRadius = CornerRadius(18.dp.toPx(), 18.dp.toPx()),
            style = paint,
        )
        drawRoundRect(
            color = color,
            topLeft = Offset(size.width - size.width * 0.16f - 14.dp.toPx(), size.height * 0.32f),
            size = Size(size.width * 0.16f, size.height * 0.36f),
            cornerRadius = CornerRadius(18.dp.toPx(), 18.dp.toPx()),
            style = paint,
        )
    }
}

private fun formatMatchDateTime(dateTime: LocalDateTime): String = dateTime.format(dateTimeFormatter)

private fun formatDateOnly(date: LocalDate): String = date.format(dateOnlyFormatter)

private data class OnboardingSlide(
    val title: String,
    val body: String,
    val icon: ImageVector,
    val accent: Color,
)

private enum class FMateTab(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
) {
    Matches("매치", Icons.Outlined.Explore, Icons.Filled.Explore),
    Schedule("일정", Icons.Outlined.CalendarMonth, Icons.Filled.CalendarMonth),
    Create("생성", Icons.Outlined.AddCircleOutline, Icons.Filled.AddCircle),
    Profile("프로필", Icons.Outlined.PersonOutline, Icons.Filled.Person),
}
