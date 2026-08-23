SHELL := /bin/sh

BASE := $(CURDIR)
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
LINUX_MEDIA ?= $(BASE)/linux_media
PATCHES_DIR ?= $(BASE)/patches
OUT_BASE ?= $(BASE)/out

PROFILE ?=
ifeq ($(PROFILE),)
ifneq (,$(filter tbs5580,$(MAKECMDGOALS)))
PROFILE := tbs5580
endif
ifneq (,$(filter t230,$(MAKECMDGOALS)))
PROFILE := t230
endif
ifneq (,$(filter t210,$(MAKECMDGOALS)))
PROFILE := t210
endif
endif

PROFILE_FILE := $(BASE)/profiles/$(PROFILE).mk
ifneq ($(PROFILE),)
include $(PROFILE_FILE)
endif

ifneq ($(PROFILE),)
OUT_PROFILE ?= $(OUT_BASE)/$(PROFILE)
else
OUT_PROFILE ?= $(OUT_BASE)
endif
OUT_DIST ?= $(OUT_BASE)/dist
INSTRUCTION_FILE := $(OUT_PROFILE)/INSTALL.txt

# The include below defines targets, so the default goal has to be
# pinned here — otherwise a bare 'make' would build instead of helping.
.DEFAULT_GOAL := help

include $(BASE)/mk/build-modules.mk

OUTPUT_MODULES := $(USB_MODULES) $(FE_MODULES) $(TUNER_MODULES)
INSMOD_FILES ?=
RMMOD_MODULES ?=
MODPROBE_DEPS ?=
FIRMWARE ?=
FIRMWARES ?=
CHECK_MODULES ?= $(RMMOD_MODULES)

.PHONY: help tbs5580 t230 t210 build fetch apply-patches check-profile \
	check-linux-media check-kdir precheck \
	copy-mods artifacts instructions package print-vars \
	check-dkms-version check-dkms-profile check-snapshot dkms-source \
	check-deb-tools dkms-deb check print-profile-vars

help:
	@printf "Usage:\\n"
	@printf "  make tbs5580 [KVER=...] [LINUX_MEDIA=...]\\n"
	@printf "  make t230 [KVER=...] [LINUX_MEDIA=...]\\n"
	@printf "  make t210 [KVER=...] [LINUX_MEDIA=...]\\n"
	@printf "  make build PROFILE=<name> [KVER=...]\\n"
	@printf "  make precheck PROFILE=<name>\\n"
	@printf "  make fetch PROFILE=<name>\\n"
	@printf "  make apply-patches PROFILE=<name>\\n"
	@printf "  make package PROFILE=<name>\\n"
	@printf "  make dkms-source PROFILE=<name>\\n"
	@printf "  make dkms-deb PROFILE=<name>\\n"
	@printf "  make check\\n"

tbs5580: build
t230: build
t210: build

check-profile:
	@if [ -z "$(PROFILE)" ]; then \
		echo "PROFILE is not set (e.g. make tbs5580)"; \
		exit 2; \
	fi
	@if [ ! -f "$(PROFILE_FILE)" ]; then \
		echo "Missing profile: $(PROFILE_FILE)"; \
		exit 2; \
	fi

check-linux-media:
	@if [ ! -d "$(LINUX_MEDIA)" ]; then \
		echo "LINUX_MEDIA not found at $(LINUX_MEDIA)"; \
		echo "Run: make fetch PROFILE=$(PROFILE)"; \
		exit 2; \
	fi

check-kdir:
	@if [ ! -d "$(KDIR)" ]; then \
		echo "Kernel build dir not found: $(KDIR)"; \
		exit 2; \
	fi

fetch: check-profile
	@if [ -z "$(LINUX_MEDIA_URL)" ] || [ -z "$(LINUX_MEDIA_REF)" ]; then \
		echo "Profile must set LINUX_MEDIA_URL and LINUX_MEDIA_REF"; \
		exit 2; \
	fi
	@if [ ! -d "$(LINUX_MEDIA)/.git" ]; then \
		echo "Cloning $(LINUX_MEDIA_URL) to $(LINUX_MEDIA)"; \
		git clone "$(LINUX_MEDIA_URL)" "$(LINUX_MEDIA)"; \
	fi
	@echo "Checking out $(LINUX_MEDIA_REF)"
	@git -C "$(LINUX_MEDIA)" fetch --all --tags --prune
	@git -C "$(LINUX_MEDIA)" checkout "$(LINUX_MEDIA_REF)"

apply-patches: check-profile check-linux-media
	@if [ ! -f "$(PATCH_SERIES)" ]; then \
		echo "No patch series: $(PATCH_SERIES)"; \
		exit 2; \
	fi
	@while read -r p; do \
		[ -z "$$p" ] && continue; \
		patch_path="$(PATCH_DIR)/$$p"; \
		if git -C "$(LINUX_MEDIA)" apply --reverse --check "$$patch_path" >/dev/null 2>&1; then \
			echo "Patch already applied: $$p"; \
			continue; \
		fi; \
		git -C "$(LINUX_MEDIA)" apply --check "$$patch_path"; \
		git -C "$(LINUX_MEDIA)" apply "$$patch_path"; \
		echo "Applied: $$p"; \
	done < "$(PATCH_SERIES)"

build: check-profile check-linux-media check-kdir build-usb build-fe build-tuner \
	copy-mods artifacts instructions

precheck: check-profile
	@set -eu; \
	if [ -z "$(USB_ID)" ]; then \
		echo "USB_ID not set in profile"; \
		exit 2; \
	fi; \
	usb_id="$(USB_ID)"; \
	vid=$${usb_id%%:*}; \
	pid=$${usb_id##*:}; \
	echo "USB_ID: $$vid:$$pid"; \
	if lsusb -d "$$vid:$$pid" >/dev/null 2>&1; then \
		echo "Device present: yes"; \
	else \
		echo "Device present: no"; \
	fi; \
	alias_file="/lib/modules/$(KVER)/modules.alias"; \
	if [ -f "$$alias_file" ]; then \
		echo "In-tree alias matches:"; \
		alias_lines=""; \
		if command -v rg >/dev/null 2>&1; then \
			alias_lines=$$(rg -ni "v$${vid}p$${pid}" "$$alias_file" || true); \
		else \
			alias_lines=$$(grep -ni "v$${vid}p$${pid}" "$$alias_file" || true); \
		fi; \
		if [ -n "$$alias_lines" ]; then \
			printf "%s\\n" "$$alias_lines"; \
			alias_mods=$$(printf "%s\\n" "$$alias_lines" | cut -d: -f2- | \
				awk '{print $$NF}' | sort -u | tr '\\n' ' '); \
			if [ -n "$$alias_mods" ]; then \
				echo "Suggested modprobe (in-tree): $$alias_mods"; \
			fi; \
		else \
			echo "  (none)"; \
		fi; \
	else \
		echo "modules.alias not found: $$alias_file"; \
	fi; \
	found_paths=""; \
	for d in /sys/bus/usb/devices/*; do \
		[ -f "$$d/idVendor" ] || continue; \
		[ -f "$$d/idProduct" ] || continue; \
		if [ "$$(cat $$d/idVendor)" = "$$vid" ] && \
		   [ "$$(cat $$d/idProduct)" = "$$pid" ]; then \
			found_paths="$$found_paths $$d"; \
		fi; \
	done; \
	if [ -z "$$found_paths" ]; then \
		echo "USB sysfs: no matching device path found"; \
	else \
		for d in $$found_paths; do \
			echo "USB sysfs: $$d"; \
			if [ -L "$$d/driver" ]; then \
				echo "Driver bound: $$(basename "$$(readlink "$$d/driver")")"; \
			else \
				echo "Driver bound: (none)"; \
			fi; \
		done; \
	fi; \
	dvb_for_dev=0; \
	for d in $$found_paths; do \
		d_real=$$(readlink -f "$$d"); \
		for dvb in /sys/class/dvb/*/device; do \
			[ -e "$$dvb" ] || continue; \
			dvb_real=$$(readlink -f "$$dvb"); \
			case "$$dvb_real" in \
				$$d_real/*) dvb_for_dev=1 ;; \
			esac; \
		done; \
	done; \
	if [ "$$dvb_for_dev" -eq 1 ]; then \
		echo "Result: DVB nodes found for this device (build likely not needed)."; \
	else \
		echo "Result: no DVB nodes for this device (build may be required)."; \
	fi; \
	echo "Blacklist checks:"; \
	mods="$(CHECK_MODULES)"; \
	if [ -z "$$mods" ]; then \
		echo "  (no module list)"; \
	else \
		cmdline=$$(cat /proc/cmdline); \
		bl_line=$$(printf "%s" "$$cmdline" | tr ' ' '\n' | \
			grep -E '^(module_blacklist|modprobe.blacklist)=' || true); \
		if [ -n "$$bl_line" ]; then \
			bl_vals=$$(printf "%s\n" "$$bl_line" | \
				sed -E 's/^[^=]+=//; s/,/ /g'); \
			hit=""; \
			for m in $$mods; do \
				for b in $$bl_vals; do \
					if [ "$$m" = "$$b" ]; then \
						hit="$$hit $$m"; \
					fi; \
				done; \
			done; \
			if [ -n "$$hit" ]; then \
				echo "  kernel cmdline blacklisted:$$hit"; \
			else \
				echo "  kernel cmdline blacklisted: (none)"; \
			fi; \
		else \
			echo "  kernel cmdline blacklisted: (none)"; \
		fi; \
		conf_dirs="/etc/modprobe.d /usr/lib/modprobe.d /lib/modprobe.d /run/modprobe.d"; \
		any_hit=0; \
		for d in $$conf_dirs; do \
			[ -d "$$d" ] || continue; \
			for m in $$mods; do \
				if command -v rg >/dev/null 2>&1; then \
					if rg -n "^[[:space:]]*(blacklist[[:space:]]+$$m|install[[:space:]]+$$m[[:space:]]+/bin/(false|true))" "$$d" >/dev/null 2>&1; then \
						echo "  $$m: matches in $$d"; \
						rg -n "^[[:space:]]*(blacklist[[:space:]]+$$m|install[[:space:]]+$$m[[:space:]]+/bin/(false|true))" "$$d"; \
						any_hit=1; \
					fi; \
				else \
					if grep -En "^[[:space:]]*(blacklist[[:space:]]+$$m|install[[:space:]]+$$m[[:space:]]+/bin/(false|true))" "$$d" >/dev/null 2>&1; then \
						echo "  $$m: matches in $$d"; \
						grep -En "^[[:space:]]*(blacklist[[:space:]]+$$m|install[[:space:]]+$$m[[:space:]]+/bin/(false|true))" "$$d"; \
						any_hit=1; \
					fi; \
				fi; \
			done; \
		done; \
		if [ "$$any_hit" -eq 0 ]; then \
			echo "  modprobe.d blacklists: (none)"; \
		fi; \
	fi

copy-mods:
	@mkdir -p "$(OUT_PROFILE)"
	@for m in $(USB_MODULES); do \
		cp -f "$(LINUX_MEDIA)/$(USB_DIR)/$$m" "$(OUT_PROFILE)/$$m"; \
	done
	@for m in $(FE_MODULES); do \
		cp -f "$(LINUX_MEDIA)/$(FE_DIR)/$$m" "$(OUT_PROFILE)/$$m"; \
	done
	@for m in $(TUNER_MODULES); do \
		cp -f "$(LINUX_MEDIA)/$(TUNER_DIR)/$$m" "$(OUT_PROFILE)/$$m"; \
	done

artifacts:
	@if [ -n "$(OUTPUT_MODULES)" ]; then \
		: > "$(OUT_PROFILE)/artifacts.txt"; \
		for m in $(OUTPUT_MODULES); do \
			echo "== $$m ==" >> "$(OUT_PROFILE)/artifacts.txt"; \
			modinfo "$(OUT_PROFILE)/$$m" >> "$(OUT_PROFILE)/artifacts.txt"; \
			echo "" >> "$(OUT_PROFILE)/artifacts.txt"; \
		done; \
	fi

instructions:
	@mkdir -p "$(OUT_PROFILE)"
	@printf "Profile: %s\n" "$(PROFILE)" > "$(INSTRUCTION_FILE)"
	@printf "Kernel: %s\n" "$(KVER)" >> "$(INSTRUCTION_FILE)"
	@printf "Linux media: %s @ %s\n" "$(LINUX_MEDIA_URL)" "$(LINUX_MEDIA_REF)" \
		>> "$(INSTRUCTION_FILE)"
	@if [ -n "$(FIRMWARES)" ]; then \
		printf "Firmware: (see prerequisites)\n" >> "$(INSTRUCTION_FILE)"; \
	else \
		printf "Firmware: %s\n" "$(FIRMWARE)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "USB ID: %s\n" "$(USB_ID)" >> "$(INSTRUCTION_FILE)"
	@printf "\nPrerequisites:\n" >> "$(INSTRUCTION_FILE)"
	@printf "  - Kernel version must match exactly (vermagic).\n" \
		>> "$(INSTRUCTION_FILE)"
	@if [ -n "$(FIRMWARES)" ]; then \
		echo "  - Firmware must include one of:" >> "$(INSTRUCTION_FILE)"; \
		for f in $(FIRMWARES); do \
			echo "      /lib/firmware/$$f" >> "$(INSTRUCTION_FILE)"; \
		done; \
	elif [ -n "$(FIRMWARE)" ]; then \
		printf "  - Firmware must exist at /lib/firmware/%s.\n" "$(FIRMWARE)" \
			>> "$(INSTRUCTION_FILE)"; \
	else \
		echo "  - Firmware: (not specified)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "  - Secure Boot: unsigned modules must be allowed.\n" \
		>> "$(INSTRUCTION_FILE)"
	@printf "\nDevice check:\n" >> "$(INSTRUCTION_FILE)"
	@if [ -n "$(USB_ID)" ]; then \
		echo "  lsusb -d $(USB_ID)" >> "$(INSTRUCTION_FILE)"; \
	else \
		echo "  (USB_ID not set)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "\nLoad (modprobe deps):\n" >> "$(INSTRUCTION_FILE)"
	@if [ -n "$(MODPROBE_DEPS)" ]; then \
		for m in $(MODPROBE_DEPS); do \
			echo "  sudo modprobe $$m" >> "$(INSTRUCTION_FILE)"; \
		done; \
	else \
		echo "  (none)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "\nLoad (insmod, from this directory):\n" \
		>> "$(INSTRUCTION_FILE)"
	@if [ -n "$(INSMOD_FILES)" ]; then \
		for m in $(INSMOD_FILES); do \
			echo "  sudo insmod ./$$m" >> "$(INSTRUCTION_FILE)"; \
		done; \
	else \
		echo "  (none)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "\nVerify:\n" >> "$(INSTRUCTION_FILE)"
	@printf "  ls -l /dev/dvb\n" >> "$(INSTRUCTION_FILE)"
	@printf "  ls -l /dev/dvb/adapter*/ || true\n" >> "$(INSTRUCTION_FILE)"
	@printf "  dmesg | tail -n 200 | egrep -i 'tbs|dvb|usb|firmware|frontend|ci|ca'\n" \
		>> "$(INSTRUCTION_FILE)"
	@printf "\nUnload:\n" >> "$(INSTRUCTION_FILE)"
	@if [ -n "$(RMMOD_MODULES)" ]; then \
		echo "  sudo rmmod $(RMMOD_MODULES)" >> "$(INSTRUCTION_FILE)"; \
	else \
		echo "  (none)" >> "$(INSTRUCTION_FILE)"; \
	fi
	@printf "\nNote:\n" >> "$(INSTRUCTION_FILE)"
	@printf "  Modules are not installed and are only for this boot.\n" \
		>> "$(INSTRUCTION_FILE)"
	@printf "  This is the fallback route for hosts without DKMS. Prefer\n" \
		>> "$(INSTRUCTION_FILE)"
	@printf "  'make dkms-source' + dkms, which survives kernel updates.\n" \
		>> "$(INSTRUCTION_FILE)"

package: build
	@mkdir -p "$(OUT_DIST)"
	@tar -C "$(OUT_PROFILE)" -cJf "$(OUT_DIST)/$(PROFILE)-k$(KVER).tar.xz" \
		$(OUTPUT_MODULES) artifacts.txt INSTALL.txt
	@echo "Wrote $(OUT_DIST)/$(PROFILE)-k$(KVER).tar.xz"

# Without a profile the module lists are empty and clean would silently do
# nothing; that used to look like success.
clean: check-profile

print-profile-vars: check-profile
	@echo "USB_DIR=$(USB_DIR)"
	@echo "FE_DIR=$(FE_DIR)"
	@echo "TUNER_DIR=$(TUNER_DIR)"
	@echo "USB_MODULES=$(USB_MODULES)"
	@echo "FE_MODULES=$(FE_MODULES)"
	@echo "TUNER_MODULES=$(TUNER_MODULES)"

check:
	@$(BASE)/scripts/common/check.sh

print-vars:
	@echo "PROFILE=$(PROFILE)"
	@echo "DKMS_SRC=$(DKMS_SRC)"
	@echo "KVER=$(KVER)"
	@echo "KDIR=$(KDIR)"
	@echo "LINUX_MEDIA=$(LINUX_MEDIA)"
	@echo "OUT_BASE=$(OUT_BASE)"
	@echo "OUT_PROFILE=$(OUT_PROFILE)"
	@echo "OUT_DIST=$(OUT_DIST)"

# --- DKMS -------------------------------------------------------------------

DKMS_PACKAGE ?= linux-media-$(PROFILE)
DKMS_DEB_PACKAGE ?= $(DKMS_PACKAGE)-dkms
VERSION_FILE := $(BASE)/VERSION
DKMS_VERSION ?= $(shell cat $(VERSION_FILE) 2>/dev/null)
DKMS_OUT ?= $(OUT_BASE)/dkms
DKMS_SRC ?= $(DKMS_OUT)/$(DKMS_PACKAGE)-$(DKMS_VERSION)
DKMS_DIRS := $(sort $(USB_DIR) $(FE_DIR) $(TUNER_DIR) drivers/media/common)

DEB_TEMPLATE_DIR := $(BASE)/packaging/debian
DEB_HOST_ID ?= $(shell hostname)
DEB_MAINTAINER ?= linux-media packaging <linux-media@$(DEB_HOST_ID)>
DKMS_MODULE_NAMES := $(basename $(OUTPUT_MODULES))

check-dkms-version:
	@set -eu; \
	if [ -z "$(DKMS_VERSION)" ]; then \
		echo "Missing or empty version file: $(VERSION_FILE)"; \
		exit 2; \
	fi; \
	for v in '$(DKMS_PACKAGE)' '$(DKMS_VERSION)'; do \
		case "$$v" in \
			*/*|*..*|'') \
				echo "Refusing unsafe package/version component: $$v"; \
				exit 2 ;; \
		esac; \
	done; \
	out=$$(realpath -m -- "$(DKMS_OUT)"); \
	src=$$(realpath -m -- "$(DKMS_SRC)"); \
	case "$$src" in \
		"$$out"/?*) ;; \
		*) \
			echo "DKMS_SRC must live under DKMS_OUT, refusing to touch it:"; \
			echo "  DKMS_OUT=$$out"; \
			echo "  DKMS_SRC=$$src"; \
			exit 2 ;; \
	esac

check-dkms-profile: check-profile
	@if [ -z "$(strip $(OUTPUT_MODULES))" ]; then \
		echo "Profile $(PROFILE) defines no modules to build"; \
		exit 2; \
	fi
	@if [ -n "$(strip $(FIRMWARE))" ] && [ -n "$(strip $(FIRMWARES))" ]; then \
		echo "Profile $(PROFILE) sets both FIRMWARE and FIRMWARES"; \
		echo "The package treats the list as 'one of these is enough',"; \
		echo "which would hide a missing mandatory file. Pick one."; \
		exit 2; \
	fi

# The snapshot is built from the pinned ref plus the profile patch series,
# never from the shared linux_media working tree. That keeps it reproducible
# on any host, independent of which profile was patched there last, and it
# cannot pick up build artifacts such as *.mod.c.
check-snapshot: check-profile check-linux-media
	@set -eu; \
	if [ ! -d "$(LINUX_MEDIA)/.git" ]; then \
		echo "Not a git checkout: $(LINUX_MEDIA)"; \
		echo "Run: make fetch PROFILE=$(PROFILE)"; \
		exit 2; \
	fi; \
	if ! git -C "$(LINUX_MEDIA)" rev-parse --verify --quiet \
		"$(LINUX_MEDIA_REF)^{commit}" >/dev/null; then \
		echo "Pinned ref not found in $(LINUX_MEDIA): $(LINUX_MEDIA_REF)"; \
		echo "Run: make fetch PROFILE=$(PROFILE)"; \
		exit 2; \
	fi; \
	if [ ! -f "$(PATCH_SERIES)" ]; then \
		echo "Missing patch series file: $(PATCH_SERIES)"; \
		echo "Create it (empty is fine) so the snapshot is explicit."; \
		exit 2; \
	fi; \
	while read -r p || [ -n "$$p" ]; do \
		if [ -z "$$p" ]; then continue; fi; \
		if [ ! -f "$(PATCH_DIR)/$$p" ]; then \
			echo "Missing patch file: $(PATCH_DIR)/$$p"; \
			exit 2; \
		fi; \
		sed -n 's|^+++ b/||p; s|^--- a/||p' "$(PATCH_DIR)/$$p" \
		| sed 's|[[:space:]].*$$||' | sort -u \
		| while read -r f; do \
			if [ -z "$$f" ] || [ "$$f" = "/dev/null" ]; then continue; fi; \
			ok=0; \
			for d in $(DKMS_DIRS); do \
				case "$$f" in "$$d"/*) ok=1 ;; esac; \
			done; \
			if [ "$$ok" -eq 0 ]; then \
				echo "Patch $$p touches $$f, outside the profile directories"; \
				echo "The snapshot only carries: $(DKMS_DIRS)"; \
				exit 2; \
			fi; \
		done; \
	done < "$(PATCH_SERIES)"; \
	sha=$$(git -C "$(LINUX_MEDIA)" rev-parse "$(LINUX_MEDIA_REF)^{commit}"); \
	echo "Snapshot source: $$sha ($(LINUX_MEDIA_REF)) + $(PROFILE) patch series"

dkms-source: check-dkms-version check-dkms-profile check-snapshot
	@set -eu; \
	if [ -s "$(PATCH_SERIES)" ] && ! command -v patch >/dev/null 2>&1; then \
		echo "Missing tool: patch"; \
		echo "Run: sudo apt install patch"; \
		exit 2; \
	fi; \
	rm -rf "$(DKMS_SRC)"; \
	mkdir -p "$(DKMS_SRC)/mk"; \
	git -C "$(LINUX_MEDIA)" archive --format=tar "$(LINUX_MEDIA_REF)" \
		-- $(DKMS_DIRS) | tar -x -C "$(DKMS_SRC)"; \
	if [ -s "$(PATCH_SERIES)" ]; then \
		while read -r p || [ -n "$$p" ]; do \
			if [ -z "$$p" ]; then continue; fi; \
			patch -p1 -d "$(DKMS_SRC)" --forward --silent \
				--no-backup-if-mismatch < "$(PATCH_DIR)/$$p"; \
			echo "Applied to snapshot: $$p"; \
		done < "$(PATCH_SERIES)"; \
	fi; \
	for d in $(DKMS_DIRS); do \
		if [ ! -d "$(DKMS_SRC)/$$d" ]; then \
			echo "Missing directory in snapshot: $$d"; \
			exit 2; \
		fi; \
		find "$(DKMS_SRC)/$$d" -mindepth 1 -maxdepth 1 -type d \
			-exec rm -rf {} +; \
		find "$(DKMS_SRC)/$$d" -maxdepth 1 -type f \
			! -name '*.c' ! -name '*.h' ! -name 'Makefile' \
			! -name 'Kconfig' -delete; \
	done; \
	cp "$(BASE)/mk/build-modules.mk" "$(DKMS_SRC)/mk/build-modules.mk"; \
	{ \
		echo '# Generated by "make dkms-source". Do not edit.'; \
		echo "# Profile: $(PROFILE)"; \
		echo ''; \
		echo 'KVER ?= $$(shell uname -r)'; \
		echo 'KDIR ?= /lib/modules/$$(KVER)/build'; \
		echo 'LINUX_MEDIA := $$(CURDIR)'; \
		echo ''; \
		echo 'USB_DIR := $(USB_DIR)'; \
		echo 'FE_DIR := $(FE_DIR)'; \
		echo 'TUNER_DIR := $(TUNER_DIR)'; \
		echo ''; \
		echo 'USB_MODULES := $(USB_MODULES)'; \
		echo 'USB_KCONFIG := $(USB_KCONFIG)'; \
		echo 'USB_CFLAGS := $(USB_CFLAGS)'; \
		echo 'FE_MODULES := $(FE_MODULES)'; \
		echo 'FE_KCONFIG := $(FE_KCONFIG)'; \
		echo 'FE_CFLAGS := $(FE_CFLAGS)'; \
		echo 'TUNER_MODULES := $(TUNER_MODULES)'; \
		echo 'TUNER_KCONFIG := $(TUNER_KCONFIG)'; \
		echo 'TUNER_CFLAGS := $(TUNER_CFLAGS)'; \
		echo 'PROFILE_CFLAGS := $(PROFILE_CFLAGS)'; \
		echo ''; \
		echo '# DKMS calls MAKE[0] without a target and rewrites a leading'; \
		echo '# "make" into "make -j<n> KERNELRELEASE=<kver>", so the default'; \
		echo '# goal has to build everything.'; \
		echo '.DEFAULT_GOAL := all'; \
		echo '.PHONY: all'; \
		echo 'all: build-usb build-fe build-tuner'; \
		echo ''; \
		echo 'include $$(CURDIR)/mk/build-modules.mk'; \
	} > "$(DKMS_SRC)/Makefile"; \
	{ \
		echo "PACKAGE_NAME=\"$(DKMS_PACKAGE)\""; \
		echo "PACKAGE_VERSION=\"$(DKMS_VERSION)\""; \
		echo 'AUTOINSTALL="yes"'; \
		echo ''; \
		echo 'MAKE[0]="make KDIR=$${kernel_source_dir} KVER=$${kernelver}"'; \
		echo ''; \
		i=0; \
		for m in $(USB_MODULES); do \
			echo "BUILT_MODULE_NAME[$$i]=\"$${m%.ko}\""; \
			echo "BUILT_MODULE_LOCATION[$$i]=\"$(USB_DIR)\""; \
			echo "DEST_MODULE_LOCATION[$$i]=\"/updates/dkms\""; \
			echo ''; \
			i=$$((i + 1)); \
		done; \
		for m in $(FE_MODULES); do \
			echo "BUILT_MODULE_NAME[$$i]=\"$${m%.ko}\""; \
			echo "BUILT_MODULE_LOCATION[$$i]=\"$(FE_DIR)\""; \
			echo "DEST_MODULE_LOCATION[$$i]=\"/updates/dkms\""; \
			echo ''; \
			i=$$((i + 1)); \
		done; \
		for m in $(TUNER_MODULES); do \
			echo "BUILT_MODULE_NAME[$$i]=\"$${m%.ko}\""; \
			echo "BUILT_MODULE_LOCATION[$$i]=\"$(TUNER_DIR)\""; \
			echo "DEST_MODULE_LOCATION[$$i]=\"/updates/dkms\""; \
			echo ''; \
			i=$$((i + 1)); \
		done; \
	} > "$(DKMS_SRC)/dkms.conf"; \
	head_sha=$$(git -C "$(LINUX_MEDIA)" rev-parse "$(LINUX_MEDIA_REF)"); \
	{ \
		echo "profile: $(PROFILE)"; \
		echo "package: $(DKMS_PACKAGE)"; \
		echo "version: $(DKMS_VERSION)"; \
		echo "linux_media_url: $(LINUX_MEDIA_URL)"; \
		echo "linux_media_ref: $(LINUX_MEDIA_REF)"; \
		echo "linux_media_commit: $$head_sha"; \
		echo ''; \
		echo "patch series applied on top:"; \
		if [ -s "$(PATCH_SERIES)" ]; then \
			sed 's/^/  /' "$(PATCH_SERIES)"; \
		else \
			echo "  (none)"; \
		fi; \
		echo ''; \
		echo "Reproduce with:"; \
		echo "  git clone $(LINUX_MEDIA_URL)"; \
		echo "  git archive $(LINUX_MEDIA_REF) -- $(DKMS_DIRS)"; \
		echo "  then apply the series above with 'git apply -p1'"; \
	} > "$(DKMS_SRC)/PROVENANCE"; \
	echo "Wrote $(DKMS_SRC)"

check-deb-tools:
	@for t in dpkg-buildpackage dh_dkms; do \
		if ! command -v "$$t" >/dev/null 2>&1; then \
			echo "Missing tool: $$t"; \
			echo "Run: sudo apt install debhelper dh-dkms"; \
			exit 2; \
		fi; \
	done

dkms-deb: export DKMS_V_MODULE = $(DKMS_PACKAGE)
dkms-deb: export DKMS_V_PACKAGE = $(DKMS_DEB_PACKAGE)
dkms-deb: export DKMS_V_VERSION = $(DKMS_VERSION)
dkms-deb: export DKMS_V_PROFILE = $(PROFILE)
dkms-deb: export DKMS_V_MAINT = $(DEB_MAINTAINER)
dkms-deb: export DKMS_V_OVER = $(DKMS_MODULE_NAMES)
dkms-deb: export DKMS_V_FW = $(strip $(FIRMWARE) $(FIRMWARES))
dkms-deb: check-deb-tools dkms-source
	@set -eu; \
	src=$$(realpath -m -- "$(DKMS_SRC)"); \
	dist=$$(realpath -m -- "$(OUT_DIST)"); \
	build_dir="$$(dirname "$$src")"; \
	deb_dir="$$src/debian"; \
	rm -rf "$$deb_dir"; \
	mkdir -p "$$deb_dir/source" "$$dist"; \
	esc() { printf '%s' "$$1" | sed -e 's/[\\&|]/\\&/g'; }; \
	v_module=$$DKMS_V_MODULE; v_package=$$DKMS_V_PACKAGE; \
	v_version=$$DKMS_V_VERSION; v_profile=$$DKMS_V_PROFILE; \
	v_maint=$$DKMS_V_MAINT; v_over=$$DKMS_V_OVER; \
	fw_files=$$DKMS_V_FW; \
	fw_list="$$fw_files"; \
	if [ -z "$$fw_list" ]; then fw_list="(none required)"; fi; \
	subst="s|@MODULE@|$$(esc "$$v_module")|g; \
		s|@PACKAGE@|$$(esc "$$v_package")|g; \
		s|@VERSION@|$$(esc "$$v_version")|g; \
		s|@PROFILE@|$$(esc "$$v_profile")|g; \
		s|@MAINTAINER@|$$(esc "$$v_maint")|g; \
		s|@DATE@|$$(esc "$$(date -R -d @$${SOURCE_DATE_EPOCH:-$$(git -C \
			"$(BASE)" log -1 --format=%ct 2>/dev/null || date +%s)})")|g; \
		s|@FIRMWARE_FILES@|$$(esc "$$fw_files")|g; \
		s|@FIRMWARE_LIST@|$$(esc "$$fw_list")|g; \
		s|@OVERRIDE_LIST@|$$(esc "$$v_over")|g"; \
	stanzas="$$deb_dir/.driver-stanzas"; \
	: > "$$stanzas"; \
	( cd "$$src" && find drivers -type f \
		| sort | while read -r f; do \
			lic=$$(sed -n '1,3s|.*SPDX-License-Identifier:[[:space:]]*\([A-Za-z0-9.+-]*\).*|\1|p' "$$f" | head -1); \
			case "$$lic" in \
				GPL-2.0) lic=GPL-2.0-only ;; \
				GPL-2.0+) lic=GPL-2.0-or-later ;; \
				'') \
					if grep -qi 'any later version' "$$f"; then \
						lic=UNSPECIFIED-or-later; \
					else \
						lic=UNSPECIFIED-only; \
					fi ;; \
			esac; \
			printf '%s\t%s\n' "$$lic" "$$f"; \
		done ) | sort > "$$deb_dir/.lic-map"; \
	for lic in $$(cut -f1 "$$deb_dir/.lic-map" | sort -u); do \
		awk -F'\t' -v l="$$lic" '$$1==l {print $$2}' \
			"$$deb_dir/.lic-map" > "$$deb_dir/.files"; \
		( cd "$$src" && while read -r f; do \
			sed -n '1,60p' "$$f" | grep -i 'copyright' || true; \
		  done < "$$deb_dir/.files" ) \
		| sed -e 's|^[[:space:]/*#]*||' -e 's|[[:space:]]*\*/[[:space:]]*$$||' \
			-e 's|[[:space:]][[:space:]]*| |g' \
			-e 's|^[[:space:]]*||' -e 's|[[:space:]]*$$||' \
			-e 's|^[Cc][Oo][Pp][Yy][Rr][Ii][Gg][Hh][Tt][[:space:]]*||' \
			-e 's|^(c)[[:space:]]*||I' -e 's|^[Cc][Oo][Pp][Yy][Rr][Ii][Gg][Hh][Tt]||' \
		| grep -vE '^[[:space:]]*$$' | sort -u > "$$deb_dir/.holders"; \
		{ \
			printf 'Files:'; \
			sed 's/^/       /' "$$deb_dir/.files"; \
			if [ -s "$$deb_dir/.holders" ]; then \
				printf 'Copyright:\n'; \
				sed 's/^/ /' "$$deb_dir/.holders"; \
			else \
				echo "Copyright: no copyright notice in these files"; \
			fi; \
			case "$$lic" in \
				UNSPECIFIED-or-later) \
					echo "License: GPL-2.0-or-later"; \
					echo "Comment: No SPDX identifier in these files. Their"; \
					echo " licence text offers version 2 or, at the user's"; \
					echo " option, any later version."; ;; \
				UNSPECIFIED-only) \
					echo "License: GPL-2.0-only"; \
					echo "Comment: No SPDX identifier in these files and no"; \
					echo " later-version clause in their licence text; the"; \
					echo " Linux kernel default of GPL-2.0-only is assumed."; ;; \
				*) echo "License: $$lic"; ;; \
			esac; \
			echo ""; \
		} >> "$$stanzas"; \
	done; \
	for f in control rules changelog README.Debian; do \
		sed -e "$$subst" "$(DEB_TEMPLATE_DIR)/$$f" > "$$deb_dir/$$f"; \
	done; \
	sed -e "$$subst" "$(DEB_TEMPLATE_DIR)/copyright" \
		| awk -v s="$$stanzas" '/@DRIVER_STANZAS@/ { \
			while ((getline line < s) > 0) print line; next } 1' \
		> "$$deb_dir/copyright"; \
	rm -f "$$stanzas" "$$deb_dir/.lic-map" "$$deb_dir/.files" \
		"$$deb_dir/.holders"; \
	sed -e "$$subst" "$(DEB_TEMPLATE_DIR)/postinst" \
		> "$$deb_dir/$(DKMS_DEB_PACKAGE).postinst"; \
	cp "$(DEB_TEMPLATE_DIR)/source/format" "$$deb_dir/source/format"; \
	cp "$$src/dkms.conf" "$$deb_dir/$(DKMS_DEB_PACKAGE).dkms"; \
	chmod +x "$$deb_dir/rules" "$$deb_dir/$(DKMS_DEB_PACKAGE).postinst"; \
	( cd "$$src" && dpkg-buildpackage -us -uc -b ); \
	mv "$$build_dir/$(DKMS_DEB_PACKAGE)_$(DKMS_VERSION)_all.deb" "$$dist/"; \
	rm -f "$$build_dir/$(DKMS_PACKAGE)_$(DKMS_VERSION)_"*.buildinfo \
		"$$build_dir/$(DKMS_PACKAGE)_$(DKMS_VERSION)_"*.changes; \
	rm -rf "$$deb_dir"; \
	echo "Wrote $$dist/$(DKMS_DEB_PACKAGE)_$(DKMS_VERSION)_all.deb"
