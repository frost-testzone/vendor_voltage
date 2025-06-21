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
    SimpleDeviceConfig

ifneq ($(PRODUCT_NO_CAMERA),true)
PRODUCT_PACKAGES += \
    Aperture
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
