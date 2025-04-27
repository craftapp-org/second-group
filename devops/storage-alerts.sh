#!/bin/bash
set -e

# Config
ALERT_THRESHOLD=80  # Percentage usage threshold
ADMIN_EMAIL="admin@yourdomain.com"
SLACK_WEBHOOK=""  # Optional: "https://hooks.slack.com/services/XXX"

# Get all projects
PROJECTS=($(ls /var/projects))

for PROJECT in "${PROJECTS[@]}"; do
  # Get quota info
  if grep -q "prjquota" /etc/fstab; then
    # XFS quota system
    USAGE_INFO=$(sudo xfs_quota -x -c "report -p /var/projects/$PROJECT" / | grep "postgres_data")
    USAGE_MB=$(echo "$USAGE_INFO" | awk '{print $3}')
    LIMIT_MB=$(echo "$USAGE_INFO" | awk '{print $4}')
  else
    # ext4 quota system
    USAGE_INFO=$(sudo repquota -P / | grep "$PROJECT")
    USAGE_MB=$(echo "$USAGE_INFO" | awk '{print $3}')
    LIMIT_MB=$(echo "$USAGE_INFO" | awk '{print $4}')
  fi

  # Calculate percentage
  if [[ -z "$USAGE_MB" || -z "$LIMIT_MB" ]]; then
    echo "⚠️ Could not get storage info for $PROJECT"
    continue
  fi

  USAGE_PERCENT=$((USAGE_MB * 100 / LIMIT_MB))

  # Generate message
  MESSAGE="Storage Alert: $PROJECT at $USAGE_PERCENT% usage ($USAGE_MB MB/$LIMIT_MB MB)"

  # Send alerts if threshold exceeded
  if [[ $USAGE_PERCENT -ge $ALERT_THRESHOLD ]]; then
    # Email alert
    echo "$MESSAGE" | mail -s "🚨 Storage Alert: $PROJECT" "$ADMIN_EMAIL"

    # Slack alert (if webhook configured)
    if [[ -n "$SLACK_WEBHOOK" ]]; then
      curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$MESSAGE\"}" \
        "$SLACK_WEBHOOK"
    fi

    # System log
    logger -t storage-alerts "$MESSAGE"
  fi
done