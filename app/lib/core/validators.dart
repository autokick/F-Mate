/// 입력값 검증. 서버(DB 제약)와 같은 규칙을 쓴다.
/// 앱 검증은 사용성을 위한 것이고, 최종 검증은 항상 서버가 한다.
class Validators {
  Validators._();

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// DB: user_profiles.nickname_format 과 동일
  static final RegExp _nickname = RegExp(r'^[A-Za-z0-9가-힣_.]{2,20}$');

  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '이메일을 입력해 주세요';
    if (v.length > 254 || !_email.hasMatch(v)) return '올바른 이메일 형식이 아니에요';
    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요';
    return null;
  }

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return '비밀번호를 입력해 주세요';
    if (v.length < 8 || v.length > 64) return '비밀번호는 8~64자로 입력해 주세요';
    if (!_hasLetter.hasMatch(v) || !_hasDigit.hasMatch(v)) {
      return '영문과 숫자를 모두 포함해 주세요';
    }
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return '비밀번호를 한 번 더 입력해 주세요';
      if (value != original()) return '비밀번호가 일치하지 않아요';
      return null;
    };
  }

  static String? nickname(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '닉네임을 입력해 주세요';
    if (v.length < 2 || v.length > 20) return '닉네임은 2~20자로 입력해 주세요';
    if (!_nickname.hasMatch(v)) return '한글, 영문, 숫자, _ . 만 사용할 수 있어요';
    return null;
  }
}
