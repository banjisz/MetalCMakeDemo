#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MetalCMakeDemo"
BUNDLE_ID="com.example.metalcmakedemo"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PROJECT_PATH="$BUILD_DIR/$APP_NAME.xcodeproj"
APP_BUNDLE="$BUILD_DIR/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

kill_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

configure_project() {
  cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G Xcode
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination "platform=macOS" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_artifacts() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found: $APP_BUNDLE" >&2
    exit 1
  fi

  if [[ ! -x "$APP_BINARY" ]]; then
    echo "App binary not found: $APP_BINARY" >&2
    exit 1
  fi
}

kill_running_app
configure_project
build_app
verify_artifacts

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Verified: $APP_NAME is running."
    ;;
  *)
    usage
    exit 2
    ;;
esac
