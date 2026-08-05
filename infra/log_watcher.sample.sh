#!/bin/bash
# =====================================================================
# 경량 로그 워처 → Discord 실시간 알림 (발췌·정제 버전)
# 에러 로그 파일을 tail 하며 신규 에러를 Discord 웹훅으로 푸시.
# 실제 웹훅 URL은 환경변수로 주입합니다. (원본에 하드코딩돼 있던 URL은 폐기)
# =====================================================================

# 운영에서는 .env 등으로 주입: export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
ERROR_LOG_PATH="/usr/src/app/logging/logs/errors.log"
LOCK_DIR="/tmp/log_watcher.lock"   # 중복 알림 방지용 lock

if [ -z "$WEBHOOK_URL" ]; then
    echo "[log_watcher] DISCORD_WEBHOOK_URL is not set. Exiting."
    exit 1
fi

send_alert() {
    local message="$1"
    # 중복 전송 방지 (동시 실행 시 하나만 전송)
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        JSON_PAYLOAD=$(printf '{"content": "🚨 %s"}' "$message")
        curl -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$WEBHOOK_URL" > /dev/null 2>&1
        rmdir "$LOCK_DIR"
    fi
}

# 신규 에러 라인 감시
tail -Fn0 "$ERROR_LOG_PATH" | while read -r line; do
    if echo "$line" | grep -qiE 'error|fatal|exception'; then
        send_alert "$line"
    fi
done
