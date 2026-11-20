#!/usr/bin/env bash
# mayhem/build.sh — Apache Cloudberry: sanitized frontend libraries (libpq, pgtypeslib,
# libpgcommon, libpgport) + libFuzzer harnesses, and a normal-flags build of libpq's own
# URI regression program for mayhem/test.sh. Out-of-tree builds under mayhem/build-*/
# (gitignored by mayhem/.gitignore), so `git clean -ffdX` removes them.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
# Frontend-only configure: the backend, ORCA (C++/xerces), gpfdist, PAX and gpcloud are not
# needed by these targets.
CONF_OPTS=(--disable-orca --disable-gpfdist --disable-pax --disable-gpcloud --without-icu
           --without-python --without-readline --without-libbz2 --without-zstd --without-libcurl
           --without-rt --without-libxml --without-openssl --without-gssapi --without-ldap
           --disable-rpath)
# Pieces built in each tree: generated headers come with src/common's submake.
build_tree() { # <dir> <cflags>
  local dir="$1" cflags="$2"
  mkdir -p "$dir"
  if [ ! -f "$dir/config.status" ]; then
    (cd "$dir" && "$SRC/configure" "${CONF_OPTS[@]}" CC="$CC" CXX="$CXX" CFLAGS="$cflags" \
       CXXFLAGS="$cflags" LDFLAGS="$cflags")
  fi
  make -C "$dir/src/backend" -j"$MAYHEM_JOBS" generated-headers
  for d in src/port src/common src/interfaces/libpq; do
    make -C "$dir/$d" -j"$MAYHEM_JOBS"
  done
  # Upstream's pgtypeslib/numeric.c calls zero_numeric_var() (the backend's renamed helper),
  # but its own static helper is still zero_var(): an implicit declaration clang rejects.
  # Map the name back at compile time instead of editing upstream source.
  make -C "$dir/src/interfaces/ecpg/pgtypeslib" -j"$MAYHEM_JOBS" COPT=-Dzero_numeric_var=zero_var
}

# 1) Sanitized + DWARF-3 project build (the fuzzed code is instrumented). -O1 keeps it fast;
#    the base CFLAGS' -Werror is dropped by passing CFLAGS explicitly.
FZ="$SRC/mayhem/build-fuzz"
build_tree "$FZ" "-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"

INC=(-I"$FZ/src/include" -I"$SRC/src/include" -I"$SRC/src/interfaces/libpq"
     -I"$SRC/src/interfaces/ecpg/include" -I"$FZ/src/interfaces/ecpg/include")
COMMON_LIBS=("$FZ/src/common/libpgcommon.a" "$FZ/src/port/libpgport.a" -lz -lm -lpthread)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FZ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FZ/standalone_main.o"

link_harness() { # <name> <libs...>
  local name="$1"; shift
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "${INC[@]}" -c "$SRC/mayhem/harnesses/$name.c" -o "$FZ/$name.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FZ/$name.o" "$FZ/lsan_off.o" "$@" -o "$SRC/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$FZ/standalone_main.o" "$FZ/$name.o" "$FZ/lsan_off.o" "$@" -o "$SRC/$name-standalone"
}
link_harness fuzz_conninfo "$FZ/src/interfaces/libpq/libpq.a" "$FZ/src/common/libpgcommon_shlib.a" "$FZ/src/port/libpgport_shlib.a" -lz -lm -lpthread
link_harness fuzz_pgtypes "$FZ/src/interfaces/ecpg/pgtypeslib/libpgtypes.a" "$FZ/src/common/libpgcommon_shlib.a" "$FZ/src/port/libpgport_shlib.a" -lm
link_harness fuzz_libpq_protocol "$FZ/src/interfaces/libpq/libpq.a" "$FZ/src/common/libpgcommon_shlib.a" "$FZ/src/port/libpgport_shlib.a" -lz -lm -lpthread
link_harness fuzz_json "${COMMON_LIBS[@]}"
link_harness fuzz_common_decoders "${COMMON_LIBS[@]}"

# 2) Test build with NORMAL flags: libpq + upstream's libpq_uri_regress program.
TS="$SRC/mayhem/build-test"
build_tree "$TS" "-O2 $COVERAGE_FLAGS"
make -C "$TS/src/interfaces/libpq/test" -j"$MAYHEM_JOBS" libpq_uri_regress

# 3) AFL++-instrumented file-input targets (Mayhemfile `afl: true`) for CLI tools that exit() on
#    malformed input: pgbench (-f script parser), pg_verifybackup (backup_manifest parser) and
#    pg_restore (custom/tar/directory dump archive reader). (ecpg's preprocessor is not buildable upstream: check_rules.pl
#    rejects Cloudberry's gram.y, so preproc.y is never generated.) Same sanitizers + DWARF-3; each binary is its own reproducer.
AF="$SRC/mayhem/build-afl"
CC=afl-clang-fast CXX=afl-clang-fast++ build_tree "$AF" "-O1 $SANITIZER_FLAGS $DEBUG_FLAGS"
afl-clang-fast++ $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$AF/lsan_off.o"
make -C "$AF/src/fe_utils" -j"$MAYHEM_JOBS"
# Link libpq statically (Mayhem runs the binary without LD_LIBRARY_PATH); relink every run so the
# override always applies.
rm -f "$AF/src/bin/pgbench/pgbench" "$AF/src/bin/pg_verifybackup/pg_verifybackup" "$AF/src/bin/pg_dump/pg_restore"
for d in src/bin/pgbench src/bin/pg_verifybackup; do
  make -C "$AF/$d" -j"$MAYHEM_JOBS" libpq="$AF/src/interfaces/libpq/libpq.a $AF/src/common/libpgcommon_shlib.a $AF/src/port/libpgport_shlib.a -lpthread" \
    LIBS="-lz -lm $AF/lsan_off.o -lstdc++"
done
# Only the pg_restore program: pg_dump.c itself trips -Werror under clang and is not a target.
make -C "$AF/src/bin/pg_dump" -j"$MAYHEM_JOBS" pg_restore \
  libpq="$AF/src/interfaces/libpq/libpq.a $AF/src/common/libpgcommon_shlib.a $AF/src/port/libpgport_shlib.a -lpthread" \
  LIBS="-lz -lm $AF/lsan_off.o -lstdc++"
cp "$AF/src/bin/pgbench/pgbench" "$SRC/afl_pgbench"
cp "$AF/src/bin/pg_verifybackup/pg_verifybackup" "$SRC/afl_pg_verifybackup"
cp "$AF/src/bin/pg_dump/pg_restore" "$SRC/afl_pg_restore"
