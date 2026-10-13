import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum PolicyKind { terms, privacy, location, community }

/// 약관·정책 전문. ⚠ 아래 문안은 법률 검토 전 초안이다. 출시 전 전문가 검토 후 교체해야 한다.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.kind});

  final PolicyKind kind;

  static String title(PolicyKind k) => switch (k) {
        PolicyKind.terms => '서비스 이용약관',
        PolicyKind.privacy => '개인정보 처리방침',
        PolicyKind.location => '위치기반서비스 이용약관',
        PolicyKind.community => '커뮤니티 운영정책',
      };

  static String body(PolicyKind k) => switch (k) {
        PolicyKind.terms => _terms,
        PolicyKind.privacy => _privacy,
        PolicyKind.location => _location,
        PolicyKind.community => _community,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title(kind))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FmSpace.l),
          children: [
            Container(
              padding: const EdgeInsets.all(FmSpace.m),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(FmRadius.control)),
              child: const Text('이 문서는 법률 검토 전 초안입니다. 정식 출시 전에 확정본으로 교체됩니다.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF92400E))),
            ),
            const SizedBox(height: FmSpace.l),
            SelectableText(body(kind), style: const TextStyle(fontSize: 14, height: 1.7, color: FmColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

const _terms = '''
제1조 (목적)
이 약관은 F-Mate(이하 "서비스")가 제공하는 풋살장 예약 중개, 커뮤니티, 채팅 등 서비스의 이용 조건과 절차, 회사와 회원의 권리·의무를 정합니다.

제2조 (회원가입)
1. 만 14세 이상인 사람은 이 약관과 개인정보 처리방침에 동의하고 가입할 수 있습니다.
2. 예약·게시물 작성 등 일부 기능은 이메일 인증을 마친 회원만 이용할 수 있습니다.

제3조 (예약과 결제)
1. 서비스는 회원과 구장 운영자 사이의 예약을 중개합니다. 구장 이용 계약의 당사자는 회원과 구장 운영자입니다.
2. 예약은 결제가 승인된 때 확정됩니다. 결제 대기 시간(10분) 안에 결제하지 않으면 예약은 자동으로 만료됩니다.
3. 결제는 전자결제대행사(토스페이먼츠)를 통해 처리되며, 서비스는 카드번호 등 결제수단 정보를 저장하지 않습니다.

제4조 (취소와 환불)
1. 회원은 이용 시작 전까지 예약을 취소할 수 있고, 환불 금액은 예약 당시 구장이 정한 취소 정책을 따릅니다.
2. 구장 사정으로 예약이 취소되면 결제 금액 전액을 환불합니다.
3. 환불은 결제 수단으로 처리되며 카드사 사정에 따라 반영까지 영업일 기준 수일이 걸릴 수 있습니다.

제5조 (회원의 의무)
회원은 타인의 정보 도용, 허위 예약, 욕설·혐오 표현, 음란물·불법 콘텐츠 게시, 저작권 침해 등 커뮤니티 운영정책에 어긋나는 행위를 해서는 안 됩니다.

제6조 (게시물)
1. 회원이 올린 게시물의 저작권은 회원에게 있습니다.
2. 서비스는 신고된 게시물이 운영정책에 어긋나는 경우 숨기거나 삭제할 수 있고, 위반 정도에 따라 이용을 제한할 수 있습니다.

제7조 (회원 탈퇴)
회원은 언제든 앱에서 탈퇴할 수 있습니다. 진행 중인 예약이나 환불이 있으면 처리 후 탈퇴할 수 있습니다.

제8조 (분쟁 해결)
서비스 이용과 관련한 분쟁은 관련 법령과 상관례에 따릅니다.
''';

const _privacy = '''
1. 수집하는 개인정보
 - 필수: 이메일, 비밀번호(암호화 저장), 닉네임
 - 선택: 프로필 사진, 소개, 활동 지역, 선호 포지션
 - 예약·결제 시: 예약 내역, 결제 승인 정보(결제키, 금액, 결제수단 종류). 카드번호는 수집하지 않습니다.
 - 위치기반 기능 사용 시: 현재 위치(저장하지 않고 주변 구장 검색에만 사용)
 - 자동 수집: 기기 푸시 토큰, 접속 기록(보안 목적)

2. 이용 목적
회원 관리, 예약·결제·환불 처리, 커뮤니티 기능 제공, 부정 이용 방지, 고객 문의 대응

3. 보관 기간
 - 회원 탈퇴 시 프로필·게시물·댓글·팔로우·푸시 토큰을 즉시 삭제합니다.
 - 단, 관련 법령에 따라 결제·계약 기록은 식별 정보를 제거한 상태로 법정 기간 동안 보관합니다.

4. 제3자 제공 및 처리 위탁
 - 결제 처리: 토스페이먼츠
 - 사진·영상 저장: 클라우드 스토리지 사업자
 - 푸시 알림 전송: Google Firebase Cloud Messaging
 - 예약 확정 시 해당 구장 운영자에게 예약자 닉네임과 예약 시간이 제공됩니다.

5. 이용자의 권리
회원은 언제든 앱에서 자신의 정보를 조회·수정하고 탈퇴할 수 있습니다.

6. 개인정보 보호책임자
(출시 전 기재)
''';

const _location = '''
제1조 (목적)
이 약관은 F-Mate가 제공하는 "내 주변 구장 찾기" 기능의 위치정보 이용에 관한 사항을 정합니다.

제2조 (이용하는 위치정보와 목적)
회원 기기의 현재 위치(위도·경도)를 주변 구장 검색에만 이용합니다.

제3조 (보관)
위치정보는 검색 요청에만 쓰고 서버에 저장하지 않습니다.

제4조 (동의 철회)
회원은 언제든 기기 설정에서 위치 권한을 끄거나 앱 설정에서 동의를 철회할 수 있습니다. 철회해도 지역 선택 검색은 이용할 수 있습니다.
''';

const _community = '''
F-Mate 는 모두가 즐겁게 공을 차는 커뮤니티를 지향합니다.

금지되는 행위
 - 욕설, 비하, 혐오 표현, 특정인 저격·괴롭힘
 - 음란물, 폭력적·불법적인 콘텐츠
 - 광고·도배·스팸
 - 타인 사칭, 허위 구장 정보
 - 타인의 영상·음악 등 저작물 무단 사용

신고와 조치
 - 게시물·댓글·메시지·사용자를 신고할 수 있습니다.
 - 서로 다른 5명 이상이 신고한 게시물은 운영자 검토 전까지 자동으로 숨겨집니다.
 - 운영자는 위반 정도에 따라 콘텐츠 숨김·삭제, 경고, 기간 정지, 영구 정지 조치를 합니다.
 - 저작권 침해 신고는 권리자 확인 후 해당 콘텐츠를 삭제합니다.

차단
차단한 사용자와는 서로의 게시물·프로필을 볼 수 없고, 팔로우·채팅이 불가능합니다.
''';
