#!/usr/bin/env bash
# HomeKey Stand-in — 主页替身 构建脚本
# 不依赖 Gradle，只用 Android SDK 自带的 javac / d8 / aapt2 / zipalign / apksigner
#
# 用法：
#   ./build.sh --target-pkg app.orchard.tv --target-class app.orchard.tv.MainActivity
#   ./build.sh --pkg com.ts.launcher \
#              --target-pkg app.orchard.tv --target-class app.orchard.tv.MainActivity
#
# 参数：
#   --pkg           替身自己的包名（默认 com.ts.launcher，小米电视上实测唯一被认的包名）
#   --target-pkg    要跳转的桌面包名（必填）
#   --target-class  要跳转的桌面 Activity 全名（必填）
#   --activity      替身的 Activity 全名（默认 com.homekey.standin.MainActivity）
#   --version-code  版本号（默认 1；覆盖安装已有 App 时要大于等于对方）
#   --out           输出目录（默认 ./dist）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="com.ts.launcher"
ACTIVITY="com.homekey.standin.MainActivity"
TARGET_PKG=""
TARGET_CLS=""
VERSION_CODE=1
OUT="$HERE/dist"

while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG="$2"; shift 2 ;;
    --activity) ACTIVITY="$2"; shift 2 ;;
    --target-pkg) TARGET_PKG="$2"; shift 2 ;;
    --target-class) TARGET_CLS="$2"; shift 2 ;;
    --version-code) VERSION_CODE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

[ -z "$TARGET_PKG" ] && { echo "缺少 --target-pkg" >&2; exit 1; }
[ -z "$TARGET_CLS" ] && { echo "缺少 --target-class" >&2; exit 1; }

# ---------- 定位 Android SDK ----------
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ]; then
  for d in "$HOME/android-sdk" "$HOME/Android/Sdk" "/usr/lib/android-sdk"; do
    [ -d "$d" ] && SDK="$d" && break
  done
fi
[ -z "$SDK" ] || [ ! -d "$SDK" ] && { echo "找不到 Android SDK，请设置 ANDROID_HOME" >&2; exit 1; }

BT="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
[ -z "$BT" ] && { echo "找不到 build-tools" >&2; exit 1; }

ANDROID_JAR=""
for p in "$SDK"/platforms/android-*/android.jar; do
  [ -f "$p" ] && ANDROID_JAR="$p"
done
[ -z "$ANDROID_JAR" ] && { echo "找不到 platforms/android-*/android.jar（需装一个 platform）" >&2; exit 1; }

echo "SDK       : $SDK"
echo "build-tools: $BT"
echo "android.jar: $ANDROID_JAR"
echo "替身包名   : $PKG"
echo "跳转目标   : $TARGET_PKG / $TARGET_CLS"

# ---------- 准备构建目录 ----------
BUILD="$HERE/.build"
rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$BUILD/cls" "$BUILD/dex" "$OUT"

# ---------- 由 --activity 反推 Java 包名/类名 ----------
# 必须让 javac 编出来的类 <==> manifest 里声明的 Activity 完全一致，
# 否则系统一拉起就 ClassNotFoundException，进而无限崩溃重启（电视直接卡死）
ACT_PKG="${ACTIVITY%.*}"
ACT_SIMPLE="${ACTIVITY##*.}"
[ -z "$ACT_PKG" ] || [ "$ACT_PKG" = "$ACTIVITY" ] && { echo "--activity 必须写全名，如 com.foo.bar.MainActivity" >&2; exit 1; }

# ---------- 填充占位符 ----------
sed -e "s|__PKG__|$PKG|g" -e "s|__ACTIVITY__|$ACTIVITY|g" -e "s|__VERSION_CODE__|$VERSION_CODE|g" \
    "$HERE/manifest/AndroidManifest.xml" > "$BUILD/AndroidManifest.xml"

SRC_DIR="$BUILD/src/$(echo "$ACT_PKG" | tr '.' '/')"
mkdir -p "$SRC_DIR"

sed -e "s|^package com.homekey.standin;|package $ACT_PKG;|" \
    -e "s|public class MainActivity|public class $ACT_SIMPLE|" \
    -e "s|__TARGET_PKG__|$TARGET_PKG|g" -e "s|__TARGET_CLS__|$TARGET_CLS|g" \
    "$HERE/src/com/homekey/standin/MainActivity.java" > "$SRC_DIR/$ACT_SIMPLE.java"

# ---------- 编译 ----------
javac -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d "$BUILD/cls" "$SRC_DIR/$ACT_SIMPLE.java" 2>&1 | grep -v "bootstrap class path" || true

"${BT}d8" --lib "$ANDROID_JAR" --min-api 21 --output "$BUILD/dex" "$BUILD/cls/$(echo "$ACT_PKG" | tr '.' '/')"/*.class

"${BT}aapt2" link -I "$ANDROID_JAR" --manifest "$BUILD/AndroidManifest.xml" -o "$BUILD/base.apk"

# ---------- 打包（无 zip 命令也能用） ----------
python3 - "$BUILD/base.apk" "$BUILD/dex/classes.dex" "$BUILD/unsigned.apk" <<'PY'
import sys, zipfile, shutil
base, dex, out = sys.argv[1], sys.argv[2], sys.argv[3]
shutil.copy(base, out)
with zipfile.ZipFile(out, "a", zipfile.ZIP_DEFLATED) as z:
    z.write(dex, "classes.dex")
PY

"${BT}zipalign" -f 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"

# ---------- 签名 ----------
KS="$HOME/.android/debug.keystore"
mkdir -p "$(dirname "$KS")"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

APK="$OUT/homekey-standin-$(echo "$PKG" | tr '.' '_').apk"
"${BT}apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$APK" "$BUILD/aligned.apk"

echo ""
echo "✅ 构建完成: $APK ($(stat -c%s "$APK") bytes)"
echo ""
echo "安装到电视（把 IP 换成你的）:"
echo "  adb connect <电视IP>:5555"
echo "  adb install -r \"$APK\""
echo "  adb shell cmd package set-home-activity --user 0 $PKG/$ACTIVITY"
echo "  adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
