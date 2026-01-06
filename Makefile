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

USB_DIR := drivers/media/usb/dvb-usb
FE_DIR := drivers/media/dvb-frontends
TUNER_DIR := drivers/media/tuners

BASE_CFLAGS := -I$(LINUX_MEDIA)/drivers/media/dvb-frontends \
	-I$(LINUX_MEDIA)/drivers/media/tuners \
	-I$(LINUX_MEDIA)/drivers/media/common \
	-I$(LINUX_MEDIA)/$(USB_DIR)

PROFILE_CFLAGS ?=
USB_CFLAGS ?=
FE_CFLAGS ?=
TUNER_CFLAGS ?=

USB_EXTRA_CFLAGS := $(BASE_CFLAGS) $(PROFILE_CFLAGS) $(USB_CFLAGS)
FE_EXTRA_CFLAGS := $(BASE_CFLAGS) $(PROFILE_CFLAGS) $(FE_CFLAGS)
TUNER_EXTRA_CFLAGS := $(BASE_CFLAGS) $(PROFILE_CFLAGS) $(TUNER_CFLAGS)

USB_MODULES ?=
FE_MODULES ?=
TUNER_MODULES ?=

USB_KCONFIG ?=
FE_KCONFIG ?=
TUNER_KCONFIG ?=

OUTPUT_MODULES := $(USB_MODULES) $(FE_MODULES) $(TUNER_MODULES)
INSMOD_FILES ?=
RMMOD_MODULES ?=
MODPROBE_DEPS ?=
FIRMWARE ?=
FIRMWARES ?=
CHECK_MODULES ?= $(RMMOD_MODULES)

.PHONY: help tbs5580 t230 build fetch apply-patches check-profile \
	check-linux-media check-kdir precheck build-usb build-fe build-tuner \
	copy-mods artifacts instructions package clean print-vars

help:
	@printf "Usage:\\n"
	@printf "  make tbs5580 [KVER=...] [LINUX_MEDIA=...]\\n"
	@printf "  make t230 [KVER=...] [LINUX_MEDIA=...]\\n"
	@printf "  make build PROFILE=<name> [KVER=...]\\n"
	@printf "  make precheck PROFILE=<name>\\n"
	@printf "  make fetch PROFILE=<name>\\n"
	@printf "  make apply-patches PROFILE=<name>\\n"
	@printf "  make package PROFILE=<name>\\n"

tbs5580: build
t230: build

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

build-usb:
	@if [ -n "$(USB_MODULES)" ]; then \
		$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(USB_DIR)" $(USB_KCONFIG) \
			EXTRA_CFLAGS="$(USB_EXTRA_CFLAGS)" $(USB_MODULES); \
	else \
		echo "USB_MODULES empty, skipping"; \
	fi

build-fe:
	@if [ -n "$(FE_MODULES)" ]; then \
		$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(FE_DIR)" $(FE_KCONFIG) \
			EXTRA_CFLAGS="$(FE_EXTRA_CFLAGS)" $(FE_MODULES); \
	else \
		echo "FE_MODULES empty, skipping"; \
	fi

build-tuner:
	@if [ -n "$(TUNER_MODULES)" ]; then \
		$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(TUNER_DIR)" $(TUNER_KCONFIG) \
			EXTRA_CFLAGS="$(TUNER_EXTRA_CFLAGS)" $(TUNER_MODULES); \
	else \
		echo "TUNER_MODULES empty, skipping"; \
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

package: build
	@mkdir -p "$(OUT_DIST)"
	@tar -C "$(OUT_PROFILE)" -cJf "$(OUT_DIST)/$(PROFILE)-k$(KVER).tar.xz" \
		$(OUTPUT_MODULES) artifacts.txt INSTALL.txt
	@echo "Wrote $(OUT_DIST)/$(PROFILE)-k$(KVER).tar.xz"

clean:
	@$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(USB_DIR)" clean
	@$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(FE_DIR)" clean
	@$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$(TUNER_DIR)" clean

print-vars:
	@echo "PROFILE=$(PROFILE)"
	@echo "KVER=$(KVER)"
	@echo "KDIR=$(KDIR)"
	@echo "LINUX_MEDIA=$(LINUX_MEDIA)"
	@echo "OUT_BASE=$(OUT_BASE)"
	@echo "OUT_PROFILE=$(OUT_PROFILE)"
	@echo "OUT_DIST=$(OUT_DIST)"
