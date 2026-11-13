#!/bin/sh
# 一步设置订阅地址：写入 mihomo/subscription.url，同步 QuantumultX.conf，并重建两份配置。
# 用法：./mihomo/scripts/set-subscription.sh 'https://example.com/api/v1/...'
set -eu

[ $# -eq 1 ] || { echo "用法: $0 '<订阅地址>'" >&2; exit 2; }
DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)
URL="$1"
URL_FILE="$DIR/subscription.url"

case "$URL" in
  http://*|https://*) : ;;
  *) echo "!! 订阅地址必须以 http:// 或 https:// 开头" >&2; exit 2 ;;
esac
case "$URL" in
  *__SUBSCRIPTION_URL__*) echo "!! 这是占位符，不是真实地址" >&2; exit 2 ;;
esac

esc() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

OLD=""
[ -f "$URL_FILE" ] && OLD=$(sed -n '1p' "$URL_FILE" | tr -d '\r')

printf '%s\n' "$URL" > "$URL_FILE"
chmod 600 "$URL_FILE"

# 生成 QuantumultX 本地副本（跟踪的 QuantumultX.conf 保持占位符，避免误提交）
Q="$ROOT/QuantumultX.conf"
QLOCAL="$ROOT/QuantumultX.local.conf"
if [ -f "$Q" ]; then
  URL_ESC=$(esc "$URL")
  sed "s|__SUBSCRIPTION_URL__|$URL_ESC|g" "$Q" > "$QLOCAL"
  chmod 600 "$QLOCAL"
fi

"$DIR/scripts/build-configs.sh" all
echo ">> 订阅地址已写入 ${URL_FILE}（该文件不会提交到 git）"
[ -f "$QLOCAL" ] && echo ">> 已生成 ${QLOCAL}（导入 QX 用；同样不会提交）"
