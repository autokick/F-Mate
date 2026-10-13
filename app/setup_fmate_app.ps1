# F-Mate: create the Android Studio project (fmate_app) from this folder on any Windows PC.
#
# What it does:
#   1. flutter create  (makes the android/ folder for THIS PC's Flutter version)
#   2. copies lib/, test/, pubspec.yaml from this folder
#   3. applies the Android settings from ANDROID_SETUP.md steps 1-3
#        - minSdk 24
#        - permissions, app name "F-Mate", payment app <queries>
#        - debug-only http (cleartext) for the local server
#   4. flutter pub get
#
# Run (PowerShell, from C:\dev\fmate\app):
#   powershell -ExecutionPolicy Bypass -File .\setup_fmate_app.ps1
# Options:
#   -Target C:\dev\fmate_app        where to create the project (default)
#   -Flutter C:\src\flutter\bin\flutter.bat
#   -Force                          overwrite lib/test/pubspec in an existing project

param(
    [string]$Target = "C:\dev\fmate_app",
    [string]$Flutter = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Flutter {
    if ($Flutter -and (Test-Path $Flutter)) { return $Flutter }
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("C:\src\flutter\bin\flutter.bat", "$env:USERPROFILE\flutter\bin\flutter.bat", "C:\flutter\bin\flutter.bat")) {
        if (Test-Path $p) { return $p }
    }
    throw "Flutter not found. Install Flutter (e.g. C:\src\flutter) or pass -Flutter <path to flutter.bat>."
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

$fl = Find-Flutter
Write-Host "Flutter: $fl"

if ($Target -match "OneDrive") {
    Write-Warning "Target is inside OneDrive. Flutter often fails there (locked files). Prefer C:\dev\fmate_app."
}

# 1. flutter create (only if the project does not exist yet)
if (-not (Test-Path (Join-Path $Target "android"))) {
    $parent = Split-Path -Parent $Target
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    Write-Host "Creating Flutter project at $Target ..."
    & $fl create --org app.fmate --project-name fmate_app --platforms android $Target
    if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }
} elseif (-not $Force) {
    Write-Host "Project already exists at $Target. Code is NOT overwritten (use -Force to overwrite lib/test/pubspec). Android settings are still checked."
}

# 2. copy app code
if ($Force -or -not (Test-Path (Join-Path $Target "lib\core"))) {
    Write-Host "Copying lib/, test/, pubspec.yaml ..."
    foreach ($d in @("lib", "test")) {
        $dst = Join-Path $Target $d
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
        Copy-Item -Recurse (Join-Path $Here $d) $dst
    }
    Copy-Item -Force (Join-Path $Here "pubspec.yaml") (Join-Path $Target "pubspec.yaml")
}

# 3a. minSdk 24 (Kotlin DSL or Groovy)
$gradleKts = Join-Path $Target "android\app\build.gradle.kts"
$gradleGroovy = Join-Path $Target "android\app\build.gradle"
foreach ($g in @($gradleKts, $gradleGroovy)) {
    if (Test-Path $g) {
        $t = [System.IO.File]::ReadAllText($g)
        if ($t -match "flutter\.minSdkVersion") {
            $t = $t -replace "flutter\.minSdkVersion", "24"
            Write-Utf8NoBom $g $t
            Write-Host "minSdk -> 24 ($g)"
        }
    }
}

# 3b. main AndroidManifest: permissions, label, queries
$manifest = Join-Path $Target "android\app\src\main\AndroidManifest.xml"
$m = [System.IO.File]::ReadAllText($manifest)
if ($m -notmatch "ACCESS_FINE_LOCATION") {
    $perms = @"

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
"@
    $rx = [regex]"<manifest[^>]*>"
    $m = $rx.Replace($m, { param($x) $x.Value + $perms }, 1)
    Write-Host "Permissions added"
}
$m = [regex]::Replace($m, 'android:label="[^"]*"', 'android:label="F-Mate"')
if ($m -notmatch "viva\.republica\.toss") {
    $q = @"
        <!-- Payment window: card / easy-pay apps, phone dialer (Android 11+) -->
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
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

"@
    if ($m -match "</queries>") {
        $idx = $m.LastIndexOf("</queries>")
        $m = $m.Substring(0, $idx) + $q + "    " + $m.Substring($idx)
    } else {
        $idx = $m.LastIndexOf("</manifest>")
        $m = $m.Substring(0, $idx) + "    <queries>`n" + $q + "    </queries>`n" + $m.Substring($idx)
    }
    Write-Host "Payment app <queries> added"
}
Write-Utf8NoBom $manifest $m

# 3c. debug-only cleartext http (emulator -> http://10.0.2.2:8080)
$debugDir = Join-Path $Target "android\app\src\debug"
if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir | Out-Null }
Write-Utf8NoBom (Join-Path $debugDir "AndroidManifest.xml") @"
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true" />
</manifest>
"@
Write-Host "Debug cleartext http enabled"

# 4. pub get
Push-Location $Target
try {
    & $fl pub get
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Done. Open $Target in Android Studio, pick an emulator, and press Run."
