# Copyright (C) 2018-2024 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# Kernel build configuration variables
# ====================================
#
# These config vars are usually set in BoardConfig.mk:
#
#   TARGET_KERNEL_SOURCE               = Kernel source dir, optional, defaults
#                                          to kernel/$(TARGET_DEVICE_DIR)
#   TARGET_KERNEL_ARCH                 = Kernel Arch
#   TARGET_KERNEL_CROSS_COMPILE_PREFIX = Compiler prefix (e.g. arm-eabi-)
#                                          defaults to arm-linux-androidkernel- for arm
#                                                      aarch64-linux-android- for arm64
#                                                      x86_64-linux-android- for x86
#   TARGET_KERNEL_CROSS_COMPILE_PREFIX_ARM32 = Compiler prefix for building vDSO32
#                                              defaults to arm-linux-androidkernel- for arm64
#
#   TARGET_KERNEL_CLANG_COMPILE        = Compile kernel with clang, defaults to true
#   TARGET_KERNEL_CLANG_VERSION        = Clang prebuilts version, optional, defaults to clang-stable
#   TARGET_KERNEL_CLANG_PATH           = Clang prebuilts path, optional
#
#   TARGET_KERNEL_LIBC_SYSROOT_USE     = libc sysroot to use, defaults to "host" for 6.11+
#
#   TARGET_KERNEL_LLVM_BINUTILS        = Use LLVM binutils, defaults to true
#   TARGET_KERNEL_RUST_VERSION         = Rust prebuilts version, optional
#   TARGET_KERNEL_NO_GCC               = Fully compile the kernel without GCC.
#                                        Defaults to false
#   TARGET_KERNEL_VERSION              = Reported kernel version in top level kernel
#                                        makefile. Can be overriden in device trees
#                                        in the event of prebuilt kernel.
#
#   TARGET_KERNEL_DTBO_PREFIX          = Override path prefix of TARGET_KERNEL_DTBO.
#                                        Defaults to empty
#   TARGET_KERNEL_DTBO                 = Name of the kernel Makefile target that
#                                        generates dtbo.img. Defaults to dtbo.img
#   TARGET_KERNEL_DTB                  = Name of the kernel Makefile target that
#                                        generates the *.dtb targets. Defaults to dtbs
#
#   TARGET_KERNEL_EXT_MODULE_ROOT      = Optional, the external modules root directory
#                                          Defaults to empty
#   TARGET_KERNEL_EXT_MODULES          = Optional, the external modules we are
#                                          building. Defaults to empty
#
#   KERNEL_TOOLCHAIN_PREFIX            = Overrides TARGET_KERNEL_CROSS_COMPILE_PREFIX,
#                                          Set this var in shell to override
#                                          toolchain specified in BoardConfig.mk
#   KERNEL_TOOLCHAIN                   = Path to toolchain, if unset, assumes
#                                          TARGET_KERNEL_CROSS_COMPILE_PREFIX
#                                          is in PATH
#   USE_CCACHE                         = Enable ccache (global Android flag)

BUILD_TOP := $(abspath .)

TARGET_AUTO_KDIR := $(shell echo $(TARGET_DEVICE_DIR) | sed -e 's/^device/kernel/g')
TARGET_KERNEL_SOURCE ?= $(TARGET_AUTO_KDIR)

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
    KERNEL_ARCH := $(TARGET_ARCH)
else
    KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

KERNEL_VERSION := $(shell grep -s "^VERSION = " $(TARGET_KERNEL_SOURCE)/Makefile | awk '{ print $$3 }')
KERNEL_PATCHLEVEL := $(shell grep -s "^PATCHLEVEL = " $(TARGET_KERNEL_SOURCE)/Makefile | awk '{ print $$3 }')
TARGET_KERNEL_VERSION ?= $(shell echo $(KERNEL_VERSION)"."$(KERNEL_PATCHLEVEL))

# 5.10+ can fully compile without GCC by default
ifneq ($(KERNEL_VERSION),)
    ifeq ($(shell expr $(KERNEL_VERSION) \>= 6), 1)
        TARGET_KERNEL_NO_GCC ?= true
    else ifeq ($(shell expr $(KERNEL_VERSION) \>= 5), 1)
        ifeq ($(shell expr $(KERNEL_PATCHLEVEL) \>= 10), 1)
            TARGET_KERNEL_NO_GCC ?= true
        endif
    endif
endif

# 6.11+ can no longer use aosp glibc sysroot headers (too old)
ifneq ($(KERNEL_VERSION),)
    ifeq ($(shell expr $(KERNEL_VERSION) \< 6), 1)
        # empty
    else ifeq ($(KERNEL_VERSION), 6)
        ifeq ($(shell expr $(KERNEL_PATCHLEVEL) \>= 11), 1)
            TARGET_KERNEL_LIBC_SYSROOT_USE ?= host
        endif
    else
        TARGET_KERNEL_LIBC_SYSROOT_USE ?= host
    endif
endif

ifeq ($(TARGET_KERNEL_NO_GCC), true)
    KERNEL_NO_GCC := true
endif

ifneq ($(TARGET_KERNEL_CLANG_VERSION),)
    KERNEL_CLANG_VERSION := clang-$(TARGET_KERNEL_CLANG_VERSION)
else
    # Use the default version of clang if TARGET_KERNEL_CLANG_VERSION hasn't been set by the device config
    KERNEL_CLANG_VERSION := $(LLVM_AOSP_PREBUILTS_VERSION)
endif
TARGET_KERNEL_CLANG_PATH ?= $(BUILD_TOP)/prebuilts/clang/host/$(HOST_PREBUILT_TAG)/$(KERNEL_CLANG_VERSION)

TARGET_KERNEL_RUST_VERSION ?= 1.73.0c

ifneq ($(USE_CCACHE),)
    ifneq ($(CCACHE_EXEC),)
        # Android 10+ deprecates use of a build ccache. Only system installed ones are now allowed
        CCACHE_BIN := $(CCACHE_EXEC)
    endif
endif

# Clear this first to prevent accidental poisoning from env
KERNEL_MAKE_FLAGS :=

# Use "safe" default values for kernel build user & host - matches Pixels, helps avoid detection
KERNEL_MAKE_FLAGS += \
    KBUILD_BUILD_USER="build-user" \
    KBUILD_BUILD_HOST="build-host"

# Add back threads, ninja cuts this to $(getconf _NPROCESSORS_ONLN)/2
KERNEL_MAKE_FLAGS += -j$(shell getconf _NPROCESSORS_ONLN)

TOOLS_PATH_OVERRIDE := \
    HIP_PATH=none PERL5LIB=$(BUILD_TOP)/prebuilts/tools-lineage/common/perl-base

ifneq ($(KERNEL_NO_GCC), true)
    GCC_PREBUILTS := $(BUILD_TOP)/prebuilts/gcc/$(HOST_PREBUILT_TAG)
    # arm64 toolchain
    KERNEL_TOOLCHAIN_arm64 := $(GCC_PREBUILTS)/aarch64/aarch64-linux-android-4.9/bin
    KERNEL_TOOLCHAIN_PREFIX_arm64 := aarch64-linux-android-
    # arm toolchain
    KERNEL_TOOLCHAIN_arm := $(GCC_PREBUILTS)/arm/arm-linux-androideabi-4.9/bin
    KERNEL_TOOLCHAIN_PREFIX_arm := arm-linux-androidkernel-
    # x86 toolchain
    KERNEL_TOOLCHAIN_x86 := $(GCC_PREBUILTS)/x86/x86_64-linux-android-4.9/bin
    KERNEL_TOOLCHAIN_PREFIX_x86 := x86_64-linux-android-

    TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
    ifneq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
        KERNEL_TOOLCHAIN_PREFIX ?= $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
    else
        KERNEL_TOOLCHAIN ?= $(KERNEL_TOOLCHAIN_$(KERNEL_ARCH))
        KERNEL_TOOLCHAIN_PREFIX ?= $(KERNEL_TOOLCHAIN_PREFIX_$(KERNEL_ARCH))
    endif

    TARGET_KERNEL_CROSS_COMPILE_PREFIX_ARM32 := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX_ARM32))
    ifneq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX_ARM32),)
        KERNEL_TOOLCHAIN_PREFIX_ARM32 ?= $(TARGET_KERNEL_CROSS_COMPILE_PREFIX_ARM32)
    else
        KERNEL_TOOLCHAIN_ARM32 ?= $(KERNEL_TOOLCHAIN_arm)
        KERNEL_TOOLCHAIN_PREFIX_ARM32 ?= $(KERNEL_TOOLCHAIN_PREFIX_arm)
    endif

    ifeq ($(KERNEL_TOOLCHAIN),)
        KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN_PREFIX)
    else
        KERNEL_TOOLCHAIN_PATH := $(KERNEL_TOOLCHAIN)/$(KERNEL_TOOLCHAIN_PREFIX)
    endif

    ifeq ($(KERNEL_TOOLCHAIN_ARM32),)
        KERNEL_TOOLCHAIN_PATH_ARM32 := $(KERNEL_TOOLCHAIN_PREFIX_ARM32)
    else
        KERNEL_TOOLCHAIN_PATH_ARM32 := $(KERNEL_TOOLCHAIN_ARM32)/$(KERNEL_TOOLCHAIN_PREFIX_ARM32)
    endif

    # We need to add GCC toolchain to the path no matter what
    # for tools like `as`
    KERNEL_TOOLCHAIN_PATH_gcc := $(KERNEL_TOOLCHAIN_$(KERNEL_ARCH))

    ifneq ($(TARGET_KERNEL_CLANG_COMPILE),false)
        KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(KERNEL_TOOLCHAIN_PATH)"
    else
        KERNEL_CROSS_COMPILE := CROSS_COMPILE="$(CCACHE_BIN) $(KERNEL_TOOLCHAIN_PATH)"
    endif

    # Needed for CONFIG_COMPAT_VDSO, safe to set for all arm64 builds
    ifeq ($(KERNEL_ARCH),arm64)
        KERNEL_CROSS_COMPILE += CROSS_COMPILE_ARM32="$(KERNEL_TOOLCHAIN_PATH_ARM32)"
        KERNEL_CROSS_COMPILE += CROSS_COMPILE_COMPAT="$(KERNEL_TOOLCHAIN_PATH_ARM32)"
    endif

    ifeq ($(TARGET_KERNEL_CLANG_COMPILE),false)
        ifeq ($(KERNEL_ARCH),arm)
            # Avoid "Unknown symbol _GLOBAL_OFFSET_TABLE_" errors
            KERNEL_MAKE_FLAGS += CFLAGS_MODULE="-fno-pic"
        endif

        ifeq ($(KERNEL_ARCH),arm64)
            # Avoid "unsupported RELA relocation: 311" errors (R_AARCH64_ADR_GOT_PAGE)
            KERNEL_MAKE_FLAGS += CFLAGS_MODULE="-fno-pic"
        endif
    endif

    KERNEL_MAKE_FLAGS += HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu" HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -fuse-ld=lld"

    ifeq ($(KERNEL_ARCH),arm64)
        # Add 32-bit GCC to PATH so that arm-linux-androidkernel-as is available for CONFIG_COMPAT_VDSO
        TOOLS_PATH_OVERRIDE += PATH=$(BUILD_TOP)/prebuilts/tools-lineage/$(HOST_PREBUILT_TAG)/bin:$(KERNEL_TOOLCHAIN_arm):$$PATH
    else
        TOOLS_PATH_OVERRIDE += PATH=$(BUILD_TOP)/prebuilts/tools-lineage/$(HOST_PREBUILT_TAG)/bin:$$PATH
    endif

    # Set the full path to the clang command and LLVM binutils
    KERNEL_MAKE_FLAGS += HOSTCC=$(TARGET_KERNEL_CLANG_PATH)/bin/clang
    KERNEL_MAKE_FLAGS += HOSTCXX=$(TARGET_KERNEL_CLANG_PATH)/bin/clang++
    ifneq ($(TARGET_KERNEL_CLANG_COMPILE), false)
        ifneq ($(TARGET_KERNEL_LLVM_BINUTILS), false)
            KERNEL_MAKE_FLAGS += LD=$(TARGET_KERNEL_CLANG_PATH)/bin/ld.lld
            KERNEL_MAKE_FLAGS += AR=$(TARGET_KERNEL_CLANG_PATH)/bin/llvm-ar
        endif
    endif
else
    ifeq ($(TARGET_KERNEL_LIBC_SYSROOT_USE), host)
        KERNEL_HOST_C_LD_FLAGS_SYSROOT :=
    else
        KERNEL_HOST_C_LD_FLAGS_SYSROOT := --sysroot=$(BUILD_TOP)/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot
    endif

    KERNEL_MAKE_FLAGS += HOSTCFLAGS="$(KERNEL_HOST_C_LD_FLAGS_SYSROOT) -I$(BUILD_TOP)/prebuilts/kernel-build-tools/linux-x86/include"
    KERNEL_MAKE_FLAGS += HOSTLDFLAGS="$(KERNEL_HOST_C_LD_FLAGS_SYSROOT) -Wl,-rpath,$(BUILD_TOP)/prebuilts/kernel-build-tools/linux-x86/lib64 -L $(BUILD_TOP)/prebuilts/kernel-build-tools/linux-x86/lib64 -fuse-ld=lld --rtlib=compiler-rt"

    TOOLS_PATH_OVERRIDE += PATH=$(BUILD_TOP)/prebuilts/tools-lineage/$(HOST_PREBUILT_TAG)/bin:$(TARGET_KERNEL_CLANG_PATH)/bin:$(BUILD_TOP)/prebuilts/rust/$(HOST_PREBUILT_TAG)/$(TARGET_KERNEL_RUST_VERSION)/bin:$(BUILD_TOP)/prebuilts/clang-tools/$(HOST_PREBUILT_TAG)/bin:$$PATH
endif

# Set DTBO image locations so the build system knows to build them
ifeq (true,$(filter true, $(TARGET_NEEDS_DTBOIMAGE) $(BOARD_KERNEL_SEPARATED_DTBO)))
    TARGET_KERNEL_DTBO_PREFIX ?=
    TARGET_KERNEL_DTBO ?= dtbo.img
    BOARD_PREBUILT_DTBOIMAGE ?= $(TARGET_OUT_INTERMEDIATES)/DTBO_OBJ/arch/$(KERNEL_ARCH)/boot/$(TARGET_KERNEL_DTBO_PREFIX)$(TARGET_KERNEL_DTBO)
endif

# Set the default dtb target
TARGET_KERNEL_DTB ?= dtbs

# Set no external modules by default
TARGET_KERNEL_EXT_MODULE_ROOT ?=
TARGET_KERNEL_EXT_MODULES ?=

# Set use the full path to the make command
KERNEL_MAKE_CMD := $(BUILD_TOP)/prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin/make

# Use LLVM's substitutes for GNU binutils
ifneq ($(TARGET_KERNEL_CLANG_COMPILE), false)
    ifneq ($(TARGET_KERNEL_LLVM_BINUTILS), false)
        KERNEL_MAKE_FLAGS += LLVM=1 LLVM_IAS=1
    endif
endif

# Pass prebuilt LZ4 path
KERNEL_MAKE_FLAGS += LZ4=$(BUILD_TOP)/prebuilts/kernel-build-tools/linux-x86/bin/lz4

# Since Linux 4.16, flex and bison are required
KERNEL_MAKE_FLAGS += LEX=$(BUILD_TOP)/prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin/flex
KERNEL_MAKE_FLAGS += YACC=$(BUILD_TOP)/prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin/bison
KERNEL_MAKE_FLAGS += M4=$(BUILD_TOP)/prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin/m4
TOOLS_PATH_OVERRIDE += BISON_PKGDATADIR=$(BUILD_TOP)/prebuilts/build-tools/common/bison

# Since Linux 5.10, pahole is required
KERNEL_MAKE_FLAGS += PAHOLE=$(BUILD_TOP)/prebuilts/kernel-build-tools/linux-x86/bin/pahole

# Set the out dir for the kernel's O= arg
# This needs to be an absolute path, so only set this if the standard out dir isn't used
OUT_DIR_PREFIX := $(shell echo $(OUT_DIR) | sed -e 's|/target/.*$$||g')
KERNEL_BUILD_OUT_PREFIX :=
ifeq ($(OUT_DIR_PREFIX),out)
    KERNEL_BUILD_OUT_PREFIX := $(BUILD_TOP)/
endif
