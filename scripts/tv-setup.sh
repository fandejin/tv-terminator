#!/usr/bin/env bash
# 小米/Android TV 一键配置脚本
# 用法: ./tv-setup.sh <电视IP> [代理IP:端口]
# 示例: ./tv-setup.sh <电视IP> <电视IP>:7897
#
# 只做四件事：连设备 → 查架构 → 装 APK → 设代理
# 不做任何删除操作，所有命令可回滚。

set -euo pipefail

IP="${1:-}"
PROXY="${2:-}"

if [[ -z "$IP" ]]; then
  echo "用法: $0 <电视IP> [代理IP:端口]"
  echo "示例: $0 <电视IP> <电视IP>:7897"
  exit 1
fi

command -v adb >/dev/null || { echo "❌ 没装 adb，请先安装 platform-tools"; exit 1; }

echo "▶ 连接 $IP:5555 ..."
adb connect "$IP:5555" || true
sleep 1
adb devices

DEV="$IP:5555"
adb -s "$DEV" shell echo ok >/dev/null 2>&1 || { echo "❌ 连不上，检查电视 ADB 调试是否开启、是否同一网段"; exit 1; }

echo
echo "▶ 设备信息"
adb -s "$DEV" shell getprop ro.product.model
ABI=$(adb -s "$DEV" shell getprop ro.product.cpu.abilist | tr -d '\r')
echo "   CPU 架构: $ABI"
if echo "$ABI" | grep -q "arm64-v8a"; then
  ARCH="arm64"
  echo "   → 64 位设备，装通用包"
else
  ARCH="v7a"
  echo "   → 32 位设备，必须装 v7a 包"
fi

echo
echo "▶ 安装 APK（当前目录）"
shopt -s nullglob
for apk in *.apk; do
  if [[ "$ARCH" == "v7a" && "$apk" != *v7a* && "$apk" != "TVBro.apk" ]]; then
    echo "   跳过 $apk（32 位设备，请用 v7a 包）"
    continue
  fi
  echo "   安装 $apk ..."
  adb -s "$DEV" install -r "$apk" | tail -1
done
shopt -u nullglob

if [[ -n "$PROXY" ]]; then
  echo
  echo "▶ 设置全局代理 $PROXY"
  echo "   （必须是电脑的【局域网 IP】，填 WSL 虚拟网卡 IP 会一直转圈）"
  adb -s "$DEV" shell settings put global http_proxy "$PROXY"
  adb -s "$DEV" shell settings get global http_proxy
  echo "   取消代理: adb shell settings put global http_proxy :0"
fi

echo
echo "✅ 完成。"
echo "   换默认桌面: adb shell cmd package set-home-activity --user 0 com.ts.launcher/com.gathin.tvhome.MainActivity"
echo "   回滚原桌面: adb shell pm enable com.mitv.tvhome"
