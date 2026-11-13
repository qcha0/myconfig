#!/bin/sh
# 安装 dnsmasq 的 CN/海外 分离解析，并让 OpenWrt 的 dnsmasq 读取 /etc/dnsmasq.d。
# 效果：CN 域名 → 223.5.5.5；其余 → mihomo 127.0.0.1:1053（fake-IP）。
# mihomo 挂掉时 CN 域名仍可解析，符合"不影响国内访问"的要求。
set -eu

DEST=/etc/dnsmasq.d
BASE=https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"

# 1) 基础分流规则（唯一来源，避免 conf-dir 重复包含）
cat > "$DEST/00-mihomo-split.conf" <<'CONF'
no-resolv
strict-order
server=127.0.0.1#1053
server=223.5.5.5
cache-size=10000
CONF

# 2) CN 域名列表（把默认的 114.114.114.114 换成 223.5.5.5）
fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BASE/$1" -o "$TMP/$1"
  else
    wget -qO "$TMP/$1" "$BASE/$1"
  fi
}

fetch accelerated-domains.china.conf
sed 's#/114\.114\.114\.114$#/223.5.5.5#' "$TMP/accelerated-domains.china.conf" > "$DEST/10-china-accelerated.conf"

fetch apple.china.conf
sed 's#/114\.114\.114\.114$#/223.5.5.5#' "$TMP/apple.china.conf" > "$DEST/11-china-apple.conf"

fetch google.china.conf
sed 's#/114\.114\.114\.114$#/223.5.5.5#' "$TMP/google.china.conf" > "$DEST/12-china-google.conf"

# 3) 让 dnsmasq 读取该目录（procd jail 会挂载 confdir，/etc/dnsmasq.d 不会被读）
uci set dhcp.@dnsmasq[0].confdir="$DEST"
uci commit dhcp

/etc/init.d/dnsmasq restart
echo ">> CN 域名分流规则：$(wc -l < "$DEST/10-china-accelerated.conf") 条"
echo ">> 默认上游：127.0.0.1#1053 (mihomo) / 兜底 223.5.5.5"
