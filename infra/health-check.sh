SERVICE_STATUS=$(systemctl is-active gitlab-runner 2>&1 || echo "inactive")
VALUE=0
if [ "$SERVICE_STATUS" = "active" ]; then VALUE=1; fi

# Get IMDSv2 token
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
--connect-timeout 5 2>/dev/null)

if [ -n "$TOKEN" ]; then
    # Get region using IMDSv2
    REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
        "http://169.254.169.254/latest/dynamic/instance-identity/document" \
    --connect-timeout 5 2>/dev/null | jq -r .region 2>/dev/null)
    
    # Get instance ID using IMDSv2
    INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
        "http://169.254.169.254/latest/meta-data/instance-id" \
    --connect-timeout 5 2>/dev/null)
fi

echo "Publishing metric: region=$REGION, instance=$INSTANCE_ID, value=$VALUE"
aws cloudwatch put-metric-data \
--region "$REGION" \
--namespace "GitLab/Runner" \
--metric-name "RunnerHealthy" \
--value "$VALUE" \
--unit Count \
--dimensions InstanceId="$INSTANCE_ID"