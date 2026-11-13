#!/bin/sh
# 合并 base.yaml + overlays/<device>.yaml，注入订阅地址与 API secret，并做 mihomo -t 校验。
# 用法：./scripts/build-configs.sh [router|macos|all]
# 依赖：mihomo（可选，用于 -t；没有则跳过校验）
# 输入：
#   mihomo/subscription.url  订阅地址（git 忽略，由 set-subscription.sh 写入）
#   mihomo/.secret           API secret（首次运行自动生成，git 忽略）
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BASE="$DIR/base.yaml"
URL_FILE="${SUBSCRIPTION_URL_FILE:-$DIR/subscription.url}"
SECRET_FILE="$DIR/.secret"
BIN="${MIHOMO_BIN:-$(command -v mihomo 2>/dev/null || true)}"
TARGET="${1:-all}"

fail() { echo "!! $*" >&2; exit 1; }

[ -f "$URL_FILE" ] || fail "缺少 ${URL_FILE}；先运行 ./scripts/set-subscription.sh '<订阅地址>'"
URL=$(sed -n '1p' "$URL_FILE" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -n "$URL" ] || fail "${URL_FILE} 为空"
case "$URL" in
  *__SUBSCRIPTION_URL__*|*REPLACE_ME*) fail "${URL_FILE} 仍是占位符，请填写真实订阅地址" ;;
esac

if [ ! -s "$SECRET_FILE" ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16 > "$SECRET_FILE"
  else
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' > "$SECRET_FILE"
  fi
  chmod 600 "$SECRET_FILE"
fi
SECRET=$(tr -d '\r\n' < "$SECRET_FILE")

# sed 替换串转义：反斜杠、&、竖线
esc() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
URL_ESC=$(esc "$URL")
SECRET_ESC=$(esc "$SECRET")

TMP_BASE=$(mktemp)
TMP_OVER=$(mktemp)
TMP_OUT=""
trap 'rm -f "$TMP_BASE" "$TMP_OVER" ${TMP_OUT:+"$TMP_OUT"}' EXIT INT TERM
sed "s|__SUBSCRIPTION_URL__|$URL_ESC|g" "$BASE" > "$TMP_BASE"

build() {
  device="$1"
  out="$DIR/$device.yaml"
  overlay="$DIR/overlays/$device.yaml"
  cache=$(mktemp -d)
  TMP_OUT="$out.tmp.$$"

  sed "s|__API_SECRET__|$SECRET_ESC|g" "$overlay" > "$TMP_OVER"
  cat "$TMP_BASE" "$TMP_OVER" > "$TMP_OUT"

  if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "!! 未找到 mihomo，跳过 ${device} 的 -t 校验（可设置 MIHOMO_BIN=...）" >&2
  else
    "$BIN" -t -d "$cache" -f "$TMP_OUT"
  fi

  mv "$TMP_OUT" "$out"
  rm -rf "$cache"
  echo ">> 已生成 ${out}"
}

case "$TARGET" in
  router|macos) build "$TARGET" ;;
  all) build router; build macos ;;
  *) echo "用法: $0 [router|macos|all]" >&2; exit 2 ;;
esac
