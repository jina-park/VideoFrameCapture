#!/usr/bin/env bash
set -euo pipefail

echo "=== VideoFrameCapture 프로젝트 설정 ==="

# 1. xcodegen 설치 확인
if ! command -v xcodegen &>/dev/null; then
    echo "xcodegen이 없습니다. Homebrew로 설치합니다..."
    if ! command -v brew &>/dev/null; then
        echo "오류: Homebrew가 필요합니다. https://brew.sh 에서 먼저 설치해주세요."
        exit 1
    fi
    brew install xcodegen
fi

# 2. 기존 .xcodeproj 제거 후 재생성
echo "Xcode 프로젝트 생성 중..."
cd "$(dirname "$0")"
rm -rf VideoFrameCapture.xcodeproj
xcodegen generate

echo ""
echo "✅ 완료! Xcode에서 프로젝트를 엽니다..."
open VideoFrameCapture.xcodeproj
