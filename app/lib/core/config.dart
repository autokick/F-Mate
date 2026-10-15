/// 빌드 시 주입하는 설정값 (--dart-define).
///
/// 실행 예 (에뮬레이터 + PC 의 로컬 서버):
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
/// 실제 기기에서 PC 서버를 쓸 때는 PC 의 내부 IP (예: http://192.168.0.10:8080)
///
/// 비밀 키(시크릿)는 절대 앱에 넣지 않는다. 공개돼도 되는 값만 둔다.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// AndroidManifest 에 Google Maps API 키를 넣은 뒤에만 true 로 빌드한다.
  /// (키 없이 지도 위젯을 띄우면 앱이 종료되므로 기본 false)
  static const bool mapsEnabled = bool.fromEnvironment('MAPS_ENABLED');

  /// google-services.json 을 넣은 뒤에만 true. 아니면 푸시 초기화를 건너뛴다.
  static const bool pushEnabled = bool.fromEnvironment('PUSH_ENABLED');

  static const String appVersion = '1.0.0';

  /// 오른쪽 위 '초기화면' 버튼 (전시용, 기본 켜짐). 끄려면 --dart-define=HOME_BUTTON=false
  static const bool homeButton = bool.fromEnvironment('HOME_BUTTON', defaultValue: true);

  /// 위치를 모를 때 거리 계산 기준점 (기본: 서울 중랑구청). 에뮬레이터는 위치가 미국으로 잡혀 있어서
  /// 내 위치를 쓰지 않을 때는 이 지점에서 가까운 순으로 보여준다.
  static const String defaultAreaName = String.fromEnvironment('DEFAULT_AREA', defaultValue: '중랑구');
  static final double defaultLat = double.tryParse(const String.fromEnvironment('DEFAULT_LAT')) ?? 37.6066;
  static final double defaultLng = double.tryParse(const String.fromEnvironment('DEFAULT_LNG')) ?? 127.0927;

  /// WebSocket 주소 (http → ws, https → wss)
  static String get chatSocketUrl {
    final base = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    if (base.startsWith('https://')) return 'wss://${base.substring(8)}/ws/chat';
    if (base.startsWith('http://')) return 'ws://${base.substring(7)}/ws/chat';
    return '$base/ws/chat';
  }
}
