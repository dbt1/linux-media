# Profile: tbs5580 (TBS 5580 CI USB2.0)
PROFILE_NAME := tbs5580

LINUX_MEDIA_URL := https://github.com/tbsdtv/linux_media.git
LINUX_MEDIA_REF := bef2e2680

PATCH_DIR := $(PATCHES_DIR)/tbs5580
PATCH_SERIES := $(PATCH_DIR)/series

USB_MODULES := dvb-usb.ko dvb-usb-tbs5580.ko
USB_KCONFIG := CONFIG_DVB_USB=m CONFIG_DVB_USB_TBS5580=m

FE_MODULES := si2183.ko
FE_KCONFIG := CONFIG_DVB_SI2183=m

TUNER_MODULES := av201x.ko
TUNER_KCONFIG := CONFIG_MEDIA_TUNER_AV201X=m

PROFILE_CFLAGS := -DCONFIG_MEDIA_TUNER_AV201X=1

FIRMWARE := dvb-usb-id5580.fw
USB_ID := 734c:5580
LOAD_MODULES := dvb_usb si2183 av201x dvb_usb_tbs5580
INSMOD_FILES := dvb-usb.ko si2183.ko av201x.ko dvb-usb-tbs5580.ko
RMMOD_MODULES := dvb_usb_tbs5580 dvb_usb si2183 av201x
MODPROBE_DEPS := dvb_core rc_core i2c-mux si2157
