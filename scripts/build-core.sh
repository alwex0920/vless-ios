#!/bin/bash
# Сборка VlessCore.xcframework (Xray-core + go-tun2socks/lwIP) для iOS 12+.
set -euo pipefail

IOS_MIN=12.0
OUT_DIR="$(dirname "$0")/../XrayFramework"

echo "== 1/3 Подготавливаем модуль ядра =="
cd "$(dirname "$0")/../core-go"
GO111MODULE=on go mod tidy

# >>> ДОБАВЛЕНО: обновляем sing до версии с исправлением errNoSuchInterface
GO111MODULE=on go get github.com/sagernet/sing@latest
GO111MODULE=on go mod tidy

echo "== 2/3 Устанавливаем gomobile =="
GO111MODULE=on go install golang.org/x/mobile/cmd/gomobile@latest
export PATH="$PATH:$(go env GOPATH)/bin"
gomobile init

echo "== 3/3 gomobile bind =="
mkdir -p "$OUT_DIR"
GO111MODULE=on go get -t golang.org/x/mobile/cmd/gobind
GO111MODULE=on gomobile bind \
  -target=ios -iosversion "$IOS_MIN" \
  -ldflags="-s -w -checklinkname=0" \
  -o "$OUT_DIR/VlessCore.xcframework" \
  ./vlesscore

echo "Готово: $OUT_DIR/VlessCore.xcframework"
