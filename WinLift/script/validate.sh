#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n script/build_and_run.sh
bash -n script/validate.sh

required_files=(
  Package.swift
  Sources/WinLift/App/WinLiftApp.swift
  Sources/WinLiftCore/QEMUCommandBuilder.swift
  Tests/WinLiftCoreTests/QEMUCommandBuilderTests.swift
  Documentation/FABLE5_PROMPT.md
  Documentation/VERIFICATION.md
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "缺少必需文件：$file" >&2
    exit 1
  fi
done

if command -v swift >/dev/null 2>&1; then
  swift package dump-package >/dev/null
  swift test
else
  echo "静态结构与 shell 语法检查通过；当前环境没有 Swift，已跳过 Swift 编译与测试。"
fi
