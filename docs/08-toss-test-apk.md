# F-Mate Spark + TossPayments TEST Android APK

## Built experience (unattended capstone exhibition)

- Android app ID: `app.fmate`, Firebase project: `f-mate`, Spark (free).
- Real Firebase email account + verification, Firestore text board, realtime messaging, fictional booking slots; see [07](07-firebase-spark-exhibition.md).
- **Official TossPayments Flutter SDK** `tosspayments_widget_sdk_flutter` version `^2.2.0` (not an imitation UI).
- Toss payment widget/test gateway uses only a `test_gck_` client key. Default is the **public documentation test key** from the official SDK example. Replace it with your own **test client key** when you have a Toss test merchant: `--dart-define=TOSS_TEST_CLIENT_KEY=test_gck_...`
- Walk-up visitors can open **토스페이먼츠 실제 TEST 결제창** without signing up. Signed-in users can also open the widget from one of their **fictional** booking slots.
- The app blocks any non-test client key. All transactions are test-only; real payment methods are not charged in Toss's test environment.
- **Important limitation:** `requestPayment` returns an authentication result. The server-side Toss **confirm** API is deliberately NOT called (no backend with secret key is deployed). The app NEVER marks a slot as paid/financially approved. The resulting screen says “test authentication” and explicitly says “server confirmation not done.”
- TossPay availability in the widget may depend on the public documentation test merchant settings and mobile SDK environment. KakaoPay is not part of this release.
- No merchant secret or live API key is embedded in the APK, repository, or Firestore.
- No production-ready payment records, receipts, refunds, or order-verification backend have been implemented.

## Android package/build/release

The repository has a **build-time generated** Android project (not checked into Git). A GitHub Actions workflow generates it using Flutter stable and `scripts/prepare_android_firebase.py`, then injects `google-services.json` from the private GitHub Actions secret `F_MATE_GOOGLE_SERVICES_JSON`. This JSON was supplied by the project owner for Android package `app.fmate`; its contents are never committed.

```bash
cd app
flutter create --platforms=android --org app.fmate --project-name fmate_app --no-pub .
cd ..
python3 scripts/prepare_android_firebase.py
# Put private google-services.json in app/android/app/google-services.json
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 \
  --dart-define=BACKEND=firebase \
  --dart-define=EXHIBITION_KIOSK=true
```

The GitHub Actions **android-apk** job assembles an Android ARM64 APK artifact. Release tags are created only after CI passes and artifact downloads are verified.

**Signing:** The ephemeral Flutter/Gradle template's debug keystore signs the release-mode APK for exhibition testing, NOT Play Store distribution. Future APKs built with different ephemeral keys may require uninstalling a prior test build. Personal login, chat and Cloud Firestore records persist on the backend (unless explicitly deleted), but app reinstall clears the device session.

## Security and performance caveats

- Firestore rules must be published at [firestore.rules](../firestore.rules) after authorization tests. The user has reported posting them in Firebase Console; release pipeline does not overwrite rules.
- For public/exhibition use, email sign-ups are real Firebase Auth users, not disposable accounts. Avoid entering real personal details in posts/chat. 5-minute kiosk idle sign-out protects the **device**, not backend data retention.
- Payment test client key is embedded (by design, public); **secret approval key is never on-device**.
- Android device Internet connection is necessary. The local rules-based demo bot works without network.
- Flutter build & widget tests are automated. Physical device/TossPay app return flows require on-device QA; a CI-passing APK alone cannot establish payment usability across every Android handset.

Android AGP 9 currently rejects the published `flutter_inappwebview_android 1.1.3` plugin's obsolete ProGuard default; `scripts/patch_toss_inappwebview.py` applies upstream's corrected default **only in the disposable CI pub cache**. This can be removed after a stable upstream fix.
