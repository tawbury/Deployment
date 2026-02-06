#!/bin/bash
# Phase 13 JSONL to DB Migration Script
# Docker 환경에서 실행

set -e

echo "================================="
echo "Phase 13: JSONL to PostgreSQL Migration"
echo "================================="
echo ""

# 데이터 확인
# 데이터 확인 (Asset 디렉토리)
SCALP_DIR="/opt/platform/runtime/observer/data/assets/scalp"
SWING_DIR="/opt/platform/runtime/observer/data/assets/swing"

echo "Checking data directories:"
echo "  Scalp: $SCALP_DIR"
if [ -d "$SCALP_DIR" ]; then
    SCALP_FILES=$(find "$SCALP_DIR" -name "*.jsonl" | wc -l)
    echo "    ✓ Found $SCALP_FILES JSONL files"
else
    echo "    ✗ Directory not found"
fi

echo "  Swing: $SWING_DIR"
if [ -d "$SWING_DIR" ]; then
    SWING_FILES=$(find "$SWING_DIR" -name "*.jsonl" | wc -l)
    echo "    ✓ Found $SWING_FILES JSONL files"
else
    echo "    ✗ Directory not found"
fi

echo ""
echo "DB Connection:"
echo "  Host: $DB_HOST"
echo "  User: $DB_USER"
echo "  Database: $DB_NAME"
echo ""

# Python 마이그레이션 스크립트 실행
echo "Starting migration..."
cd /opt/platform/observer/src
python -m db.migrate_jsonl_to_db

echo ""
echo "================================="
echo "Migration completed!"
echo "================================="
