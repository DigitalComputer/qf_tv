#!/bin/bash
# deploy.sh — Build from source and push to a TV box over SSH
# For fresh Ubuntu installs prefer: scripts/setup-tv-box.sh (downloads GitHub release)
#
# Usage: ./deploy.sh [IP] [QF_API_HOST]
# Example: ./deploy.sh 192.168.1.101 https://demo.queueflow.ao

TARGET_IP=${1:-"192.168.1.101"}
TARGET_USER="kiosk"
DEPLOY_PATH="/opt/qf-tv"
SERVICE_NAME="qf-tv"
API_HOST=${2:-"https://demo.queueflow.ao"}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  QueueFlow qf_tv — SSH deploy (dev)"
echo "  Target: $TARGET_USER@$TARGET_IP"
echo "  API:    $API_HOST"
echo "  Tip: fresh Ubuntu box → scripts/setup-tv-box.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n[1/5] Flutter build (linux release)..."
flutter build linux --release --dart-define=QF_API_HOST="$API_HOST"
if [ $? -ne 0 ]; then
  echo "Build failed"
  exit 1
fi

echo -e "\n[2/5] Preparing target directory..."
ssh "$TARGET_USER@$TARGET_IP" "sudo mkdir -p $DEPLOY_PATH /etc/qf-tv && sudo chown $TARGET_USER:$TARGET_USER $DEPLOY_PATH"

echo -e "\n[3/5] Writing /etc/qf-tv/config.json..."
ssh "$TARGET_USER@$TARGET_IP" "echo '{\"api_host\":\"$API_HOST\"}' | sudo tee /etc/qf-tv/config.json > /dev/null"

echo -e "\n[4/5] Syncing bundle..."
rsync -avz --delete \
  build/linux/x64/release/bundle/ \
  "$TARGET_USER@$TARGET_IP:$DEPLOY_PATH/"

echo -e "\n[5/5] Installing systemd unit and restarting..."
scp systemd/qf-tv.service "$TARGET_USER@$TARGET_IP:/tmp/qf-tv.service"
ssh "$TARGET_USER@$TARGET_IP" "sudo cp /tmp/qf-tv.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable $SERVICE_NAME && sudo systemctl restart $SERVICE_NAME"

echo -e "\nDeploy complete."
