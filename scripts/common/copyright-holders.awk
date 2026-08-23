# Extract the copyright notices from a kernel source file header.
#
# One output line per notice. A notice starts at a line whose text, after the
# comment decoration is removed, begins with the word "Copyright". Anchoring at
# the start of the line is what keeps warranty disclaimers and cross references
# out of a DEP-5 Copyright field -- "THIS PROGRAM IS PROVIDED ... THE COPYRIGHT
# HOLDER" and "see dvb-usb-init.c for copyright information" carry the word in
# the middle of a sentence, never at the front. A year is not required: several
# files state only "Copyright (C) ST Microelectronics".
#
# Continuation lines are folded into the notice they belong to, so
#
#     Copyright (C) 2010 Patrick Boettcher,
#                        Kernel Labs Inc. PO Box 745, St James, NY 11780
#
# yields one entry naming both holders instead of dropping the second one. A
# line continues the notice while it is indented further than the "Copyright"
# text itself, is not empty, does not read like licence boilerplate, and does
# not open a new statement with a date ("April 2015" starts a changelog, not a
# holder).
#
# Only the first 60 lines are scanned, which is where kernel headers put their
# notices. mxl5005s.c also repeats notices around line 327 and 3837; those name
# holders that already appear in its header, so nothing is lost today, but the
# bound is a bound and not a proof.
#
# Credits that are not copyright statements stay out on purpose: "based on
# nxt2002 by Taylor Jacob", "Updated 2012 by Jannis Achstetter" and
# "Timothy Lee <...> (for initial work on LGS8GL5)" name contributors, not
# holders, and a DEP-5 Copyright field must not claim otherwise.

function indent(s,   i, c, col) {
	col = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == " ")
			col++
		else if (c == "\t")
			col = col + 8 - (col % 8)
		else
			break
	}
	return col
}

function flush() {
	if (cur != "") {
		gsub(/[ \t]+/, " ", cur)
		sub(/^ +/, "", cur)
		sub(/ +$/, "", cur)
		if (cur != "")
			print cur
	}
	cur = ""
}

BEGIN {
	# Indentation alone does not make a line a holder. Kernel headers put
	# function lists, porting credits and change notes right below the
	# copyright, indented the same way.
	boiler = "(free software|redistribute|WARRANT|GNU |Licen[sc]e|SPDX|" \
		 "This program|This file|This driver|under the terms|" \
		 "PARTICULAR PURPOSE|AS IS|^[-*(]|^Functions:|[Bb]ased on|" \
		 "Support for|^Removed|^Added|^Updated|^Modified|^Ported)"
	newstmt = "^([0-9][0-9][0-9][0-9]|Jan(uary)?|Feb(ruary)?|Mar(ch)?|" \
		  "Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|Sep(tember)?|" \
		  "Oct(ober)?|Nov(ember)?|Dec(ember)?)[-/ \t,.]"
	cur = ""
	curind = 0
}

NR > 60 { exit }

{
	text = $0
	# Drop the comment decoration but keep the indentation behind it.
	if (match(text, /^[ \t]*(\/\*+|\*+\/|\*+|\/\/+|#+)/)) {
		text = substr(text, RLENGTH + 1)
		sub(/^[ \t]/, "", text)
	}
	sub(/[ \t]*\*+\/[ \t]*$/, "", text)
	sub(/[ \t]+$/, "", text)

	ind = indent(text)
	body = text
	sub(/^[ \t]+/, "", body)

	if (body ~ /^[Cc]opyright([ \t(]|$)/ && body !~ boiler) {
		sub(/^[Cc]opyright[ \t]*/, "", body)
		sub(/^(\([Cc]\)|©)[ \t]*/, "", body)
		if (body != "") {
			flush()
			cur = body
			curind = ind
			next
		}
	}

	if (cur != "") {
		if (body == "" || ind <= curind || body ~ boiler || \
		    body ~ newstmt)
			flush()
		else
			cur = cur " " body
	}
}

END { flush() }
