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
internal fun ProfileScreen(

    displayName: String,
    profile: PlayerProfile,
    bestScore: Int,
    joinedCount: Int,
    createdCount: Int,
    bookmarkedCount: Int,
    onProfileChange: (PlayerProfile) -> Unit,
    onResetDemo: () -> Unit,
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

                            Text(
                                text = profile.statusMessage,
                                color = MutedInk,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }

                    TagRow(
                        tags = listOf(profile.position, profile.skill, profile.timePreference, "추천 ${bestScore}점"),
                    )

                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        MetricCard("참가 일정", joinedCount.toString(), FieldGreen)
                        MetricCard("개설 매치", createdCount.toString(), CitrusOrange)
                        MetricCard("관심 매치", bookmarkedCount.toString(), TeamBlue)
                    }

                    OptionSection("포지션", positions, profile.position, onSelect = {
                        onProfileChange(profile.copy(position = it))
                    })
                    OptionSection("실력", levels, profile.skill, onSelect = {
                        onProfileChange(profile.copy(skill = it))
                    })
                    OptionSection("선호 시간", timePreferences, profile.timePreference, onSelect = {
                        onProfileChange(profile.copy(timePreference = it))
                    })
                    OutlinedTextField(
                        value = profile.statusMessage,
                        onValueChange = {
                            onProfileChange(profile.copy(statusMessage = it))
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("상태 메시지") },
                        placeholder = { Text("예: 풋살 같이 할 친구 구해요!") },
                        minLines = 2
                    )

                    OutlinedButton(
                        onClick = onResetDemo,
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(vertical = 14.dp),
                    ) {
                        Icon(Icons.Filled.RestartAlt, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("시연 데이터 초기화")
                    }
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
