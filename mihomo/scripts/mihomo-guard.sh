#!/bin/sh
# mihomo 看门狗：连续 3 次 API 探测失败 → 停止 nikki（移除 nft 规则，恢复直连）
# 用法：nohup /usr/local/bin/mihomo-guard.sh >/dev/null 2>&1 &
# 建议放到 /etc/init.d/ 或 crontab 里。
set -u

API=http://127.0.0.1:9090/version
CONF=/etc/nikki/run/config.yaml
INTERVAL=30
FAILS=0

secret=$(sed -n 's/^secret: *//p' "$CONF" 2>/dev/null | tr -d '"' | head -1)

while :; do
  if [ -n "$secret" ]; then
    ok=$(curl -fsS -m 2 -H "Authorization: Bearer $secret" "$API" >/dev/null 2>&1 && echo 1 || echo 0)
  else
    ok=$(curl -fsS -m 2 "$API" >/dev/null 2>&1 && echo 1 || echo 0)
  fi

  if [ "$ok" = 1 ]; then
    FAILS=0
  else
    FAILS=$((FAILS + 1))
    if [ "$FAILS" -ge 3 ]; then
      logger -t mihomo-guard "core unhealthy ${FAILS}x, stopping nikki to restore direct access"
      /etc/init.d/nikki stop || true
      FAILS=0
    fi
  fi
  sleep "$INTERVAL"
done
