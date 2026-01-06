# Profile: t210 (DVB-T210 v2.0)
# Note: Some units report the same USB ID as T230C v2 (0572:c68a).
# Adjust USB_ID if your stick differs.
PROFILE_NAME := t210

LINUX_MEDIA_URL := https://github.com/tbsdtv/linux_media.git
LINUX_MEDIA_REF := bef2e2680

PATCH_DIR := $(PATCHES_DIR)/t210
PATCH_SERIES := $(PATCH_DIR)/series

USB_DIR := drivers/media/usb/dvb-usb-v2

USB_MODULES := dvb_usb_v2.ko dvb-usb-dvbsky.ko
USB_KCONFIG := CONFIG_DVB_USB_V2=m CONFIG_DVB_USB_DVBSKY=m

FE_MODULES := si2168.ko
FE_KCONFIG := CONFIG_DVB_SI2168=m

TUNER_MODULES := si2157.ko
TUNER_KCONFIG := CONFIG_MEDIA_TUNER_SI2157=m

FIRMWARES := dvb-demod-si2168-a20-01.fw dvb-demod-si2168-a30-01.fw dvb-demod-si2168-b40-01.fw dvb-demod-si2168-d60-01.fw
USB_ID := 0572:c68a

INSMOD_FILES := dvb_usb_v2.ko dvb-usb-dvbsky.ko si2168.ko si2157.ko
RMMOD_MODULES := dvb_usb_dvbsky dvb_usb_v2 si2168 si2157
MODPROBE_DEPS := dvb_core rc_core i2c-mux
