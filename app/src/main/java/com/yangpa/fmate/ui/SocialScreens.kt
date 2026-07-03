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
internal fun FriendsScreen(
    myEmail: String,
    users: List<UserProfile>,
    friends: List<UserProfile>,
    usersLoading: Boolean,
    friendsLoading: Boolean,
    onRefreshUsers: () -> Unit,
    onRefreshFriends: () -> Unit,
    onAddFriend: (UserProfile) -> Unit,
    onUserClick: (UserProfile) -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }

    val filteredUsers = users.filter { user ->
        user.email != myEmail &&
            (searchQuery.isBlank() ||
                user.nickname.contains(searchQuery, ignoreCase = true) ||
                user.email.contains(searchQuery, ignoreCase = true))
    }

    val friendEmails = friends.map { it.email }.toSet()

    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            SectionHeading(
                subtitle = "Friends",
                title = "친구",
                caption = "유저를 검색해 친구로 추가하고, 친구 정보를 확인합니다.",
            )
        }

        item {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("닉네임 또는 이메일 검색") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
            )
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = onRefreshUsers,
                    enabled = !usersLoading,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 14.dp),
                ) {
                    Text(if (usersLoading) "불러오는 중..." else "유저 검색")
                }

                OutlinedButton(
                    onClick = onRefreshFriends,
                    enabled = !friendsLoading,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 14.dp),
                ) {
                    Text(if (friendsLoading) "불러오는 중..." else "내 친구")
                }
            }
        }

        item {
            SectionHeading(
                subtitle = "My Friends",
                title = "내 친구 목록",
                caption = "친구로 추가한 유저입니다.",
            )
        }

        if (friends.isEmpty()) {
            item {
                EmptyCard(
                    title = "아직 추가한 친구가 없습니다.",
                    description = "유저를 검색한 뒤 친구 추가를 눌러보세요.",
                )
            }
        } else {
            items(friends) { friend ->
                ElevatedCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onUserClick(friend) },
                    colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
                    shape = RoundedCornerShape(24.dp),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(friend.nickname.ifBlank { "이름 없음" }, style = MaterialTheme.typography.titleLarge)
                        Text(friend.email, color = MutedInk)
                        Text(
                            "${friend.position} | ${friend.skill} | ${friend.timePreference} 선호",
                            color = MutedInk,
                        )
                        Text(
                            friend.statusMessage.ifBlank { "상태 메시지가 없습니다." },
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }

        item {
            SectionHeading(
                subtitle = "Search Result",
                title = "검색 결과",
                caption = "친구로 추가할 유저를 선택하세요.",
            )
        }

        if (filteredUsers.isEmpty()) {
            item {
                EmptyCard(
                    title = "검색 결과가 없습니다.",
                    description = "유저 검색 버튼을 누르거나 검색어를 다시 입력해보세요.",
                )
            }
        } else {
            items(filteredUsers) { user ->
                val alreadyFriend = friendEmails.contains(user.email)

                ElevatedCard(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.elevatedCardColors(containerColor = Color.White),
                    shape = RoundedCornerShape(24.dp),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(user.nickname.ifBlank { "이름 없음" }, style = MaterialTheme.typography.titleLarge)
                        Text(user.email, color = MutedInk)

                        Text(
                            "${user.position} | ${user.skill} | ${user.timePreference} 선호",
                            color = MutedInk,
                        )

                        Text(
                            user.statusMessage.ifBlank { "상태 메시지가 없습니다." },
                            style = MaterialTheme.typography.bodyMedium,
                        )

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilledTonalButton(
                                onClick = { onUserClick(user) },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("정보 확인")
                            }

                            Button(
                                onClick = { onAddFriend(user) },
                                enabled = !alreadyFriend,
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(if (alreadyFriend) "친구 추가됨" else "친구 추가")
                            }
                        }
                    }
                }
            }
        }
    }
}
@Composable
internal fun UserDetailScreen(
    user: UserProfile,
    onBack: () -> Unit,
    onChatClick: () -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(start = 20.dp, top = 12.dp, end = 20.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = onBack,
                    colors = IconButtonDefaults.filledTonalIconButtonColors()
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "뒤로")
                }

                Spacer(modifier = Modifier.width(8.dp))

                Text(
                    text = "프로필 상세",
                    style = MaterialTheme.typography.headlineMedium,
                    color = Ink
                )
            }
        }

        item {
            ElevatedCard(
                colors = CardDefaults.elevatedCardColors(containerColor = Color(0xFFFFF9ED)),
                shape = RoundedCornerShape(28.dp),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(22.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(82.dp)
                            .clip(RoundedCornerShape(26.dp))
                            .background(Color(0x140F8F43)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Filled.Person,
                            contentDescription = null,
                            tint = FieldGreen,
                            modifier = Modifier.size(44.dp)
                        )
                    }

                    Text(
                        text = user.nickname.ifBlank { "이름 없음" },
                        style = MaterialTheme.typography.headlineMedium,
                        color = Ink
                    )

                    Text(
                        text = user.email,
                        color = MutedInk
                    )

                    TagRow(
                        tags = listOf(
                            user.position.ifBlank { "포지션 미입력" },
                            user.skill.ifBlank { "실력 미입력" },
                            user.timePreference.ifBlank { "시간 미입력" }
                        )
                    )

                    Text(
                        text = user.statusMessage.ifBlank { "상태 메시지가 없습니다." },
                        style = MaterialTheme.typography.bodyLarge,
                        color = Ink
                    )

                    Button(
                        onClick = onChatClick,
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        Text("채팅하기")
                    }
                }
            }
        }
    }
}
data class ChatMessage(
    val text: String,
    val isMine: Boolean
)

@Composable
internal fun ChatScreen(
    myEmail: String,
    user: UserProfile,
    showMessage: (String) -> Unit,
    onBack: () -> Unit
) {
    var message by remember { mutableStateOf("") }
    var messages by remember { mutableStateOf<List<ChatMessageData>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val listState = rememberLazyListState()

    DisposableEffect(myEmail, user.email) {
        loading = true
        val registration = listenMessagesFromFirebase(
            myEmail = myEmail,
            friendEmail = user.email,
            onChange = { loadedMessages ->
                messages = loadedMessages
                loading = false
            },
            onFailure = {
                loading = false
                showMessage("메시지를 불러오지 못했습니다.")
            },
        )
        onDispose { registration.remove() }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = null
                )
            }

            Text(
                text = user.nickname.ifBlank { "채팅" },
                style = MaterialTheme.typography.titleLarge
            )
        }

        Box(modifier = Modifier.weight(1f)) {
            when {
                loading -> CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center)
                )

                messages.isEmpty() -> Text(
                    text = "아직 대화가 없습니다. 첫 메시지를 보내보세요.",
                    color = MutedInk,
                    modifier = Modifier.align(Alignment.Center)
                )

                else -> LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(messages) { msg ->
                        val isMine = msg.senderEmail == myEmail

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = if (isMine) Arrangement.End else Arrangement.Start
                        ) {
                            Card(
                                colors = CardDefaults.cardColors(
                                    containerColor = if (isMine) Color(0xFFD7F2DD) else Color.White
                                )
                            ) {
                                Text(
                                    text = msg.text,
                                    modifier = Modifier.padding(12.dp),
                                    color = Ink
                                )
                            }
                        }
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            OutlinedTextField(
                value = message,
                onValueChange = { message = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("메시지 입력") }
            )

            Spacer(modifier = Modifier.width(8.dp))

            Button(
                onClick = {
                    val text = message.trim()
                    if (text.isNotBlank()) {
                        sendMessageToFirebase(
                            myEmail = myEmail,
                            friendEmail = user.email,
                            text = text,
                            onSuccess = {
                                message = ""
                            },
                            onFailure = {
                                showMessage("메시지 전송에 실패했습니다.")
                            }
                        )
                    }
                }
            ) {
                Text("전송")
            }
        }
    }
}
