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
internal fun EntryFlow(onComplete: (String, String) -> Unit) {
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
    var nickname by remember { mutableStateOf("홍길동") }
    var email by remember { mutableStateOf("20220000@seoil.ac.kr") }

    if (showLogin) {
        LoginScreen(
            nickname = nickname,
            email = email,
            onNicknameChange = { nickname = it },
            onEmailChange = { email = it },
            onBack = { showLogin = false },
            onEnter = {
                onComplete(nickname.trim(), email.trim())
            },
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
internal fun OnboardingVisual(slide: OnboardingSlide, modifier: Modifier = Modifier) {
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
internal fun LoginScreen(
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

internal data class OnboardingSlide(
    val title: String,
    val body: String,
    val icon: ImageVector,
    val accent: Color,
)
