#!/usr/bin/env bash
#
# mayhem/build.sh — build Simd's fuzzing harness(es) + test oracle.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
# The base image exports: CC, CXX, LIB_FUZZING_ENGINE, SANITIZER_FLAGS,
# DEBUG_FLAGS, STANDALONE_FUZZ_MAIN, SRC.
#
# Build steps:
#   1) Build libSimd.a WITH $SANITIZER_FLAGS + $DEBUG_FLAGS (so the fuzzed
#      code is instrumented and carries DWARF<4 symbols).
#   2) Compile simd_load_fuzzer + standalone reproducer against the sanitized
#      library.
#   3) Build libSimd.a WITHOUT sanitizers (normal Release build) for the
#      behavioral test oracle that test.sh runs.
#   4) Compile simd_test_oracle against the clean library.
#
# Re-run is idempotent: CMake re-uses cached objects; the library builds from
# source in the image (offline, no network).

set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# ---------------------------------------------------------------------------
# 1) Sanitized build of libSimd.a (for fuzzing).
# ---------------------------------------------------------------------------
# Disable AVX-512/AMX/SVE (optional SIMD tiers) — they add ~250 heavy source
# files and long compile times at little fuzzing benefit; the base/SSE4.1/AVX2
# paths already exercise the image-loading routines.
# Pass SANITIZER_FLAGS + DEBUG_FLAGS via CMAKE_CXX_FLAGS so every object in
# the library carries ASan+UBSan instrumentation and DWARF-3 symbols.
# The CMakeLists.txt strips -march/-mtune/-mavx* from CMAKE_CXX_FLAGS before
# building COMMON_CXX_FLAGS, but leaves -fsanitize* and -g* alone.
cmake -B build-fuzz -S prj/cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
    -DSIMD_TEST=OFF \
    -DSIMD_PYTHON=OFF \
    -DSIMD_AVX512=OFF \
    -DSIMD_AVX512VNNI=OFF \
    -DSIMD_AMXBF16=OFF \
    -DSIMD_SVE=OFF \
    -DSIMD_SVE2=OFF \
    -DSIMD_INSTALL=OFF \
    -DSIMD_UNINSTALL=OFF

cmake --build build-fuzz -j"$MAYHEM_JOBS" --target Simd

# ---------------------------------------------------------------------------
# 2) Compile fuzzer harness + standalone reproducer.
# ---------------------------------------------------------------------------
SIMD_INC="$SRC/src"
SIMD_LIB="$SRC/build-fuzz/libSimd.a"

# libFuzzer harness
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    -std=c++11 -fPIC \
    -I"$SIMD_INC" \
    "$SRC/mayhem/simd_load_fuzzer.cpp" \
    "$SIMD_LIB" \
    -lpthread -lm \
    -o /mayhem/simd_load_fuzzer

# Standalone (non-fuzzer) reproducer: takes an input file, runs once, crashes
# naturally.  Compile the LLVM standalone driver as C (so its
# LLVMFuzzerTestOneInput ref keeps C linkage), then link as C++.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
    -std=c++11 -fPIC \
    -I"$SIMD_INC" \
    /tmp/standalone_main.o \
    "$SRC/mayhem/simd_load_fuzzer.cpp" \
    "$SIMD_LIB" \
    -lpthread -lm \
    -o /mayhem/simd_load_fuzzer-standalone

# ---------------------------------------------------------------------------
# 3) Clean (unsanitized) build of libSimd.a for the test oracle.
# ---------------------------------------------------------------------------
cmake -B build-test -S prj/cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DSIMD_TEST=OFF \
    -DSIMD_PYTHON=OFF \
    -DSIMD_AVX512=OFF \
    -DSIMD_AVX512VNNI=OFF \
    -DSIMD_AMXBF16=OFF \
    -DSIMD_SVE=OFF \
    -DSIMD_SVE2=OFF \
    -DSIMD_INSTALL=OFF \
    -DSIMD_UNINSTALL=OFF

cmake --build build-test -j"$MAYHEM_JOBS" --target Simd

# ---------------------------------------------------------------------------
# 4) Compile the behavioral test oracle (no fuzzer engine, no sanitizers).
# ---------------------------------------------------------------------------
SIMD_LIB_TEST="$SRC/build-test/libSimd.a"

$CXX -O2 \
    -std=c++11 -fPIC \
    -I"$SIMD_INC" \
    "$SRC/mayhem/simd_test_oracle.cpp" \
    "$SIMD_LIB_TEST" \
    -lpthread -lm \
    -o /mayhem/simd_test_oracle
