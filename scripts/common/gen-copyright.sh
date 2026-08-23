#!/bin/sh
# Render debian/copyright: expand the @DRIVER_STANZAS@ line of a template into
# one DEP-5 stanza per licence actually found in the packaged driver sources.
#
# This lives outside the Makefile on purpose. It is the part of the packaging
# that makes a legal statement about several hundred files, a recipe line is
# neither readable nor testable, and scripts/common/check.sh drives it here
# directly. Every failure mode below exits non-zero rather than shipping a
# copyright file that quietly says less than it should.
set -eu

# Collation order decides the order of the Files and Copyright entries, and a
# locale-dependent one makes the same source produce a different package on a
# different machine. Byte order, always.
LC_ALL=C
export LC_ALL

usage() {
	echo "usage: $0 <source-tree> <template> <output>" >&2
	exit 2
}

[ $# -eq 3 ] || usage
SRC=$1
TEMPLATE=$2
OUT=$3
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for helper in copyright-holders.awk classify-licence.awk; do
	[ -r "$HERE/$helper" ] || {
		echo "missing helper: $HERE/$helper" >&2
		exit 2
	}
done

[ -d "$SRC/drivers" ] || { echo "no drivers/ below $SRC" >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "no template: $TEMPLATE" >&2; exit 2; }
grep -q '^@DRIVER_STANZAS@$' "$TEMPLATE" || {
	echo "template carries no @DRIVER_STANZAS@ line: $TEMPLATE" >&2
	exit 2
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# The file list. A DEP-5 Files field is whitespace separated and understands
# globs, so a path carrying either would mean something other than itself.
( cd "$SRC" && find drivers -type f | sort ) > "$tmp/files"
[ -s "$tmp/files" ] || { echo "no files below $SRC/drivers" >&2; exit 2; }
if grep -nE '[][*?[:space:]]' "$tmp/files" >&2; then
	echo "the path(s) above cannot be used in a DEP-5 Files field" >&2
	exit 2
fi

while read -r f; do
	bucket=$(awk -f "$HERE/classify-licence.awk" "$SRC/$f") || exit 2
	[ -n "$bucket" ] || {
		echo "classifier said nothing about $f" >&2
		exit 2
	}
	printf '%s\t%s\n' "$bucket" "$f"
done < "$tmp/files" > "$tmp/map"

if grep -q '^unknown:' "$tmp/map"; then
	echo "unrecognised SPDX identifier, refusing to guess a licence:" >&2
	awk -F'\t' '$1 ~ /^unknown:/ { print "  " $2 ": " substr($1, 9) }' \
		"$tmp/map" >&2
	exit 2
fi

: > "$tmp/stanzas"
first=1
for bucket in $(cut -f1 "$tmp/map" | sort -u); do
	evidence=${bucket%%:*}
	licence=${bucket#*:}
	awk -F'\t' -v b="$bucket" '$1 == b { print $2 }' "$tmp/map" \
		> "$tmp/group"
	# Deliberately not a pipeline into sort: a pipeline's status is the
	# last command's, so a failing extractor would be swallowed and every
	# stanza would quietly claim its files carry no copyright notice.
	( cd "$SRC" && while read -r f; do
		awk -f "$HERE/copyright-holders.awk" "$f" || exit 2
	  done < "$tmp/group" ) > "$tmp/raw" || {
		echo "copyright extraction failed in bucket $bucket" >&2
		exit 2
	}
	sort -u "$tmp/raw" > "$tmp/holders"
	{
		[ "$first" -eq 1 ] || echo ""
		printf 'Files:'
		sed 's|^|       |' "$tmp/group"
		if [ -s "$tmp/holders" ]; then
			printf 'Copyright:\n'
			sed 's|^| |' "$tmp/holders"
		else
			echo "Copyright: no copyright notice in these files"
		fi
		echo "License: $licence"
		case "$evidence" in
		text)
			echo "Comment: These files carry no SPDX identifier."
			echo " Their licence text offers version 2 or, at the"
			echo " user's option, any later version."
			;;
		assumed)
			echo "Comment: No SPDX identifier was recognised in"
			echo " these files, and their licence text, where they"
			echo " carry one, does not offer a later version."
			echo " GPL-2.0-only is the narrower reading and the one"
			echo " taken here. Some of them are tagged"
			echo " MODULE_LICENSE(\"GPL\"), which"
			echo " include/linux/module.h defines as version 2 or"
			echo " later; where a file's own header says version 2,"
			echo " the header governs."
			;;
		esac
	} >> "$tmp/stanzas"
	first=0
done

[ -s "$tmp/stanzas" ] || { echo "no stanzas generated" >&2; exit 2; }
grep -q '^Copyright:$' "$tmp/stanzas" || {
	echo "not one stanza named a copyright holder" >&2
	exit 2
}

# awk's getline returns 0 on an empty file and -1 on a read error, and both
# would leave the placeholder line replaced by nothing at all.
awk -v s="$tmp/stanzas" '
	/^@DRIVER_STANZAS@$/ {
		while ((rc = (getline line < s)) > 0)
			print line
		if (rc < 0) {
			print "cannot read " s > "/dev/stderr"
			exit 1
		}
		close(s)
		next
	}
	1' "$TEMPLATE" > "$tmp/out"

if grep -q '@DRIVER_STANZAS@' "$tmp/out"; then
	echo "placeholder survived the substitution" >&2
	exit 2
fi

# Every packaged file has to be covered exactly once. Coverage is what the
# whole stanza machinery exists for, so it is asserted, not assumed.
awk '{
		if ($0 ~ /^Files:/) {
			infiles = 1
			line = $0
			sub(/^Files:[ \t]*/, "", line)
		} else if (infiles && $0 ~ /^[ \t]/) {
			line = $0
		} else {
			infiles = 0
			next
		}
		n = split(line, a, /[ \t]+/)
		for (i = 1; i <= n; i++)
			if (a[i] ~ /^drivers\//)
				print a[i]
	}' "$tmp/out" | sort > "$tmp/covered"
if ! cmp -s "$tmp/files" "$tmp/covered"; then
	echo "Files fields do not cover the packaged tree exactly once:" >&2
	diff "$tmp/files" "$tmp/covered" | head -20 >&2
	exit 2
fi

# A short form in a Files stanza needs a standalone paragraph to resolve to.
awk '/^License: / { print $2 }' "$tmp/out" | sort -u > "$tmp/used"
awk '/^License: / {
		lic = $2
		if ((getline nxt) > 0 && nxt ~ /^[ \t]/)
			print lic
	}' "$tmp/out" | sort -u > "$tmp/standalone"
missing=$(comm -23 "$tmp/used" "$tmp/standalone")
if [ -n "$missing" ]; then
	echo "License short form without a standalone paragraph:" >&2
	printf '  %s\n' $missing >&2
	exit 2
fi

cp "$tmp/out" "$OUT"
