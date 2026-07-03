package com.yangpa.fmate.data

import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.yangpa.fmate.model.PlayerProfile

fun saveUserToFirebase(
    nickname: String,
    email: String,
    profile: PlayerProfile = PlayerProfile("윙어", "중급", "야간"),
    onSuccess: () -> Unit = {},
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()

    val user = hashMapOf(
        "nickname" to nickname,
        "email" to email,
        "position" to profile.position,
        "skill" to profile.skill,
        "timePreference" to profile.timePreference,
        "statusMessage" to profile.statusMessage,
        "profileImageUrl" to "",
        "level" to 1,
        "createdAt" to FieldValue.serverTimestamp(),
        "updatedAt" to FieldValue.serverTimestamp()
    )

    db.collection("users")
        .document(email)
        .set(user)
        .addOnSuccessListener {
            Log.d("FIREBASE", "사용자 저장 성공")
            onSuccess()
        }
        .addOnFailureListener { e ->
            Log.e("FIREBASE", "사용자 저장 실패", e)
            onFailure(e)
        }
}

fun updateUserProfileToFirebase(
    email: String,
    profile: PlayerProfile,
    onSuccess: () -> Unit = {},
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()

    db.collection("users")
        .document(email)
        .update(
            mapOf(
                "position" to profile.position,
                "skill" to profile.skill,
                "timePreference" to profile.timePreference,
                "statusMessage" to profile.statusMessage,
                "updatedAt" to FieldValue.serverTimestamp()
            )
        )
        .addOnSuccessListener { onSuccess() }
        .addOnFailureListener { e -> onFailure(e) }
}

data class UserProfile(
    val email: String = "",
    val nickname: String = "",
    val position: String = "",
    val skill: String = "",
    val timePreference: String = "",
    val statusMessage: String = ""
)

fun addFriendToFirebase(
    myEmail: String,
    friend: UserProfile,
    onSuccess: () -> Unit = {},
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()

    val friendData = hashMapOf(
        "email" to friend.email,
        "nickname" to friend.nickname,
        "position" to friend.position,
        "skill" to friend.skill,
        "timePreference" to friend.timePreference,
        "statusMessage" to friend.statusMessage,
        "addedAt" to FieldValue.serverTimestamp()
    )

    db.collection("users")
        .document(myEmail)
        .collection("friends")
        .document(friend.email)
        .set(friendData)
        .addOnSuccessListener { onSuccess() }
        .addOnFailureListener { e -> onFailure(e) }
}

fun loadFriendsFromFirebase(
    myEmail: String,
    onSuccess: (List<UserProfile>) -> Unit,
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()

    db.collection("users")
        .document(myEmail)
        .collection("friends")
        .get()
        .addOnSuccessListener { result ->
            val friends = result.documents.mapNotNull { doc ->
                doc.toObject(UserProfile::class.java)
            }
            onSuccess(friends)
        }
        .addOnFailureListener { e -> onFailure(e) }
}
data class ChatMessageData(
    val senderEmail: String = "",
    val text: String = "",
    val createdAtMillis: Long = 0L
)

fun makeChatRoomId(myEmail: String, friendEmail: String): String {
    return listOf(myEmail, friendEmail)
        .sorted()
        .joinToString("_")
        .replace(".", "_")
        .replace("@", "_")
}

fun sendMessageToFirebase(
    myEmail: String,
    friendEmail: String,
    text: String,
    onSuccess: () -> Unit = {},
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()
    val roomId = makeChatRoomId(myEmail, friendEmail)

    val message = hashMapOf(
        "senderEmail" to myEmail,
        "text" to text,
        "createdAtMillis" to System.currentTimeMillis()
    )

    db.collection("chatRooms")
        .document(roomId)
        .collection("messages")
        .add(message)
        .addOnSuccessListener { onSuccess() }
        .addOnFailureListener { e -> onFailure(e) }
}

fun loadMessagesFromFirebase(
    myEmail: String,
    friendEmail: String,
    onSuccess: (List<ChatMessageData>) -> Unit,
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()
    val roomId = makeChatRoomId(myEmail, friendEmail)

    db.collection("chatRooms")
        .document(roomId)
        .collection("messages")
        .orderBy("createdAtMillis")
        .get()
        .addOnSuccessListener { result ->
            val messages = result.documents.mapNotNull { doc ->
                doc.toObject(ChatMessageData::class.java)
            }
            onSuccess(messages)
        }
        .addOnFailureListener { e -> onFailure(e) }
}

fun listenMessagesFromFirebase(
    myEmail: String,
    friendEmail: String,
    onChange: (List<ChatMessageData>) -> Unit,
    onFailure: (Exception) -> Unit = {}
): ListenerRegistration {
    val db = FirebaseFirestore.getInstance()
    val roomId = makeChatRoomId(myEmail, friendEmail)

    return db.collection("chatRooms")
        .document(roomId)
        .collection("messages")
        .orderBy("createdAtMillis")
        .addSnapshotListener { snapshot, error ->
            if (error != null) {
                onFailure(error)
                return@addSnapshotListener
            }
            val messages = snapshot?.documents?.mapNotNull { doc ->
                doc.toObject(ChatMessageData::class.java)
            } ?: emptyList()
            onChange(messages)
        }
}

fun loadUsersFromFirebase(
    onSuccess: (List<UserProfile>) -> Unit,
    onFailure: (Exception) -> Unit = {}
) {
    val db = FirebaseFirestore.getInstance()

    db.collection("users")
        .get()
        .addOnSuccessListener { result ->
            val users = result.documents.mapNotNull { doc ->
                doc.toObject(UserProfile::class.java)
            }
            onSuccess(users)
        }
        .addOnFailureListener { e ->
            onFailure(e)
        }
}
