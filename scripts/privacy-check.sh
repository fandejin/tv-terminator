#!/usr/bin/env bash
# 检查仓库里有没有私人信息。命中就 exit 1，别 push。
# 用法: bash scripts/privacy-check.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

GREP_OPTS=(--exclude-dir=.git --exclude-dir=node_modules
           --exclude='*.png' --exclude='*.jpg' --exclude='*.apk'
           --exclude='privacy-check.sh')

hits=0
say() { echo "❌ $1"; hits=$((hits+1)); }

# 1. 内网 IP（真实的才拦；127.0.0.1 和占位符不算）
IP_RE='\b(192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})\b'
if grep -rnEI "$IP_RE" . "${GREP_OPTS[@]}" >/dev/null 2>&1; then
  grep -rnEI "$IP_RE" . "${GREP_OPTS[@]}" | head -20
  say "发现内网 IP（应写成 <电视IP> / <电脑IP>）"
fi

# 2. 本机绝对路径（/home/<名字>/ 或 C:\Users\<名字>\；占位符 <你> 不算）
PATH_RE='(^|[^A-Za-z0-9_/])/home/[a-z0-9_-]+/|C:\\\\Users\\\\[^<]'
if grep -rnEI "$PATH_RE" . "${GREP_OPTS[@]}" >/dev/null 2>&1; then
  grep -rnEI "$PATH_RE" . "${GREP_OPTS[@]}" | head -20
  say "发现本机绝对路径/用户名（应写成 ~/ 或 <路径>）"
fi

# 3. 凭据类（只认“有值”的，不认文档里提到这些词）
SECRET_RE='(ssid|wifi_name|wifi-name|password|passwd|serialno|android_id)\s*[=:]\s*["'"'"']?[A-Za-z0-9_@#$%^&*.-]{3,}|(ghp_|gho_|github_pat_|sk-|AKIA)[A-Za-z0-9_]{10,}'
if grep -rnEI "$SECRET_RE" . "${GREP_OPTS[@]}" >/dev/null 2>&1; then
  grep -rnEI "$SECRET_RE" . "${GREP_OPTS[@]}" | sed 's/=.*/=<已隐藏>/' | head -10
  say "发现疑似凭据/WiFi 名/设备号"
fi

# 4. 邮箱 / 手机号（example.com、github noreply 放行）
CONTACT_RE='([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\b1[3-9][0-9]{9}\b)'
if grep -rnEI "$CONTACT_RE" . "${GREP_OPTS[@]}" | grep -vE 'example\.(com|org)|noreply@github|users\.noreply' >/dev/null 2>&1; then
  grep -rnEI "$CONTACT_RE" . "${GREP_OPTS[@]}" | grep -vE 'example\.(com|org)|noreply@github|users\.noreply' | head -10
  say "发现邮箱或手机号"
fi

# 5. 提交信息也别写私事
if git log -n 50 --pretty=%B | grep -qEI "$IP_RE"; then
  say "最近 50 条提交信息里有内网 IP"
fi

if [ "$hits" -eq 0 ]; then
  echo "✅ 没发现私人信息，可以 push"
  exit 0
fi
echo
echo "共 $hits 类问题，先改成占位符再提交。"
exit 1
