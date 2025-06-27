# VoltageOS packages
PRODUCT_PACKAGES += \
    Covers \
    ThemePicker \
    AvatarPicker \
    ThemesStub \
    LogViewer \
    GmsCompat \
    NetworkLocation \
    AppCompatConfig \
    SimpleDeviceConfig \
    Datura

ifneq ($(PRODUCT_NO_CAMERA),true)
PRODUCT_PACKAGES += \
    Aperture
endif

ifeq ($(VOLTAGE_BUILD_TYPE),OFFICIAL)
include vendor/voltage-priv/keys/keys.mk
else
-include vendor/voltage-priv/keys/keys.mk
endif

# Extra tools in Voltage
PRODUCT_PACKAGES += \
    awk \
    bzip2 \
    curl \
    getcap \
    libsepol \
    setcap \

# Filesystems tools
PRODUCT_PACKAGES += \
    fsck.exfat \
    mke2fs \
    mkfs.exfat

# VoltageOS UDFPS animations
ifeq ($(EXTRA_UDFPS_ANIMATIONS),true)
PRODUCT_PACKAGES += \
    UdfpsIcons \
    UdfpsAnimations
endif
