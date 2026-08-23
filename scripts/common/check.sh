#!/bin/bash
# Repo self-check. Runs for every profile and needs no root and no hardware.
# Kernel headers are only required for the optional build check.
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILES="${PROFILES:-$(ls "$BASE_DIR/profiles"/*.mk | xargs -n1 basename | sed 's/\.mk$//')}"
KVER="${KVER:-$(uname -r)}"
KDIR="${KDIR:-/lib/modules/$KVER/build}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }

mk() { make -C "$BASE_DIR" "$@"; }

# 1. A bare `make` must print help, not start building.
check_default_goal() {
	local goal
	goal="$(mk -np 2>/dev/null | sed -n 's/^\.DEFAULT_GOAL := //p' | tail -1)"
	if [ "$goal" = "help" ]; then
		pass "default goal is help"
	else
		bad "default goal is '$goal', expected 'help'"
	fi
}

# 2. dkms.conf must agree with the profile it was generated from.
check_dkms_conf() {
	local profile="$1" src conf n i name loc
	src="$(mk print-vars PROFILE="$profile" 2>/dev/null | sed -n 's/^OUT_BASE=//p')"
	src="$src/dkms/linux-media-$profile-$(cat "$BASE_DIR/VERSION")"
	conf="$src/dkms.conf"
	[ -f "$conf" ] || { bad "$profile: no dkms.conf at $conf"; return; }

	# expected: one entry per module, in USB, FE, TUNER order
	local expect_names="" expect_locs=""
	for grp in USB FE TUNER; do
		local mods dir
		mods="$(mk print-profile-vars PROFILE="$profile" 2>/dev/null | sed -n "s/^${grp}_MODULES=//p")"
		dir="$(mk print-profile-vars PROFILE="$profile" 2>/dev/null | sed -n "s/^${grp}_DIR=//p")"
		for m in $mods; do
			expect_names="$expect_names ${m%.ko}"
			expect_locs="$expect_locs $dir"
		done
	done

	local got_names got_locs
	got_names="$(sed -n 's/^BUILT_MODULE_NAME\[[0-9]*\]="\(.*\)"$/\1/p' "$conf" | tr '\n' ' ')"
	got_locs="$(sed -n 's/^BUILT_MODULE_LOCATION\[[0-9]*\]="\(.*\)"$/\1/p' "$conf" | tr '\n' ' ')"

	if [ "$(echo $expect_names)" = "$(echo $got_names)" ]; then
		pass "$profile: BUILT_MODULE_NAME matches profile"
	else
		bad "$profile: BUILT_MODULE_NAME '$got_names' != '$expect_names'"
	fi
	if [ "$(echo $expect_locs)" = "$(echo $got_locs)" ]; then
		pass "$profile: BUILT_MODULE_LOCATION matches profile"
	else
		bad "$profile: BUILT_MODULE_LOCATION '$got_locs' != '$expect_locs'"
	fi

	# every declared module must have an index, and indices must be dense
	n="$(grep -c '^BUILT_MODULE_NAME\[' "$conf")"
	i=0
	while [ "$i" -lt "$n" ]; do
		grep -q "^BUILT_MODULE_NAME\[$i\]=" "$conf" || bad "$profile: missing index $i"
		grep -q "^DEST_MODULE_LOCATION\[$i\]=\"/updates/dkms\"" "$conf" \
			|| bad "$profile: index $i has no /updates/dkms destination"
		i=$((i + 1))
	done
	[ "$n" -gt 0 ] || bad "$profile: dkms.conf declares no modules"

	# MAKE[0] must start with the literal "make": dkms rewrites that prefix
	grep -q '^MAKE\[0\]="make ' "$conf" \
		&& pass "$profile: MAKE[0] starts with literal make" \
		|| bad "$profile: MAKE[0] must start with 'make' for dkms to inject -j/KERNELRELEASE"
}

# 3. The snapshot must not contain build artifacts or subdirectories.
check_snapshot_clean() {
	local profile="$1" src stray
	src="$(mk print-vars PROFILE="$profile" 2>/dev/null | sed -n 's/^OUT_BASE=//p')"
	src="$src/dkms/linux-media-$profile-$(cat "$BASE_DIR/VERSION")"
	[ -d "$src" ] || { bad "$profile: no snapshot at $src"; return; }

	stray="$(find "$src/drivers" -name '*.mod.c' -o -name '*.o' -o -name '*.ko' 2>/dev/null | wc -l)"
	[ "$stray" -eq 0 ] && pass "$profile: snapshot free of build artifacts" \
		|| bad "$profile: snapshot contains $stray build artifacts"

	local dirs d
	dirs="$(mk print-profile-vars PROFILE="$profile" 2>/dev/null \
		| sed -n 's/^\(USB\|FE\|TUNER\)_DIR=//p' | sort -u)"
	stray=0
	for d in $dirs drivers/media/common; do
		[ -d "$src/$d" ] || continue
		stray=$((stray + $(find "$src/$d" -mindepth 1 -type d 2>/dev/null | wc -l)))
	done
	[ "$stray" -eq 0 ] && pass "$profile: no subdirectories inside driver dirs" \
		|| bad "$profile: $stray unexpected subdirectories inside driver dirs"
}

# 3b. Every patch of the series must actually be present in the snapshot.
# git apply silently ignores paths when run inside another repository and
# still exits 0, so "the command succeeded" is not evidence here.
check_patches_applied() {
	local profile="$1" src series pdir p
	src="$(mk print-vars PROFILE="$profile" 2>/dev/null | sed -n 's/^OUT_BASE=//p')"
	src="$src/dkms/linux-media-$profile-$(cat "$BASE_DIR/VERSION")"
	series="$BASE_DIR/patches/$profile/series"
	pdir="$BASE_DIR/patches/$profile"
	if [ ! -s "$series" ]; then
		pass "$profile: no patch series to verify"
		return
	fi
	while read -r p || [ -n "$p" ]; do
		[ -n "$p" ] || continue
		# reverse-apply must succeed if and only if the patch is in place
		if patch -p1 -d "$src" --dry-run --reverse --silent \
			< "$pdir/$p" >/dev/null 2>&1; then
			pass "$profile: $p present in snapshot"
		else
			bad "$profile: $p NOT applied in snapshot"
		fi
	done < "$series"
}

# 4. The generated tree must build under the command line dkms actually uses.
check_dkms_build() {
	local profile="$1" src work
	src="$(mk print-vars PROFILE="$profile" 2>/dev/null | sed -n 's/^OUT_BASE=//p')"
	src="$src/dkms/linux-media-$profile-$(cat "$BASE_DIR/VERSION")"
	work="$WORK/build-$profile"
	cp -a "$src" "$work"
	rm -rf "$work/debian"
	# exactly how dkms invokes it, see /usr/sbin/dkms (MAKE[0] rewrite)
	if make -C "$work" -j"$(nproc)" KERNELRELEASE="$KVER" \
		KDIR="$KDIR" KVER="$KVER" >"$WORK/build-$profile.log" 2>&1; then
		local n
		n="$(find "$work" -name '*.ko' | wc -l)"
		pass "$profile: builds under dkms invocation ($n modules)"
	else
		bad "$profile: build failed, see $WORK/build-$profile.log"
		tail -15 "$WORK/build-$profile.log"
	fi
}

echo "Profiles: $PROFILES"
echo
echo "Makefile:"
check_default_goal

for p in $PROFILES; do
	echo
	echo "Profile $p:"
	if ! mk dkms-source PROFILE="$p" >/dev/null 2>&1; then
		bad "$p: make dkms-source failed"
		mk dkms-source PROFILE="$p" 2>&1 | tail -5
		continue
	fi
	check_dkms_conf "$p"
	check_snapshot_clean "$p"
	check_patches_applied "$p"
	if [ -d "$KDIR" ]; then
		check_dkms_build "$p"
	else
		echo "  skip $p: no kernel headers at $KDIR"
	fi
done

echo
if [ "$fail" -eq 0 ]; then
	echo "All checks passed."
else
	echo "Checks FAILED."
fi
exit "$fail"
