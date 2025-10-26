# shellcheck shell=bash

SERVICE_STATUS=$(systemctl is-active gitlab-runner 2>&1 || echo "inactive")
PROCESS_COUNT=$(pgrep -c -f gitlab-runner 2> /dev/null || echo "0")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p /var/www/health

# Determine health status
if [ "$SERVICE_STATUS" = "active" ]; then
  HEALTH_STATUS="healthy"
else
  HEALTH_STATUS="unhealthy"
fi

# Create status JSON
echo "{\"status\":\"$HEALTH_STATUS\",\"service\":\"$SERVICE_STATUS\",\"processes\":$PROCESS_COUNT,\"timestamp\":\"$TIMESTAMP\"}" > /var/www/health/status.json
chmod 644 /var/www/health/status.json
