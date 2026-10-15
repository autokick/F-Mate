import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';
import '../features/auth/verify_email_screen.dart';
import 'payment/toss_test_checkout.dart';

/// First implementation stage for the zero-VPS Spark build. This is intentionally
/// isolated from the Spring-based 38-screen app until each repository is ported.
/// All venues and amounts below are explicitly fictional exhibition examples.
class FirebaseExhibitionHome extends StatefulWidget {
  const FirebaseExhibitionHome({super.key});

  @override
  State<FirebaseExhibitionHome> createState() => _FirebaseExhibitionHomeState();
}

class _FirebaseExhibitionHomeState extends State<FirebaseExhibitionHome> {
  int _tab = 0;
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services != _services) {
      _services?.goHome.removeListener(_resetTab);
      _services = services;
      services.goHome.addListener(_resetTab);
    }
  }

  void _resetTab() {
    if (mounted) setState(() => _tab = 0);
  }

  @override
  void dispose() {
    _services?.goHome.removeListener(_resetTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    const pages = [
      _DemoVenueList(),
      _DemoPosts(),
      _DemoChats(),
      _DemoAccount(),
    ];
    const labels = ['풋살장', '커뮤니티', '채팅', '내 정보'];
    return Scaffold(
      appBar: AppBar(
        title: Text('F-Mate · ${labels[_tab]}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '무료 전시 모드',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: FmColors.brand.withValues(alpha: .09),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Text(
              session.guest
                  ? '게스트 열람 · 쓰기는 실제 계정 로그인 후 가능'
                  : 'Firebase Auth + Firestore 실제 연결 · 예약·시설은 전시용 데이터',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: IndexedStack(index: _tab, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            label: '풋살장',
          ),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'SNS'),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: '채팅',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '마이'),
        ],
      ),
    );
  }
}

Future<bool> _requireVerified(BuildContext context) async {
  final session = AppScope.read(context).session;
  if (!session.isLoggedIn) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인한 계정만 사용할 수 있어요. 마이 탭에서 로그인해 주세요.')),
    );
    return false;
  }
  if (session.me?.emailVerified == true) return true;
  final result = await Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => const VerifyEmailScreen()));
  return result == true;
}

void _notify(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _dateKey(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

class _DemoVenue {
  const _DemoVenue(this.id, this.name, this.area, this.size, this.price);
  final String id;
  final String name;
  final String area;
  final String size;
  final int price;
}

const _demoVenues = <_DemoVenue>[
  _DemoVenue('demo-01', '시연용 풋살장 A', '서울 · 가상 시설', '5:5', 45000),
  _DemoVenue('demo-02', '시연용 풋살장 B', '경기 · 가상 시설', '6:6', 55000),
  _DemoVenue('demo-03', '시연용 풋살장 C', '서울 · 가상 시설', '5:5', 40000),
  _DemoVenue('demo-04', '시연용 풋살장 D', '경기 · 가상 시설', '6:6', 60000),
];

class _DemoVenueList extends StatelessWidget {
  const _DemoVenueList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('아래 구장 이름·요금은 모두 예시입니다'),
          subtitle: Text('공공데이터 구장 수백 개의 이관은 후속 단계입니다. 실제 예약·결제가 아닙니다.'),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.account_balance_wallet_outlined),
            ),
            title: const Text('토스페이먼츠 실제 TEST 결제창'),
            subtitle: const Text('토스 공식 SDK 호출 · 실제 청구 없음 · 게스트도 체험 가능'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TossTestCheckout(
                  venueName: '시연용 풋살장 A',
                  amount: 45000,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final venue in _demoVenues)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: const CircleAvatar(child: Icon(Icons.sports_soccer)),
              title: Text(venue.name),
              subtitle: Text(
                '${venue.area} · ${venue.size} · 예시 요금 ${venue.price}원',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DemoVenueBooking(venue: venue),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DemoVenueBooking extends StatefulWidget {
  const _DemoVenueBooking({required this.venue});
  final _DemoVenue venue;

  @override
  State<_DemoVenueBooking> createState() => _DemoVenueBookingState();
}

class _DemoVenueBookingState extends State<_DemoVenueBooking> {
  bool _busy = false;

  Future<void> _book(
    DocumentReference<Map<String, dynamic>> ref,
    String dateKey,
    int hour,
  ) async {
    if (!await _requireVerified(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) throw StateError('이미 선점된 시연 시간입니다');
        tx.set(ref, {
          'ownerUid': uid,
          'venueId': widget.venue.id,
          'dateKey': dateKey,
          'hour': hour,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      if (mounted) {
        _notify(context, '전시 예약이 저장됐어요. 아래에서 토스 TEST 결제도 체험할 수 있어요.');
      }
    } catch (e) {
      if (mounted) _notify(context, '예약 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(DocumentReference<Map<String, dynamic>> ref) async {
    setState(() => _busy = true);
    try {
      await ref.delete();
      if (mounted) _notify(context, '전시 예약을 취소했어요');
    } catch (e) {
      if (mounted) _notify(context, '취소 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextDay = DateTime.now().add(const Duration(days: 1));
    final day = _dateKey(nextDay);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: Text(widget.venue.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('시연용 예약'),
            subtitle: Text('가상 시설이며 실제 구장 예약이나 결제가 발생하지 않습니다. 인터넷 연결이 필요합니다.'),
          ),
          Text(
            '예약일: ${nextDay.year}.${nextDay.month}.${nextDay.day}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final hour in [18, 19, 20])
            Builder(
              builder: (context) {
                final ref = FirebaseFirestore.instance
                    .collection('demo_slots')
                    .doc(
                      '${widget.venue.id}_${day}_${hour.toString().padLeft(2, '0')}',
                    );
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: ref.snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    final booked = snapshot.data?.exists == true;
                    final mine =
                        booked && data?['ownerUid'] == uid && uid != null;
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text('$hour:00 ~ ${hour + 1}:00'),
                            subtitle: Text(
                              snapshot.hasError
                                  ? 'DB 연결 또는 보안 규칙을 확인하세요'
                                  : booked
                                  ? (mine ? '내 전시 예약' : '다른 체험자가 선점함')
                                  : '시연 예약 가능',
                            ),
                            trailing: TextButton(
                              onPressed:
                                  _busy ||
                                      snapshot.hasError ||
                                      !snapshot.hasData ||
                                      (booked && !mine)
                                  ? null
                                  : () => mine
                                        ? _cancel(ref)
                                        : _book(ref, day, hour),
                              child: Text(
                                mine
                                    ? '취소'
                                    : booked
                                    ? '예약됨'
                                    : '예약',
                              ),
                            ),
                          ),
                          if (mine)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 6,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.payment, size: 17),
                                  label: const Text('토스 TEST 결제 체험'),
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => TossTestCheckout(
                                              venueName: widget.venue.name,
                                              amount: widget.venue.price,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DemoPosts extends StatefulWidget {
  const _DemoPosts();

  @override
  State<_DemoPosts> createState() => _DemoPostsState();
}

class _DemoPostsState extends State<_DemoPosts> {
  bool _posting = false;

  Future<void> _compose() async {
    if (!await _requireVerified(context)) return;
    if (!mounted) return;
    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전시용 게시글 작성'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          maxLength: 400,
          decoration: const InputDecoration(
            hintText: '공개 시연 게시물입니다. 개인정보를 입력하지 마세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('게시'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (body == null || body.isEmpty || !mounted) return;
    setState(() => _posting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('demo_posts').add({
        'authorUid': uid,
        'authorName': AppScope.read(context).session.me?.nickname ?? '체험 회원',
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _notify(context, '글이 Firestore에 저장됐어요');
    } catch (e) {
      if (mounted) _notify(context, '글 저장 실패: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      children: [
        ListTile(
          title: const Text('실시간 공개 게시판'),
          subtitle: const Text('Firestore 저장·동기화 · 영상/댓글은 다음 개발 단계'),
          trailing: FilledButton.icon(
            onPressed: _posting ? null : _compose,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('글쓰기'),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('demo_posts')
                .orderBy('createdAt', descending: true)
                .limit(25)
                .snapshots(includeMetadataChanges: true),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('게시물을 불러올 수 없어요. Firestore 보안 규칙과 연결을 확인하세요.'),
                );
              }
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final posts = snapshot.data!.docs;
              if (posts.isEmpty)
                return const Center(
                  child: Text('아직 게시물이 없어요. 첫 시연 글을 작성해 보세요.'),
                );
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: posts.length,
                itemBuilder: (ctx, i) {
                  final post = posts[i];
                  final data = post.data();
                  final owner = data['authorUid'] == uid && uid != null;
                  final time = data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp)
                            .toDate()
                            .toLocal()
                            .toString()
                            .substring(0, 16)
                      : '동기화 중';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 16,
                                child: Icon(Icons.person_outline, size: 17),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${data['authorName'] ?? '체험 회원'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      time,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (owner)
                                IconButton(
                                  tooltip: '내 글 삭제',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    try {
                                      await post.reference.delete();
                                    } catch (e) {
                                      if (context.mounted)
                                        _notify(context, '삭제 실패: $e');
                                    }
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('${data['body'] ?? ''}'),
                          if (post.metadata.hasPendingWrites)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                '기기에서 서버 동기화 대기 중',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DemoChats extends StatelessWidget {
  const _DemoChats();

  Future<void> _openChat(
    BuildContext context,
    String otherUid,
    String otherName,
  ) async {
    if (!await _requireVerified(context)) return;
    if (!context.mounted) return;
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final members = [currentUid, otherUid]..sort();
    final chatId = members.join('_');
    final room = FirebaseFirestore.instance
        .collection('demo_chats')
        .doc(chatId);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snapshot = await tx.get(room);
        if (!snapshot.exists) {
          tx.set(room, {
            'members': members,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _RealChatScreen(room: room, otherName: otherName),
        ),
      );
    } catch (e) {
      if (context.mounted) _notify(context, '채팅방 생성 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('전시 안내 자동응답'),
            subtitle: const Text('기기 안에서만 작동하는 규칙형 자동응답 · 실제 상대방 아님'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const _LocalBotScreen())),
          ),
        ),
        const SizedBox(height: 12),
        const ListTile(
          title: Text('실제 실시간 1:1 채팅'),
          subtitle: Text(
            '두 개의 이메일 인증된 Firebase 계정으로 로그인해 메시지를 주고받을 수 있어요. 한 기기에서도 계정을 바꿔 확인할 수 있습니다.',
          ),
        ),
        if (uid == null)
          const ListTile(title: Text('채팅을 이용하려면 로그인해 주세요'))
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('profiles')
                .limit(40)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const ListTile(
                  title: Text('프로필 검색 실패 · Firestore 규칙을 확인하세요'),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final others = snapshot.data!.docs
                  .where((d) => d.id != uid)
                  .toList();
              if (others.isEmpty)
                return const ListTile(
                  title: Text('다른 시연 계정이 아직 없어요'),
                  subtitle: Text(
                    '이메일이 다른 계정을 하나 더 만들고 인증하면 실제 채팅을 테스트할 수 있어요.',
                  ),
                );
              return Column(
                children: [
                  for (final p in others)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text('${p.data()['nickname'] ?? '체험 회원'}'),
                        subtitle: const Text('실제 Firestore 채팅방 열기'),
                        trailing: const Icon(Icons.chat_outlined),
                        onTap: () => _openChat(
                          context,
                          p.id,
                          '${p.data()['nickname'] ?? '체험 회원'}',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _RealChatScreen extends StatefulWidget {
  const _RealChatScreen({required this.room, required this.otherName});
  final DocumentReference<Map<String, dynamic>> room;
  final String otherName;

  @override
  State<_RealChatScreen> createState() => _RealChatScreenState();
}

class _RealChatScreenState extends State<_RealChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || body.length > 500 || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.room.collection('messages').add({
        'authorUid': FirebaseAuth.instance.currentUser!.uid,
        'text': body,
        'sentAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _input.clear();
    } catch (e) {
      if (mounted) _notify(context, '메시지 전송 실패: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherName)),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              '실제 Firebase 1:1 채팅 · 상대 계정이 접속하면 실시간으로 보입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.room
                  .collection('messages')
                  .orderBy('sentAt', descending: true)
                  .limit(60)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(child: Text('채팅 수신 실패 · 규칙을 확인하세요'));
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final mine = m.data()['authorUid'] == uid;
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(11),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .78,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? FmColors.brand.withValues(alpha: .16)
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${m.data()['text'] ?? ''}'),
                            if (m.metadata.hasPendingWrites)
                              const Text(
                                '동기화 대기',
                                style: TextStyle(fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 500,
                      maxLines: 2,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: '메시지 입력',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: '전송',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotMessage {
  const _BotMessage(this.text, this.mine);
  final String text;
  final bool mine;
}

class _LocalBotScreen extends StatefulWidget {
  const _LocalBotScreen();

  @override
  State<_LocalBotScreen> createState() => _LocalBotScreenState();
}

class _LocalBotScreenState extends State<_LocalBotScreen> {
  final _input = TextEditingController();
  final _messages = <_BotMessage>[
    const _BotMessage(
      '안녕하세요! 저는 오프라인 시연용 규칙형 자동응답입니다. 시간·준비물·예약 중 하나를 물어보세요.',
      false,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    String reply;
    if (q.contains('시간') || q.contains('언제')) {
      reply = '시연 화면의 예시 경기 시간은 내일 오후 6시부터입니다. 실제 경기는 아닙니다.';
    } else if (q.contains('준비물') || q.contains('신발')) {
      reply = '풋살화와 운동복을 준비하면 좋습니다. 구장별 이용 규정을 확인하세요.';
    } else if (q.contains('예약') || q.contains('결제')) {
      reply = '풋살장 탭에서 시연 예약을 체험할 수 있어요. 실제 요금은 청구되지 않습니다.';
    } else {
      reply = '무슨 뜻인지 이해하지 못했어요. 시간·준비물·예약에 대해 질문해 주세요.';
    }
    setState(() => _messages.add(_BotMessage(q, true)));
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _messages.add(_BotMessage(reply, false)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('오프라인 자동응답 데모')),
      body: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('자동응답 시뮬레이션'),
            subtitle: Text('AI가 아니며 실제 회원 채팅이 아닙니다. 답변은 서버에 저장되지 않습니다.'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final m in _messages)
                  Align(
                    alignment: m.mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(m.text),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(hintText: '질문을 입력하세요'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoAccount extends StatelessWidget {
  const _DemoAccount();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final me = services.session.me;
    if (me == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.account_circle_outlined, size: 72),
          const SizedBox(height: 18),
          const Text('게스트 체험 중', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text(
            '글쓰기·시연 예약·실시간 채팅은 가입 후 이메일 인증이 필요합니다.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: services.session.stopBrowsing,
            child: const Text('로그인 / 회원가입 화면으로'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: Icon(Icons.account_circle_outlined, size: 72)),
        const SizedBox(height: 16),
        Text(
          me.nickname,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(me.email ?? '', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ListTile(
          leading: Icon(
            me.emailVerified
                ? Icons.verified
                : Icons.mark_email_unread_outlined,
          ),
          title: Text(me.emailVerified ? '이메일 인증 완료' : '이메일 인증 필요'),
          subtitle: const Text('이메일의 인증 링크를 눌러야 글 작성과 시연 예약이 가능합니다.'),
          trailing: me.emailVerified ? null : const Icon(Icons.chevron_right),
          onTap: me.emailVerified
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
                ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('전시용 Firebase 계정'),
          subtitle: Text(
            '이 버전에서 작성한 SNS·예약·채팅은 Firebase에 실제 저장됩니다. '
            '로그아웃해도 서버에 작성 기록은 남습니다. 자동 삭제/초기화는 아직 구현되지 않았습니다.',
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          onPressed: () async {
            try {
              await services.logout();
            } catch (e) {
              if (context.mounted) _notify(context, '로그아웃 실패: $e');
            }
          },
          label: const Text('로그아웃하고 다음 관람객 맞이하기'),
        ),
      ],
    );
  }
}
