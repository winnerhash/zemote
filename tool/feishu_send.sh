#!/usr/bin/env bash
# Send the built APK to a Feishu user/chat via a self-built app (自建应用).
# Required env:
#   FEISHU_APP_ID      - app_id of the custom app
#   FEISHU_APP_SECRET  - app_secret
#   FEISHU_RECEIVE_ID  - open_id / user_id / chat_id of the recipient
#   FEISHU_RECEIVE_TYPE- open_id (default) | user_id | chat_id
# Optional:
#   FEISHU_APK         - path to the apk (default: build output below)
set -euo pipefail

APK="${FEISHU_APK:-$(dirname "$0")/../build/app/outputs/flutter-apk/app-release.apk}"
: "${FEISHU_APP_ID:?FEISHU_APP_ID not set}"
: "${FEISHU_APP_SECRET:?FEISHU_APP_SECRET not set}"
: "${FEISHU_RECEIVE_ID:?FEISHU_RECEIVE_ID not set}"
RECEIVE_TYPE="${FEISHU_RECEIVE_TYPE:-open_id}"
HOST="https://open.feishu.cn"

echo "== 1/3 tenant_access_token"
TOKEN=$(curl -s "$HOST/open-apis/auth/v3/tenant_access_token/internal" \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);if(j.code!==0){console.error('auth failed:',j.msg);process.exit(1)}console.log(j.tenant_access_token)})")
echo "   token ok (${#TOKEN} chars)"

echo "== 2/3 upload file ($(basename "$APK"), $(du -h "$APK" | cut -f1))"
UPLOAD=$(curl -s "$HOST/open-apis/im/v1/files" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file_type=stream" \
  -F "file_name=$(basename "$APK")" \
  -F "file=@$APK")
echo "   upload resp: $UPLOAD"
FILE_KEY=$(printf '%s' "$UPLOAD" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);if(j.code!==0){console.error('upload failed:',j.msg);process.exit(1)}console.log(j.data.file_key)})")

echo "== 3/3 send file message"
curl -s "$HOST/open-apis/im/v1/messages?receive_id_type=$RECEIVE_TYPE" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"receive_id\":\"$FEISHU_RECEIVE_ID\",\"msg_type\":\"file\",\"content\":\"{\\\"file_key\\\":\\\"$FILE_KEY\\\"}\"}"
echo
echo "== done"
