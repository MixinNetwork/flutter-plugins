#!/usr/bin/env bash
set -euo pipefail
# Usage: run_shared_toolbar_engine_test.sh /path/to/flutter
# Requires a Flutter source checkout, a C++17 host compiler, and no Windows SDK.
flutter_root="${1:?Pass the Flutter source checkout root (verified with 3.47.6)}"
test_dir="$(cd "$(dirname "$0")" && pwd)"
platform="$flutter_root/engine/src/flutter/shell/platform"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
"${CXX:-g++}" -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-pessimizing-move \
  -I"$test_dir/stubs" -I"$flutter_root/engine/src" \
  -isystem "$platform/windows/public" -isystem "$platform/common/public" \
  -isystem "$platform/windows/client_wrapper/include" \
  -isystem "$platform/common/client_wrapper/include" \
  -isystem "$platform/common/client_wrapper/include/flutter" \
  "$test_dir/shared_toolbar_engine_test.cc" \
  "$test_dir/../flutter_view.cc" "$test_dir/../message_channel_plugin.cc" \
  "$platform/common/client_wrapper/core_implementations.cc" \
  "$platform/common/client_wrapper/plugin_registrar.cc" \
  "$platform/common/client_wrapper/standard_codec.cc" \
  -o "$build_dir/shared_toolbar_engine_test"
"$build_dir/shared_toolbar_engine_test"
