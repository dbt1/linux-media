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
skipped=""
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
skip() { printf '  skip %s\n' "$*"; skipped="$skipped
  $*"; }

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

	# Identity and autoinstall decide whether dkms picks the module up at
	# all on the next kernel; none of the three was ever compared.
	conf_field "$profile" "$conf" PACKAGE_NAME "$(var "$profile" DKMS_PACKAGE)"
	conf_field "$profile" "$conf" PACKAGE_VERSION "$(var "$profile" DKMS_VERSION)"
	conf_field "$profile" "$conf" AUTOINSTALL yes
}

conf_field() {
	local profile="$1" conf="$2" key="$3" want="$4" got
	got="$(sed -n "s/^$key=\"\(.*\)\"\$/\1/p" "$conf")"
	if [ "$got" = "$want" ]; then
		pass "$profile: $key=$want"
	else
		bad "$profile: $key is '$got', expected '$want'"
	fi
}

# 3. The snapshot must be exactly "pinned ref + series", nothing else.
# Built independently here, so a bug in dkms-source cannot hide itself.
check_snapshot_matches_source() {
	local profile="$1" src ref want dirs d p series
	src="$(var "$profile" DKMS_SRC)"
	[ -d "$src" ] || { bad "$profile: no snapshot at $src"; return; }
	# The reference comes from the profile, never from the artefact under
	# test: a dkms-source that pinned the wrong ref would also write that
	# wrong ref into PROVENANCE and compare clean against itself.
	ref="$(pvar "$profile" LINUX_MEDIA_REF)"
	[ -n "$ref" ] || { bad "$profile: profile pins no LINUX_MEDIA_REF"; return; }
	local rec_ref rec_sha want_sha
	rec_ref="$(sed -n 's/^linux_media_ref: //p' "$src/PROVENANCE")"
	rec_sha="$(sed -n 's/^linux_media_commit: //p' "$src/PROVENANCE")"
	want_sha="$(git -C "$BASE_DIR/linux_media" rev-parse "$ref^{commit}" \
		2>/dev/null)"
	if [ -n "$want_sha" ] && [ "$rec_ref" = "$ref" ] \
		&& [ "$rec_sha" = "$want_sha" ]; then
		pass "$profile: PROVENANCE records the pinned ref ($ref)"
	else
		bad "$profile: PROVENANCE says $rec_ref/$rec_sha, profile pins $ref/$want_sha"
	fi
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

# 5. debian/copyright is the part of the packaging that makes a legal claim
# about several hundred files. Nothing here needs dpkg: the generator is
# driven directly, which is also why it lives outside the Makefile.
check_copyright() {
	local profile="$1" src tmpl out
	src="$(var "$profile" DKMS_SRC)"
	tmpl="$(var "$profile" DEB_TEMPLATE_DIR)/copyright"
	out="$WORK/copyright-$profile"
	if ! "$BASE_DIR/scripts/common/gen-copyright.sh" "$src" "$tmpl" "$out" \
		2>"$WORK/copyright-$profile.log"; then
		bad "$profile: gen-copyright.sh failed"
		sed 's/^/       /' "$WORK/copyright-$profile.log" | head -8
		return
	fi
	# Coverage and the standalone-paragraph rule are asserted by the
	# generator itself; what it cannot judge is whether the entries read
	# like copyright holders at all.
	awk '{
			if ($0 ~ /^Copyright:/) {
				incopy = 1
				line = $0
				sub(/^Copyright:[ \t]*/, "", line)
			} else if (incopy && $0 ~ /^[ \t]/) {
				line = $0
			} else {
				incopy = 0
				next
			}
			if (line != "")
				print line
		}' "$out" > "$WORK/copyright-$profile.fields"
	if grep -nE '(PROVIDED|DISCLAIM|WARRANT|FITNESS|for copyright|following copyrights|retained the copyright|[Bb]ased on|Functions:|Support for|^Removed|^Ported|^[-*(])' \
		"$WORK/copyright-$profile.fields" \
		>"$WORK/copyright-$profile.junk"; then
		bad "$profile: non-holder text ended up in a Copyright field"
		head -3 "$WORK/copyright-$profile.junk" | sed 's/^/       /'
	else
		pass "$profile: copyright fields name holders only"
	fi
	# A stanza that names nobody is what every silent failure in the
	# extraction chain looks like, so it is an error and not an ok.
	if grep -q '^Copyright: no copyright notice' "$out"; then
		bad "$profile: $(grep -c '^Copyright: no copyright notice' "$out") stanza(s) name no holder at all"
	else
		pass "$profile: every stanza names at least one holder"
	fi
	# Collation order decides the entry order, so a locale-dependent sort
	# makes the same source produce a different package elsewhere. Both
	# runs have to differ in the *ambient* locale, otherwise this proves
	# nothing: the generator pins LC_ALL itself, and comparing two C runs
	# would stay green even if that pin were removed.
	local other
	other="$(locale -a 2>/dev/null \
		| grep -iE '^(de_DE|en_US|fr_FR)\.utf-?8$' | head -1)"
	if [ -z "$other" ]; then
		skip "$profile: locale check, no non-C UTF-8 locale installed"
	elif LC_ALL=C "$BASE_DIR/scripts/common/gen-copyright.sh" "$src" \
			"$tmpl" "$out.c" >/dev/null 2>&1 \
		&& LC_ALL="$other" "$BASE_DIR/scripts/common/gen-copyright.sh" \
			"$src" "$tmpl" "$out.l" >/dev/null 2>&1 \
		&& cmp -s "$out.c" "$out.l"; then
		pass "$profile: copyright identical under C and $other"
	else
		bad "$profile: copyright changes between C and $other"
	fi
	local n
	n="$(grep -c '^Files:' "$out")"
	pass "$profile: copyright renders ($n stanzas, $(wc -l < "$WORK/copyright-$profile.fields") holder lines)"
}

# 6. The generator must refuse what it cannot classify. A licence file that
# quietly guesses is worse than one that fails, so the guard gets its own
# fault injection instead of being taken on trust.
check_copyright_guards() {
	local fake="$WORK/fake-src" tmpl="$WORK/fake-template" out="$WORK/fake-out"
	mkdir -p "$fake/drivers"
	printf '/* SPDX-License-Identifier: Frobnicate-1.0 */\n' \
		> "$fake/drivers/x.c"
	printf 'Format: x\n\n@DRIVER_STANZAS@\n' > "$tmpl"
	if "$BASE_DIR/scripts/common/gen-copyright.sh" "$fake" "$tmpl" "$out" \
		>/dev/null 2>&1; then
		bad "generator accepted an unknown SPDX identifier"
	else
		pass "generator refuses an unknown SPDX identifier"
	fi
	printf 'Format: x\n' > "$tmpl"
	printf '/* SPDX-License-Identifier: GPL-2.0 */\n' > "$fake/drivers/x.c"
	if "$BASE_DIR/scripts/common/gen-copyright.sh" "$fake" "$tmpl" "$out" \
		>/dev/null 2>&1; then
		bad "generator accepted a template without @DRIVER_STANZAS@"
	else
		pass "generator refuses a template without @DRIVER_STANZAS@"
	fi
}

# 7. Every placeholder a template uses has to be filled by the Makefile, and
# every substitution the Makefile performs has to have a taker. Both halves
# silently produce a wrong package otherwise.
check_placeholders() {
	local tmpl_dir used filled
	tmpl_dir="$BASE_DIR/packaging/debian"
	used="$(grep -rhoE '@[A-Z_]+@' "$tmpl_dir" | sort -u)"
	filled="$(sed -n 's/.*s|\(@[A-Z_]*@\)|.*/\1/p' "$BASE_DIR/Makefile" \
		| sort -u)"
	# These two are line replacements, not sed substitutions.
	filled="$(printf '%s\n@DRIVER_STANZAS@\n@FIRMWARE_NOTE@\n' "$filled" \
		| sort -u)"
	local orphan
	orphan="$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$filled"))"
	if [ -n "$orphan" ]; then
		bad "template placeholder nobody fills: $(echo $orphan)"
	else
		pass "every template placeholder is filled"
	fi
	orphan="$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$filled"))"
	if [ -n "$orphan" ]; then
		bad "substitution without a template that uses it: $(echo $orphan)"
	else
		pass "every substitution has a taker"
	fi
}

echo "Profiles: $PROFILES"
echo "Generated in: $CHECK_OUT (inside the repo, on purpose)"
echo "Reference in: $WORK (outside the repo)"
echo
echo "Makefile:"
check_default_goal
check_placeholders

echo
echo "Packaging:"
check_copyright_guards

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
	check_copyright "$p"
	if [ -d "$KDIR" ]; then
		check_dkms_build "$p"
	else
		skip "$p: build check, no kernel headers at $KDIR"
	fi
done

echo
if [ "$fail" -ne 0 ]; then
	echo "RESULT: checks FAILED."
elif [ -n "$skipped" ]; then
	# Naming them matters: a caller that only reads the last line would
	# otherwise take a partial run for full coverage.
	echo "RESULT: passed, but these checks did not run:$skipped"
else
	echo "RESULT: all checks passed."
fi
exit "$fail"
