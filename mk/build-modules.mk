# Shared module build recipes.
#
# Included by the repository Makefile and by the generated Makefile inside a
# DKMS source tree, so both build the modules in exactly the same way.
#
# The includer must set these before the include:
#   KDIR         kernel build directory (/lib/modules/<KVER>/build)
#   LINUX_MEDIA  source root that contains drivers/media/...
#                  repo build: $(BASE)/linux_media
#                  DKMS build: $(CURDIR), the copied tree is the root itself
#
# Everything else comes from profiles/<name>.mk and has a default here.

USB_DIR ?= drivers/media/usb/dvb-usb
FE_DIR ?= drivers/media/dvb-frontends
TUNER_DIR ?= drivers/media/tuners

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

.PHONY: build-usb build-fe build-tuner clean

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

# Tolerate a missing KDIR: when DKMS removes a module the headers of the
# kernel being removed are usually gone already, and failing there would
# abort the removal.
clean:
	@if [ ! -d "$(KDIR)" ]; then \
		echo "KDIR not present, nothing to clean: $(KDIR)"; \
		exit 0; \
	fi; \
	for pair in "$(USB_DIR):$(USB_MODULES)" "$(FE_DIR):$(FE_MODULES)" \
		"$(TUNER_DIR):$(TUNER_MODULES)"; do \
		dir="$${pair%%:*}"; \
		mods="$${pair#*:}"; \
		if [ -n "$$mods" ]; then \
			$(MAKE) -C "$(KDIR)" M="$(LINUX_MEDIA)/$$dir" clean; \
		fi; \
	done
