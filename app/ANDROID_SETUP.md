# Android 설정 (Android Studio)

`lib/`, `test/`, `pubspec.yaml`을 덮어쓴 뒤 **`android/` 폴더에서 한 번만** 해 줄 설정이다.
Flutter 3.29 이후 새 프로젝트는 Gradle 파일이 `build.gradle.kts`(Kotlin)이다. 예전 `build.gradle`(Groovy)이면 괄호 안의 Groovy 문법을 쓴다.

## 1. 최소 SDK — `android/app/build.gradle.kts`

```kotlin
android {
    defaultConfig {
        applicationId = "app.fmate"      // 원하는 패키지명. 스토어 등록 후에는 바꿀 수 없다
        minSdk = 24                      // flutter.minSdkVersion 대신 (Firebase·지도·WebView 요구)
        // targetSdk, versionCode, versionName 은 기본값 유지
    }
}
```
(Groovy: `minSdkVersion 24`)

## 2. 권한·앱 이름 — `android/app/src/main/AndroidManifest.xml`

`<manifest>` 바로 아래, `<application>` 위에 추가:

```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <!-- 내 주변 풋살장 (사용자가 동의할 때만 요청) -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <!-- Android 13+ 푸시 알림 -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

```

그리고 **파일 맨 아래에 이미 있는 `<queries>` 블록 안에** 아래 내용을 추가한다 (Flutter가 만든 `PROCESS_TEXT` 항목은 그대로 둔다. `<queries>`를 하나 더 만들지 말 것):

```xml
        <!-- Android 11+ : 결제창에서 카드사·간편결제 앱, 지도·전화 앱을 열 수 있도록 -->
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <!-- 주요 카드사·간편결제 앱 (토스페이먼츠 안내 목록 기준으로 필요 시 추가) -->
        <package android:name="viva.republica.toss" />
        <package android:name="com.kakao.talk" />
        <package android:name="com.nhn.android.search" />
        <package android:name="com.samsung.android.spay" />
        <package android:name="kvp.jjy.MispAndroid320" />
        <package android:name="com.kbcard.cxh.appcard" />
        <package android:name="com.shcard.smartpay" />
        <package android:name="com.hyundaicard.appcard" />
        <package android:name="com.lcacApp" />
        <package android:name="kr.co.samsungcard.mpocket" />
        <package android:name="com.hanaskcard.paycllo" />
        <package android:name="nh.smart.nhallonepay" />
        <package android:name="com.wooricard.smartapp" />
```

그리고 `<application android:label="...">`의 값을 `"F-Mate"`로 바꾼다.

카드사 앱 목록은 바뀔 수 있으므로 토스페이먼츠 개발자센터의 "Android 웹뷰 연동" 안내에서 최신 목록을 확인한다.
앱을 찾지 못하면 결제 화면이 Play 스토어 설치 페이지로 보낸다(이미 구현됨).

## 3. 개발 중 http 접속 허용 — `android/app/src/debug/AndroidManifest.xml`

에뮬레이터에서 PC 서버(`http://10.0.2.2:8080`)에 붙으려면 **디버그 빌드에서만** 평문 http를 허용한다.
(릴리스 빌드는 https만 쓰도록 이 설정을 main 매니페스트에 넣지 않는다.)

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true" />
</manifest>
```

이 설정이 없으면 앱이 "서버에 연결할 수 없어요"만 보여준다.

## 4. (선택) Google Maps — 풋살장 지도 보기

1. Google Cloud Console → "Maps SDK for Android" 사용 설정 → API 키 생성 → **Android 앱 제한**(패키지명 + SHA-1)
2. `AndroidManifest.xml`의 `<application>` 안에:
   ```xml
   <meta-data android:name="com.google.android.geo.API_KEY" android:value="여기에_키"/>
   ```
3. 실행: `flutter run --dart-define=MAPS_ENABLED=true`, 서버 `.env`에 `MAPS_ENABLED=true`

키가 없으면 지도 대신 목록만 보인다(앱이 멈추지 않음). 키를 저장소에 올리고 싶지 않으면 `local.properties` + `manifestPlaceholders`로 주입한다.

## 5. (선택) 푸시 알림 — Firebase

1. Firebase 콘솔에서 Android 앱 등록(패키지명 = `applicationId`) → `google-services.json`을 `android/app/`에 둔다
2. `android/settings.gradle.kts`의 `plugins { }` 에 추가:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```
   `android/app/build.gradle.kts`의 `plugins { }` 에 추가:
   ```kotlin
   id("com.google.gms.google-services")
   ```
3. 실행: `flutter run --dart-define=PUSH_ENABLED=true`, 서버에는 서비스 계정 JSON 경로(`FCM_CREDENTIALS_PATH`)

`PUSH_ENABLED`를 켜지 않으면 Firebase를 초기화하지 않으므로 `google-services.json` 없이도 빌드·실행된다. 이때도 앱 안의 알림 목록은 동작한다.

## 6. 실행

```bash
flutter pub get
flutter run                                   # 에뮬레이터 + PC에서 docker compose up 한 서버
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080   # 실제 휴대폰 (PC의 Wi-Fi IP)
flutter test                                  # 위젯·단위 테스트 (가짜 서버 사용, 서버 불필요)
flutter analyze
```

## 7. 릴리스 빌드·서명 (스토어 출시 시)

1. 업로드 키 만들기 (한 번만, 분실하면 업데이트 불가 — 안전하게 보관):
   ```bash
   keytool -genkey -v -keystore ~/fmate-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. `android/key.properties` (커밋 금지 — `.gitignore`에 추가):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/절대경로/fmate-upload.jks
   ```
3. `android/app/build.gradle.kts`:
   ```kotlin
   import java.util.Properties
   import java.io.FileInputStream

   val keystoreProperties = Properties().apply {
       val f = rootProject.file("key.properties")
       if (f.exists()) load(FileInputStream(f))
   }

   android {
       signingConfigs {
           create("release") {
               keyAlias = keystoreProperties["keyAlias"] as String?
               keyPassword = keystoreProperties["keyPassword"] as String?
               storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
               storePassword = keystoreProperties["storePassword"] as String?
           }
       }
       buildTypes {
           release {
               signingConfig = signingConfigs.getByName("release")
           }
       }
   }
   ```
4. 빌드:
   ```bash
   flutter build appbundle --release \
     --dart-define=API_BASE_URL=https://api.도메인 --dart-define=ENV=prod
   ```
   결과물 `build/app/outputs/bundle/release/app-release.aab`를 Play Console에 올린다.
5. 앱 아이콘: `android/app/src/main/res/mipmap-*`를 교체하거나 `flutter_launcher_icons` 패키지 사용.

Play Console 제출 시 필요한 것: 개인정보처리방침 URL, 데이터 보안 양식(수집 항목: 이메일, 닉네임, 위치(선택), 사진·영상, 결제는 토스가 처리), 콘텐츠 등급, 스크린샷, 테스트 계정(심사용).
