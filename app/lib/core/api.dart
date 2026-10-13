import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'format.dart';

/// 서버 오류. code 는 서버 오류 코드표(docs/02-api-spec.md)와 같다.
class ApiError implements Exception {
  ApiError(this.code, this.message, {this.status, this.fieldErrors = const {}});

  final String code;
  final String message;
  final int? status;
  final Map<String, String> fieldErrors;

  bool get isNetwork => code == 'NETWORK';
  bool get isUnauthenticated => status == 401;
  bool get isNotConfigured => code.endsWith('_NOT_CONFIGURED');

  @override
  String toString() => message;

  static ApiError from(Object e) {
    if (e is ApiError) return e;
    if (e is DioException) {
      final res = e.response;
      if (res == null) {
        return ApiError('NETWORK', '서버에 연결할 수 없어요. 네트워크 상태를 확인해 주세요.');
      }
      final data = res.data;
      if (data is Map) {
        final fields = <String, String>{};
        final fe = data['fieldErrors'];
        if (fe is Map) {
          fe.forEach((k, v) => fields['$k'] = '$v');
        }
        return ApiError(asStr(data['code'], 'INTERNAL'), asStr(data['title'], '오류가 발생했어요'),
            status: res.statusCode, fieldErrors: fields);
      }
      return ApiError('INTERNAL', '오류가 발생했어요 (${res.statusCode})', status: res.statusCode);
    }
    return ApiError('INTERNAL', '알 수 없는 오류가 발생했어요');
  }
}

/// 토큰 보안 저장 (테스트에서는 persistent: false 로 메모리에만 둔다)
class TokenStore {
  TokenStore({this.persistent = true});

  final bool persistent;
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _accessKey = 'fmate.access';
  static const _refreshKey = 'fmate.refresh';

  String? access;
  String? refresh;

  Future<void> load() async {
    if (!persistent) return;
    try {
      access = await _storage.read(key: _accessKey);
      refresh = await _storage.read(key: _refreshKey);
    } catch (_) {
      // 기기 키 저장소 오류: 저장된 로그인 정보를 버리고 다시 로그인하게 한다
      access = null;
      refresh = null;
    }
  }

  Future<void> save(String accessToken, String refreshToken) async {
    access = accessToken;
    refresh = refreshToken;
    if (!persistent) return;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
    access = null;
    refresh = null;
    if (!persistent) return;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// REST 클라이언트.
///  - 모든 요청에 액세스 토큰 첨부
///  - 401 이면 리프레시 토큰으로 한 번만 갱신 후 재시도 (동시에 여러 요청이 401 이어도 갱신은 1회)
///  - 갱신 실패 시 onSessionExpired 호출 (로그아웃 처리)
class ApiClient {
  ApiClient(this.tokens, {HttpClientAdapter? adapter})
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Dio _dio;
  final TokenStore tokens;
  Future<bool>? _refreshing;
  void Function()? onSessionExpired;

  /// presigned URL 업로드 전용 (인증 헤더·기본 주소 없음)
  final Dio uploader = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(minutes: 30),
    receiveTimeout: const Duration(minutes: 2),
  ));

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, String? idempotencyKey}) =>
      _send('POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Object? body}) => _send('DELETE', path, body: body);

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? query, Object? body, String? idempotencyKey, bool retried = false}) async {
    try {
      final headers = <String, dynamic>{};
      if (tokens.access != null) headers['Authorization'] = 'Bearer ${tokens.access}';
      if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
      final res = await _dio.request<dynamic>(path,
          data: body,
          queryParameters: query == null ? null : _clean(query),
          options: Options(method: method, headers: headers));
      return res.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final isAuthCall = path.startsWith('/api/v1/auth/login') ||
          path.startsWith('/api/v1/auth/refresh') ||
          path.startsWith('/api/v1/auth/signup');
      if (status == 401 && !retried && !isAuthCall && tokens.refresh != null) {
        final ok = await _refreshOnce();
        if (ok) {
          return _send(method, path, query: query, body: body, idempotencyKey: idempotencyKey, retried: true);
        }
        onSessionExpired?.call();
      }
      throw ApiError.from(e);
    }
  }

  Future<bool> _refreshOnce() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final f = _doRefresh();
    _refreshing = f;
    f.whenComplete(() => _refreshing = null);
    return f;
  }

  Future<bool> _doRefresh() async {
    final refresh = tokens.refresh;
    if (refresh == null) return false;
    try {
      final res = await _dio.post<dynamic>('/api/v1/auth/refresh', data: {'refreshToken': refresh});
      final data = asMap(res.data);
      await tokens.save(asStr(data['accessToken']), asStr(data['refreshToken']));
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    }
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> q) {
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  /// presigned URL 로 파일 PUT (진행률 콜백)
  Future<void> uploadToUrl(String url, Stream<List<int>> data, int length, Map<String, String> headers,
      {void Function(int sent, int total)? onProgress, CancelToken? cancelToken}) async {
    try {
      await uploader.put<dynamic>(url,
          data: data,
          options: Options(headers: {...headers, Headers.contentLengthHeader: length}),
          onSendProgress: onProgress,
          cancelToken: cancelToken);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw ApiError('CANCELED', '업로드를 취소했어요');
      throw ApiError('UPLOAD_FAILED', '파일 업로드에 실패했어요. 네트워크를 확인하고 다시 시도해 주세요.');
    }
  }
}
