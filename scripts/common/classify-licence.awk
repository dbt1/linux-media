# Decide under which licence one packaged source file is distributed, and on
# what evidence. Prints a single "<evidence>:<licence>" token.
#
#   spdx:    the file carries a machine-readable identifier
#   text:    no identifier, but the licence text grants "any later version"
#   assumed: no identifier and no later-version grant
#   unknown: an identifier the caller has no mapping for -- never guessed
#
# MODULE_LICENSE is deliberately NOT used to widen a grant. include/linux/
# module.h reads the tag "GPL" as "v2 or later", but several files carrying it
# state "version 2" or "version 2 only" in their own header -- tbs5580.c and
# stv091x.c among them. The header is the licence grant, the tag is a kernel
# bookkeeping string, and where they disagree the narrower reading is the
# only safe one. The stanza comment says so instead of hiding it.
#
# The identifier window is the first three lines, which is where the kernel
# style guide puts it. The typo "SPX-License-Identifier" is matched as well:
# cxd2878.c and m88rs6060.[ch] carry it upstream, and silently filing them
# under "no identifier" would state the opposite of what they say.

NR <= 3 && bucket == "" {
	if (match($0, /SP(DX|X)-License-Identifier:[ \t]*/)) {
		id = substr($0, RSTART + RLENGTH)
		sub(/[ \t]*\*+\/.*$/, "", id)
		sub(/[ \t]+$/, "", id)
		# GPL-2.0 and GPL-2.0+ are the deprecated spellings; SPDX
		# replaced them with the explicit -only / -or-later forms.
		if (id == "GPL-2.0" || id == "GPL-2.0-only")
			bucket = "spdx:GPL-2.0-only"
		else if (id == "GPL-2.0+" || id == "GPL-2.0-or-later")
			bucket = "spdx:GPL-2.0-or-later"
		else if (id == "MIT")
			bucket = "spdx:MIT"
		else
			bucket = "unknown:" id
	}
}

NR == 4 && bucket != "" { exit }

tolower($0) ~ /any later version/ { later = 1 }

END {
	if (bucket != "")
		print bucket
	else if (later)
		print "text:GPL-2.0-or-later"
	else
		print "assumed:GPL-2.0-only"
}
