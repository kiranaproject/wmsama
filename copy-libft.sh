#!/usr/bin/env bash
set -euo pipefail

# Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_LIB="${SCRIPT_DIR}/../floria-toolkit/target/libft.so"
TARGET_DIR="${SCRIPT_DIR}/target"

if [ ! -f "${SOURCE_LIB}" ]; then
  echo "Error: ${SOURCE_LIB} not found." >&2
  echo "Please compile floria-toolkit first (e.g., run 'pasbuild' in ../floria-toolkit)." >&2
  exit 1
fi

mkdir -p "${TARGET_DIR}"
cp -v "${SOURCE_LIB}" "${TARGET_DIR}/"

echo "libft.so copied to ${TARGET_DIR}/"
