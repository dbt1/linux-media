#!/bin/bash
# Repo self-check. Runs for every profile, needs no root and no hardware.
# Kernel headers are only required for the optional build check.
#
# Generation happens under out/.check, not in a temp directory: the snapshot
# must be produced inside this git repository, because that is where real
# users generate it and some failure modes only appear there (git apply, for
# one, resolves patch paths against the enclosing repository and silently
# ignores everything outside the current directory). The reference tree the
# snapshot is compared against is built outside the repo on purpose.
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILES="${PROFILES:-$(ls "$BASE_DIR/profiles"/*.mk | xargs -n1 basename | sed 's/\.mk$//')}"
KVER="${KVER:-$(uname -r)}"
KDIR="${KDIR:-/lib/modules/$KVER/build}"

WORK="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "no work directory"; exit 1; }
CHECK_OUT="$BASE_DIR/out/.check"
rm -rf "$CHECK_OUT"
trap 'rm -rf "$WORK" "$CHECK_OUT"' EXIT

fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }

# All sub-makes use the private tree.
mk() { make -C "$BASE_DIR" OUT_BASE="$CHECK_OUT" "$@"; }

# Ask make for the effective value instead of rebuilding the path here;
# otherwise the check can happily verify a tree nobody else uses.
var() { mk print-vars PROFILE="$1" 2>/dev/null | sed -n "s/^$2=//p"; }
pvar() { mk print-profile-vars PROFILE="$1" 2>/dev/null | sed -n "s/^$2=//p"; }

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

# 2. dkms.conf must agree, entry by entry, with the profile it came from.
check_dkms_conf() {
	local profile="$1" src conf i=0 grp mods dir m
	src="$(var "$profile" DKMS_SRC)"
	conf="$src/dkms.conf"
	[ -f "$conf" ] || { bad "$profile: no dkms.conf at $conf"; return; }

	local expected="" got=""
	for grp in USB FE TUNER; do
		mods="$(pvar "$profile" "${grp}_MODULES")"
		dir="$(pvar "$profile" "${grp}_DIR")"
		for m in $mods; do
			expected="$expected$i|${m%.ko}|$dir|/updates/dkms"$'\n'
			i=$((i + 1))
		done
	done
	[ "$i" -gt 0 ] || { bad "$profile: profile declares no modules"; return; }

	# rebuild the same tuples straight out of dkms.conf
	got="$(awk -F'[][]|="|"$' '
		/^BUILT_MODULE_NAME\[/     { n[$2] = $4 }
		/^BUILT_MODULE_LOCATION\[/ { l[$2] = $4 }
		/^DEST_MODULE_LOCATION\[/  { d[$2] = $4 }
		END { for (k = 0; k in n || k in l || k in d; k++)
			printf "%s|%s|%s|%s\n", k, n[k], l[k], d[k] }' "$conf")"

	if [ "$expected" = "$got"$'\n' ]; then
		pass "$profile: dkms.conf entries match the profile ($i modules)"
	else
		bad "$profile: dkms.conf does not match the profile"
		diff <(printf '%s' "$expected") <(printf '%s\n' "$got") | sed 's/^/       /'
	fi

	# dkms rewrites a leading "make"; anything else loses -j and KERNELRELEASE
	grep -q '^MAKE\[0\]="make ' "$conf" \
		&& pass "$profile: MAKE[0] starts with literal make" \
		|| bad "$profile: MAKE[0] must start with 'make'"
}

# 3. The snapshot must be exactly "pinned ref + series", nothing else.
# Built independently here, so a bug in dkms-source cannot hide itself.
check_snapshot_matches_source() {
	local profile="$1" src ref want dirs d p series
	src="$(var "$profile" DKMS_SRC)"
	[ -d "$src" ] || { bad "$profile: no snapshot at $src"; return; }
	ref="$(grep '^linux_media_ref: ' "$src/PROVENANCE" | cut -d' ' -f2)"
	dirs="$(pvar "$profile" USB_DIR) $(pvar "$profile" FE_DIR)"
	dirs="$dirs $(pvar "$profile" TUNER_DIR) drivers/media/common"
	want="$WORK/want-$profile"
	mkdir -p "$want"

	git -C "$BASE_DIR/linux_media" archive --format=tar "$ref" -- $dirs \
		2>/dev/null | tar -x -C "$want" || {
		bad "$profile: cannot archive $ref"; return; }

	series="$BASE_DIR/patches/$profile/series"
	if [ -s "$series" ]; then
		while read -r p || [ -n "$p" ]; do
			[ -n "$p" ] || continue
			patch -p1 -d "$want" --forward --silent \
				--no-backup-if-mismatch < "$BASE_DIR/patches/$profile/$p" \
				|| { bad "$profile: reference patch $p failed"; return; }
		done < "$series"
	fi

	for d in $(echo $dirs | tr ' ' '\n' | sort -u); do
		[ -d "$want/$d" ] || continue
		find "$want/$d" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
		find "$want/$d" -maxdepth 1 -type f \
			! -name '*.c' ! -name '*.h' ! -name 'Makefile' \
			! -name 'Kconfig' -delete
	done

	if diff -r -q "$want/drivers" "$src/drivers" >"$WORK/diff-$profile" 2>&1; then
		pass "$profile: snapshot == pinned ref + patch series"
	else
		bad "$profile: snapshot differs from ref+series"
		head -5 "$WORK/diff-$profile" | sed 's/^/       /'
	fi
}

# 4. The generated tree must build under the command line dkms actually uses,
# and produce exactly the modules dkms.conf promises.
check_dkms_build() {
	local profile="$1" src work expected got m
	src="$(var "$profile" DKMS_SRC)"
	work="$WORK/build-$profile"
	cp -a "$src" "$work" || { bad "$profile: cannot copy snapshot"; return; }
	rm -rf "$work/debian"
	if ! make -C "$work" -j"$(nproc)" KERNELRELEASE="$KVER" \
		KDIR="$KDIR" KVER="$KVER" >"$WORK/build-$profile.log" 2>&1; then
		bad "$profile: build failed"
		tail -12 "$WORK/build-$profile.log" | sed 's/^/       /'
		return
	fi
	# every BUILT_MODULE_NAME must exist at its BUILT_MODULE_LOCATION
	expected="$(awk -F'[][]|="|"$' '
		/^BUILT_MODULE_NAME\[/     { n[$2] = $4 }
		/^BUILT_MODULE_LOCATION\[/ { l[$2] = $4 }
		END { for (k = 0; k in n; k++) printf "%s/%s.ko\n", l[k], n[k] }' \
		"$src/dkms.conf")"
	got=0
	for m in $expected; do
		if [ -f "$work/$m" ]; then
			got=$((got + 1))
		else
			bad "$profile: dkms.conf promises $m, build did not produce it"
		fi
	done
	[ "$got" -gt 0 ] && [ "$got" -eq "$(echo "$expected" | wc -l)" ] \
		&& pass "$profile: builds under dkms invocation ($got/$got modules)"
}

echo "Profiles: $PROFILES"
echo "Generated in: $CHECK_OUT (inside the repo, on purpose)"
echo "Reference in: $WORK (outside the repo)"
echo
echo "Makefile:"
check_default_goal

for p in $PROFILES; do
	echo
	echo "Profile $p:"
	if ! mk dkms-source PROFILE="$p" >"$WORK/gen-$p.log" 2>&1; then
		bad "$p: make dkms-source failed"
		tail -5 "$WORK/gen-$p.log" | sed 's/^/       /'
		continue
	fi
	check_dkms_conf "$p"
	check_snapshot_matches_source "$p"
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
