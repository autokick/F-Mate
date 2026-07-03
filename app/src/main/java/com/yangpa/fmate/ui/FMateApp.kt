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

internal val appBackground = Brush.verticalGradient(
    listOf(Color(0xFFF8F3E8), Color(0xFFF1EADB)),
)

internal val pitchGradient = Brush.linearGradient(
    listOf(FieldGreen, Color(0xFF0E612F), PitchDark),
)

internal val dateTimeFormatter = DateTimeFormatter.ofPattern("MM.dd (E) HH:mm", Locale.KOREAN)
internal val dateOnlyFormatter = DateTimeFormatter.ofPattern("MM.dd (E)", Locale.KOREAN)

@Composable
fun FMateApp() {
    FMateTheme {
        val context = LocalContext.current
        val demoStore = remember(context) { LocalDemoStore(context) }
        val initialSnapshot = remember(demoStore) { demoStore.load() }

        Surface(color = WarmSand) {
            val defaultMatches = remember { sampleMatches() }
            val matches = remember {
                mutableStateListOf<MatchCardData>().apply {
                    val storedMatches = initialSnapshot?.matches.orEmpty()
                    val mergedMatches = if (storedMatches.isEmpty()) {
                        defaultMatches
                    } else {
                        storedMatches + defaultMatches.filter { sample ->
                            storedMatches.none { it.id == sample.id }
                        }
                    }
                    addAll(mergedMatches)
                }
            }
            val joinedMatchIds = remember {
                mutableStateListOf<String>().apply {
                    addAll(initialSnapshot?.joinedMatchIds ?: listOf("m2", "m3"))
                }
            }
            val bookmarkedMatchIds = remember {
                mutableStateListOf<String>().apply {
                    addAll(initialSnapshot?.bookmarkedMatchIds ?: listOf("m1", "m5"))
                }
            }
            val snackbarHostState = remember { SnackbarHostState() }
            val scope = rememberCoroutineScope()

            var enteredApp by remember { mutableStateOf(initialSnapshot?.enteredApp ?: false) }
            var displayName by remember { mutableStateOf(initialSnapshot?.displayName ?: "홍길동") }
            var userEmail by remember { mutableStateOf("20220000@seoil.ac.kr") }
            var profile by remember {
                mutableStateOf(
                    initialSnapshot?.profile ?: PlayerProfile(
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

            fun persistState(
                nextMatches: List<MatchCardData> = matches.toList(),
                nextJoinedMatchIds: List<String> = joinedMatchIds.toList(),
                nextBookmarkedMatchIds: List<String> = bookmarkedMatchIds.toList(),
                nextDisplayName: String = displayName,
                nextProfile: PlayerProfile = profile,
                nextEnteredApp: Boolean = enteredApp,
            ) {
                demoStore.save(
                    DemoSnapshot(
                        matches = nextMatches,
                        joinedMatchIds = nextJoinedMatchIds,
                        bookmarkedMatchIds = nextBookmarkedMatchIds,
                        displayName = nextDisplayName,
                        profile = nextProfile,
                        enteredApp = nextEnteredApp,
                    ),
                )
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
                    persistState()
                    showMessage("참가를 취소했습니다.")
                } else {
                    joinedMatchIds.add(match.id)
                    matches[index] = match.copy(joinedCount = match.joinedCount + 1)
                    persistState()
                    showMessage("매치가 일정에 추가되었습니다.")
                }
            }

            fun toggleBookmark(match: MatchCardData) {
                val alreadyBookmarked = bookmarkedMatchIds.contains(match.id)
                if (alreadyBookmarked) {
                    bookmarkedMatchIds.remove(match.id)
                    showMessage("관심 매치에서 제거했습니다.")
                } else {
                    bookmarkedMatchIds.add(match.id)
                    showMessage("관심 매치에 추가했습니다.")
                }
                persistState()
            }

            val selectedMatch = selectedMatchId?.let { id -> matches.firstOrNull { it.id == id } }

            when {
                !enteredApp -> EntryFlow(
                    onComplete = { name, email ->
                        val nextDisplayName = name.ifBlank { "홍길동" }
                        val nextEmail = email.ifBlank { "20220000@seoil.ac.kr" }

                        displayName = nextDisplayName
                        userEmail = nextEmail
                        enteredApp = true

                        saveUserToFirebase(
                            nickname = nextDisplayName,
                            email = nextEmail,
                            profile = profile
                        )

                        persistState(
                            nextDisplayName = nextDisplayName,
                            nextEnteredApp = true
                        )
                    },
                )

                selectedMatch != null -> MatchDetailScreen(
                    match = selectedMatch,
                    joined = joinedMatchIds.contains(selectedMatch.id),
                    score = scoreMatch(selectedMatch),
                    bookmarked = bookmarkedMatchIds.contains(selectedMatch.id),
                    onBack = { selectedMatchId = null },
                    onJoin = { toggleJoin(selectedMatch) },
                    onBookmark = { toggleBookmark(selectedMatch) },
                    snackbarHostState = snackbarHostState,
                )

                else -> MainShell(
                    displayName = displayName,
                    userEmail = userEmail,
                    matches = matches,
                    joinedMatchIds = joinedMatchIds,
                    bookmarkedMatchIds = bookmarkedMatchIds,
                    profile = profile,
                    scoreMatch = ::scoreMatch,
                    onProfileChange = {
                        profile = it
                        persistState(nextProfile = it)

                        updateUserProfileToFirebase(
                            email = userEmail,
                            profile = it
                        )
                    },
                    onOpenMatch = { selectedMatchId = it.id },
                    onToggleJoin = ::toggleJoin,
                    onToggleBookmark = ::toggleBookmark,
                    onCreateMatch = { match ->
                        matches.add(0, match)
                        joinedMatchIds.add(match.id)
                        persistState()
                        showMessage("새 매치를 만들고 일정에 바로 추가했습니다.")
                    },
                    onResetDemo = {
                        demoStore.clear()
                        matches.clear()
                        matches.addAll(defaultMatches)
                        joinedMatchIds.clear()
                        joinedMatchIds.addAll(listOf("m2", "m3"))
                        bookmarkedMatchIds.clear()
                        bookmarkedMatchIds.addAll(listOf("m1", "m5"))
                        profile = PlayerProfile(position = "윙어", skill = "중급", timePreference = "야간")
                        displayName = "홍길동"
                        enteredApp = false
                        showMessage("시연 데이터를 초기화했습니다.")
                    },
                    snackbarHostState = snackbarHostState,
                    showMessage = ::showMessage,
                )
            }
        }
    }
}

@Composable
internal fun MainShell(
    displayName: String,
    userEmail: String,
    matches: List<MatchCardData>,
    joinedMatchIds: List<String>,
    bookmarkedMatchIds: List<String>,
    profile: PlayerProfile,
    scoreMatch: (MatchCardData) -> Int,
    onProfileChange: (PlayerProfile) -> Unit,
    onOpenMatch: (MatchCardData) -> Unit,
    onToggleJoin: (MatchCardData) -> Unit,
    onToggleBookmark: (MatchCardData) -> Unit,
    onCreateMatch: (MatchCardData) -> Unit,
    onResetDemo: () -> Unit,
    snackbarHostState: SnackbarHostState,
    showMessage: (String) -> Unit,
) {
    var selectedTab by remember { mutableStateOf(FMateTab.Matches) }
    var users by remember { mutableStateOf<List<UserProfile>>(emptyList()) }
    var friends by remember { mutableStateOf<List<UserProfile>>(emptyList()) }
    var selectedUser by remember { mutableStateOf<UserProfile?>(null) }
    var chatUser by remember { mutableStateOf<UserProfile?>(null) }
    var usersLoading by remember { mutableStateOf(false) }
    var friendsLoading by remember { mutableStateOf(false) }

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

            if (chatUser != null) {
                ChatScreen(
                    myEmail = userEmail,
                    user = chatUser!!,
                    showMessage = showMessage,
                    onBack = {
                        chatUser = null
                    }
                )
            } else {
                when (selectedTab) {
                    FMateTab.Matches -> MatchListScreen(
                        matches = matches,
                        joinedMatchIds = joinedMatchIds,
                        bookmarkedMatchIds = bookmarkedMatchIds,
                        profile = profile,
                        scoreMatch = scoreMatch,
                        onOpenMatch = onOpenMatch,
                        onToggleJoin = onToggleJoin,
                        onToggleBookmark = onToggleBookmark,
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

                    FMateTab.Users -> {
                        if (selectedUser == null) {
                            FriendsScreen(
                                myEmail = userEmail,
                                users = users,
                                friends = friends,
                                usersLoading = usersLoading,
                                friendsLoading = friendsLoading,
                                onRefreshUsers = {
                                    usersLoading = true
                                    loadUsersFromFirebase(
                                        onSuccess = { loadedUsers ->
                                            users = loadedUsers
                                            usersLoading = false
                                        },
                                        onFailure = {
                                            usersLoading = false
                                            showMessage("유저 목록을 불러오지 못했습니다.")
                                        }
                                    )
                                },
                                onRefreshFriends = {
                                    friendsLoading = true
                                    loadFriendsFromFirebase(
                                        myEmail = userEmail,
                                        onSuccess = { loadedFriends ->
                                            friends = loadedFriends
                                            friendsLoading = false
                                        },
                                        onFailure = {
                                            friendsLoading = false
                                            showMessage("친구 목록을 불러오지 못했습니다.")
                                        }
                                    )
                                },
                                onAddFriend = { user ->
                                    addFriendToFirebase(
                                        myEmail = userEmail,
                                        friend = user,
                                        onSuccess = {
                                            friends = friends + user
                                            showMessage("친구로 추가했습니다.")
                                        },
                                        onFailure = {
                                            showMessage("친구 추가에 실패했습니다.")
                                        }
                                    )
                                },
                                onUserClick = { user ->
                                    selectedUser = user
                                }
                            )
                        } else {
                            UserDetailScreen(
                                user = selectedUser!!,
                                onBack = {
                                    selectedUser = null
                                },
                                onChatClick = {
                                    chatUser = selectedUser
                                }
                            )
                        }
                    }

                    FMateTab.Profile -> ProfileScreen(
                        displayName = displayName,
                        profile = profile,
                        bestScore = matches.maxOfOrNull(scoreMatch) ?: 0,
                        joinedCount = joinedMatchIds.size,
                        createdCount = matches.count { it.createdByUser },
                        bookmarkedCount = bookmarkedMatchIds.size,
                        onProfileChange = onProfileChange,
                        onResetDemo = onResetDemo,
                    )
                }
            }
        }
    }
}

@Composable
internal fun AppHeader(displayName: String, onProfileClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
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
internal fun InsightCard(text: String) {
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
internal fun FlowCard(onCreateClick: () -> Unit) {
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
internal fun EmptyCard(title: String, description: String) {
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
internal fun MetricCard(label: String, value: String, accent: Color, modifier: Modifier = Modifier.width(158.dp)) {
    Card(
        modifier = modifier,
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
internal fun SectionHeading(subtitle: String, title: String, caption: String, bright: Boolean = false) {
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
internal fun DateBadge(dateTime: LocalDateTime, compact: Boolean = false) {
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
internal fun TagRow(tags: List<String>, bright: Boolean = false) {
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
internal fun TagChip(label: String, bright: Boolean = false) {
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
internal fun <T> OptionSection(
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
internal fun PitchLines(alpha: Float, modifier: Modifier = Modifier.fillMaxSize()) {
    Canvas(modifier = modifier) {
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

internal fun formatMatchDateTime(dateTime: LocalDateTime): String = dateTime.format(dateTimeFormatter)

internal fun formatDateOnly(date: LocalDate): String = date.format(dateOnlyFormatter)

internal fun matchStatus(match: MatchCardData): MatchStatus {
    val remaining = match.capacity - match.joinedCount
    return when {
        remaining <= 0 -> MatchStatus("모집 마감", TeamBlue)
        remaining <= 2 -> MatchStatus("마감 임박", CitrusOrange)
        else -> MatchStatus("모집 중", FieldGreen)
    }
}

internal data class MatchStatus(
    val label: String,
    val color: Color,
)

internal enum class FMateTab(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
) {
    Matches("매치", Icons.Outlined.Explore, Icons.Filled.Explore),
    Schedule("일정", Icons.Outlined.CalendarMonth, Icons.Filled.CalendarMonth),
    Create("생성", Icons.Outlined.AddCircleOutline, Icons.Filled.AddCircle),
    Users("유저", Icons.Outlined.PersonOutline, Icons.Filled.Groups),
    Profile("프로필", Icons.Outlined.PersonOutline, Icons.Filled.Person),
}
