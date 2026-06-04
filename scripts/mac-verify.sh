#!/usr/bin/env bash
# One-shot native verification on a real Mac (e.g. a rented bare-metal EC2 mac2.metal).
#
# On a GPU-having Mac, every headless test that "skips" in CI will actually RUN here,
# validating the whole blind-written Metal path:
#   - Metal device present
#   - MSL -> MTLLibrary -> compute pipeline -> dispatch -> readback
#   - GLSL -> MSL -> Metal end-to-end (the Phase 2 proof)
#   - IOSurface <-> MTLTexture share memory
#
# Usage on a fresh EC2 Mac:
#   git clone <repo> && cd <repo> && bash scripts/mac-verify.sh

set -uo pipefail
cd "$(dirname "$0")/.."

echo "==> Host: $(uname -mrs)"
echo "==> Checking tools"

# Homebrew (EC2 Mac AMIs ship it; install if missing).
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found — install it from https://brew.sh first."; exit 1
fi

command -v cmake >/dev/null 2>&1 || brew install cmake
# JDK for JNI headers (find_package(JNI)).
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -d "$(brew --prefix)/opt/openjdk@21" ]; then
    export JAVA_HOME="$(brew --prefix)/opt/openjdk@21"
  else
    brew install openjdk@21
    export JAVA_HOME="$(brew --prefix)/opt/openjdk@21"
  fi
fi
echo "    JAVA_HOME=$JAVA_HOME"
echo "    cmake=$(cmake --version | head -1)"

echo "==> Configuring + building native (fetches glslang/SPIRV-Cross on first run)"
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release || { echo "CONFIGURE FAILED"; exit 1; }
cmake --build native/build -j"$(sysctl -n hw.ncpu)" || { echo "BUILD FAILED"; exit 1; }

# Run a test, interpret 0=pass 2=skip(no device) other=fail.
run() {
  local name="$1"; local bin="native/build/$1"
  if [ ! -x "$bin" ]; then echo "  [MISS] $name (not built)"; FAILED=1; return; fi
  echo "---- $name ----"
  "$bin"; local rc=$?
  if   [ $rc -eq 0 ]; then echo "  [PASS] $name"
  elif [ $rc -eq 2 ]; then echo "  [SKIP] $name (no Metal device — unexpected on bare metal!)"; SKIPPED=1
  else echo "  [FAIL] $name (rc=$rc)"; FAILED=1
  fi
}

FAILED=0; SKIPPED=0
echo "==> Running tests"
run transpiler_test               # CPU
run trampoline_test               # CPU
run headless_compute_test         # GPU
run headless_iosurface_test       # GPU
run headless_compute_pipeline_test # GPU
run headless_e2e_test             # GPU — the Phase 2 crown jewel

echo "============================================================"
if [ $FAILED -ne 0 ]; then
  echo "RESULT: FAILURES present — see [FAIL] above."; exit 1
elif [ $SKIPPED -ne 0 ]; then
  echo "RESULT: some GPU tests SKIPPED — no Metal device found (wrong on bare metal)."; exit 2
else
  echo "RESULT: ALL PASS — Metal compute + transpiler end-to-end verified on real hardware."
fi
