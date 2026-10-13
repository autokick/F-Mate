// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/validators.dart';

void main() {
  group('이메일', () {
    test('올바른 형식 통과', () {
      expect(Validators.email('player@fmate.app'), isNull);
      expect(Validators.email('  player@fmate.app  '), isNull, reason: '앞뒤 공백은 무시');
    });
    test('잘못된 형식 거부', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('player'), isNotNull);
      expect(Validators.email('player@fmate'), isNotNull);
      expect(Validators.email('pla yer@fmate.app'), isNotNull);
    });
  });

  group('새 비밀번호', () {
    test('영문+숫자 8자 이상 통과', () {
      expect(Validators.newPassword('abc12345'), isNull);
    });
    test('규칙 위반 거부', () {
      expect(Validators.newPassword('abc1234'), isNotNull, reason: '7자');
      expect(Validators.newPassword('abcdefgh'), isNotNull, reason: '숫자 없음');
      expect(Validators.newPassword('12345678'), isNotNull, reason: '영문 없음');
      expect(Validators.newPassword('a1' * 33), isNotNull, reason: '66자');
    });
    test('비밀번호 확인 일치', () {
      final check = Validators.confirmPassword(() => 'abc12345');
      expect(check('abc12345'), isNull);
      expect(check('abc12346'), isNotNull);
    });
  });

  group('닉네임 (DB 제약 nickname_format 과 동일)', () {
    test('허용', () {
      for (final n in ['화성풋살왕', 'pivo_10', 'kim.j', 'ab']) {
        expect(Validators.nickname(n), isNull, reason: n);
      }
    });
    test('거부', () {
      for (final n in ['a', 'a b', '이모지⚽', 'x' * 21, 'hi!']) {
        expect(Validators.nickname(n), isNotNull, reason: n);
      }
    });
  });
}
