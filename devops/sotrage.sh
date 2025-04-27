#!/bin/bash
set -e

# Storage Manager Script
# Usage: ./storage-manager.sh <project-name> <storage-limit-gb> [action]
# Actions: create (default) | delete | check | resize

# Config
STORAGE_BASE="/var/projects"  # Base directory for all project storage
QUOTA_TYPE="xfs"             # "xfs" or "ext4" (auto-detected if empty)
PROJECT_NAME="$1"
STORAGE_LIMIT_GB="$2"
ACTION="${3:-create}"

# Validate inputs
if [[ -z "$PROJECT_NAME" || ( "$ACTION" == "create" && -z "$STORAGE_LIMIT_GB" ) ]]; then
  echo "Usage: $0 <project-name> <storage-limit-gb> [create|delete|check|resize]"
  exit 1
fi

PROJECT_STORAGE="$STORAGE_BASE/$PROJECT_NAME"

# Auto-detect filesystem if not specified
if [[ -z "$QUOTA_TYPE" ]]; then
  if findmnt -n -o FSTYPE -T "$STORAGE_BASE" | grep -q xfs; then
    QUOTA_TYPE="xfs"
  else
    QUOTA_TYPE="ext4"
  fi
fi

case "$ACTION" in
  create)
    echo "🔧 Creating storage for $PROJECT_NAME with ${STORAGE_LIMIT_GB}GB limit"
    
    # Create directories
    sudo mkdir -p "$PROJECT_STORAGE"/{postgres_data,uploads}
    sudo chown -R ubuntu:ubuntu "$PROJECT_STORAGE"
    
    # Set quotas
    if [[ "$QUOTA_TYPE" == "xfs" ]]; then
      PROJECT_ID=$(date +%s | tail -c 5)
      sudo xfs_quota -x -c "project -s -p $PROJECT_STORAGE/postgres_data $PROJECT_ID" / &&
      sudo xfs_quota -x -c "limit -p bhard=${STORAGE_LIMIT_GB}G $PROJECT_ID" /
    else # ext4
      PROJECT_ID=$(($(sudo ls -1 "$STORAGE_BASE" | wc -l)+1000))
      echo "$PROJECT_ID:$PROJECT_STORAGE/postgres_data" | sudo tee -a /etc/projects >/dev/null
      sudo setquota -P $PROJECT_ID 0 $((STORAGE_LIMIT_GB*1024)) 0 0 /
    fi
    
    echo "✅ Created | Type: $QUOTA_TYPE | Path: $PROJECT_STORAGE"
    ;;

  delete)
    echo "🗑️ Removing storage for $PROJECT_NAME"
    
    # Stop containers using this storage
    if docker ps -q --filter "volume=$PROJECT_STORAGE"; then
      docker stop $(docker ps -q --filter "volume=$PROJECT_STORAGE")
    fi
    
    # Remove quota
    if [[ "$QUOTA_TYPE" == "ext4" ]]; then
      sudo sed -i "/$PROJECT_NAME/d" /etc/projects
      sudo quotaoff -P "$PROJECT_STORAGE" 2>/dev/null || true
    fi
    
    # Delete data (with confirmation)
    read -p "Delete ALL data in $PROJECT_STORAGE? (y/n) " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      sudo rm -rf "$PROJECT_STORAGE"
      echo "✅ Deleted"
    else
      echo "⚠️ Data preserved at $PROJECT_STORAGE"
    fi
    ;;

  check)
    echo "📊 Storage usage for $PROJECT_NAME"
    
    if [[ "$QUOTA_TYPE" == "xfs" ]]; then
      sudo xfs_quota -x -c "report -p $PROJECT_STORAGE" /
    else
      sudo repquota -P / | grep "$PROJECT_NAME" || true
    fi
    
    echo "📂 Directory sizes:"
    sudo du -sh "$PROJECT_STORAGE"/*
    ;;

  resize)
    NEW_LIMIT_GB="$4"
    if [[ -z "$NEW_LIMIT_GB" ]]; then
      echo "Usage: $0 <project-name> <old-limit> resize <new-limit-gb>"
      exit 1
    fi
    
    echo "🔧 Resizing $PROJECT_NAME from ${STORAGE_LIMIT_GB}GB to ${NEW_LIMIT_GB}GB"
    
    if [[ "$QUOTA_TYPE" == "xfs" ]]; then
      PROJECT_ID=$(sudo xfs_quota -x -c "report -p $PROJECT_STORAGE" / | awk '/Project ID/{print $3}')
      sudo xfs_quota -x -c "limit -p bhard=${NEW_LIMIT_GB}G $PROJECT_ID" /
    else
      PROJECT_ID=$(grep "$PROJECT_NAME" /etc/projects | cut -d: -f1)
      sudo setquota -P $PROJECT_ID 0 $((NEW_LIMIT_GB*1024)) 0 0 /
    fi
    
    echo "✅ Resized | New limit: ${NEW_LIMIT_GB}GB"
    ;;

  *)
    echo "Invalid action: $ACTION"
    exit 1
    ;;
esac

# Verify (except for delete)
if [[ "$ACTION" != "delete" ]]; then
  CURRENT_USAGE=$(sudo du -s "$PROJECT_STORAGE" | cut -f1)
  echo "ℹ️ Current usage: $((CURRENT_USAGE/1024))MB/$((STORAGE_LIMIT_GB*1024))MB"
fi




# Create storage
./storage-manager.sh myapp 30 create

# Check usage
./storage-manager.sh myapp 30 check

# Resize
./storage-manager.sh myapp 30 resize 50

# Delete
./storage-manager.sh myapp 30 delete