#!/bin/bash

# Health check script for GitLab Runner
set -e

# Check if GitLab Runner service is active
if ! systemctl is-active --quiet gitlab-runner; then
    echo "GitLab Runner service not active"
    exit 1
fi

# Check if GitLab Runner can connect to GitLab
if ! timeout 30 gitlab-runner verify --log-level error >/dev/null 2>&1; then
    echo "GitLab Runner cannot connect to GitLab"
    exit 1
fi

# Check if runner processes are running
if ! pgrep -f gitlab-runner >/dev/null; then
    echo "No GitLab Runner processes found"
    exit 1
fi

# All checks passed
echo "GitLab Runner is healthy"
exit 0
