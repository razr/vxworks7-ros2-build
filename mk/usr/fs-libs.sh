#!/usr/bin/env bash
# fs-libs.sh - the ELF steps of `make fs` (mk/usr/defs.fs.mk) on export/deploy, in
# the order fs runs them. Each step changes the tree and checks its own result.
#
#   fs-libs.sh soname <deploy dir>   one copy per shared library, under its SONAME
#   fs-libs.sh strip  <deploy dir>   strip the debug info (wr-strip --strip-debug)
#   fs-libs.sh needed <deploy dir>   every DT_NEEDED is present in <deploy>/lib
#
# soname: the deploy tree has no symlinks (the package deploys copy with cp -L,
#   FAT stores none), so a library with a version chain is there once per name:
#   libfoo.so, libfoo.so.1, libfoo.so.1.2.3. The VxWorks loader loads a library
#   by the name in DT_NEEDED, normally its SONAME, so only that copy is used. The
#   others are removed when they are the same file (cmp), unless a deployed ELF
#   file names them in DT_NEEDED; a library without a copy under its SONAME is
#   renamed to it. Files without a SONAME (Python extension modules, plugins
#   named as loaded) are left alone.
# strip: the debug info is removed from every ELF file; symbol tables stay (for
#   backtraces). export/root keeps the files as built.
# needed: every DT_NEEDED of every ELF file must exist as a file in <deploy>/lib
#   (LD_LIBRARY_PATH=/usr/lib on the target) or next to the file.
set -euo pipefail

die() { printf 'fs-libs %s FAIL: %s\n' "${STEP:-}" "$*" >&2; exit 1; }
STEP="${1:?usage: fs-libs.sh soname|strip|needed <deploy dir>}"
DEPLOY="${2:?usage: fs-libs.sh $STEP <deploy dir>}"
[ -d "$DEPLOY/lib" ] || die "no $DEPLOY/lib"

is_elf()  { local m=; IFS= read -r -n 4 -d '' m < "$1" 2>/dev/null; [ "$m" = $'\x7fELF' ]; }
soname()  { readelf -d "$1" 2>/dev/null | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p'; }
needed()  { readelf -d "$1" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'; }
elfs()    { find "$DEPLOY" -type f | while read -r f; do is_elf "$f" && echo "$f"; done; }
mb()      { awk -v b="$1" 'BEGIN { printf "%.0f MB", b / 1048576 }'; }

soname_step() {
  local f so dir n removed=0 renamed=0 kept=0 bytes=0
  local -A wanted=()
  [ -z "$(find "$DEPLOY" -type l -print -quit)" ] || die "symlinks in $DEPLOY (expected none)"
  # the names some deployed ELF file loads (DT_NEEDED): a copy under such a name
  # stays, e.g. libsqlite3.so for the SDK python's _sqlite3, linked against the
  # SDK's sqlite, which has no SONAME (pkg/sdk/files/26.03/defs.sdk.mk)
  while read -r f; do
    for n in $(needed "$f"); do wanted[$n]=1; done
  done < <(elfs)
  while read -r f; do
    [ -f "$f" ] || continue                      # removed as a copy already
    so="$(soname "$f")"; [ -n "$so" ] || continue
    [ "$(basename "$f")" != "$so" ] || continue
    [ -z "${wanted[$(basename "$f")]:-}" ] || { kept=$((kept + 1)); continue; }
    dir="$(dirname "$f")"
    if [ -e "$dir/$so" ]; then
      cmp -s "$f" "$dir/$so" || die "$f and $dir/$so differ (both SONAME $so)"
      bytes=$((bytes + $(stat -c%s "$f"))); rm -f "$f"; removed=$((removed + 1))
    else
      mv "$f" "$dir/$so"; renamed=$((renamed + 1))
    fi
  done < <(elfs | sort)
  # check: every shared library is under its SONAME or a name something loads
  while read -r f; do
    so="$(soname "$f")"; [ -n "$so" ] || continue
    [ "$(basename "$f")" = "$so" ] || [ -n "${wanted[$(basename "$f")]:-}" ] \
      || die "$f is not under its SONAME $so"
  done < <(elfs)
  printf '  fs-libs soname: removed %d copies (%s), renamed %d to their SONAME, kept %d (NEEDED by name)\n' \
    "$removed" "$(mb "$bytes")" "$renamed" "$kept"
}

strip_step() {
  local f before=0 after=0 n=0
  command -v wr-strip >/dev/null || die "wr-strip not found (source the SDK)"
  while read -r f; do
    before=$((before + $(stat -c%s "$f")))
    wr-strip --strip-debug "$f" || die "wr-strip --strip-debug $f"
    after=$((after + $(stat -c%s "$f"))); n=$((n + 1))
  done < <(elfs)
  # check: no debug sections left that are not loaded (an allocated one such as
  # Rust's .debug_gdb_scripts is part of the program and stays)
  while read -r f; do
    ! readelf -S -W "$f" 2>/dev/null | sed 's/^ *\[ *[0-9]*\] *//' | \
      awk '$1 ~ /^\.debug_/ && $7 !~ /A/ { found = 1 } END { exit !found }' \
      || die "$f still has .debug_* sections"
  done < <(elfs)
  printf '  fs-libs strip: %d ELF files, %s -> %s\n' "$n" "$(mb "$before")" "$(mb "$after")"
}

needed_step() {
  local f n missing=0 checked=0
  while read -r f; do
    for n in $(needed "$f"); do
      [ -f "$DEPLOY/lib/$n" ] || [ -f "$(dirname "$f")/$n" ] || {
        echo "  missing $n (NEEDED by ${f#"$DEPLOY"/})"; missing=$((missing + 1)); }
    done
    checked=$((checked + 1))
  done < <(elfs)
  [ "$missing" -eq 0 ] || die "$missing NEEDED libraries are not in $DEPLOY/lib"
  printf '  fs-libs needed: %d ELF files, every NEEDED present\n' "$checked"
}

case "$STEP" in
  soname) soname_step ;;
  strip)  strip_step ;;
  needed) needed_step ;;
  *) die "unknown step (want soname|strip|needed)" ;;
esac
