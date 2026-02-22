# ==============================================================================
#  AMD Zynq UltraScale+ (ZU3EG) Secure Boot Makefile
#  Target Board: AUP Z3
#  Features: OP-TEE (Secure World) + Linux (Non-Secure) + BusyBox RootFS
# ==============================================================================

# Prereqs
# - sudo apt install swig

# --- Toolchain ---
CROSS_COMPILE_AARCH64 := $(abspath gnu/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-)
CROSS_COMPILE_BARE    := $(abspath gnu/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-elf/bin/aarch64-none-elf-)
PATH := $(PATH):$(realpath /tools/xilinx/petalinux/2025.1/components/xsct/bin) # add xsct to path
PATH := $(PATH):$(realpath /tools/xilinx/2025.1/Vivado/bin) # add bootgen to path
PATH := $(PATH):$(abspath u-boot-xlnx/tools) # add mkimage
PATH := $(PATH):$(abspath gnu/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu/bin) # add linux cross compiler
PATH := $(PATH):$(abspath gnu/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-elf/bin) # add fsbl cross compiler
export PATH

# --- Memory Layout (Critical for TrustZone) ---
# We reserve 32MB for OP-TEE at 0x1E000000. 
# This must match Device Tree and OP-TEE configuration.
TZDRAM_START    := 0x1E001000
TZDRAM_SIZE     := 0x01E00000
SHMEM_START     := 0x1FE00000
SHMEM_SIZE      := 0x00200000

# --- Directory Definitions ---
VENDOR_DIR      := aup-zu3-8gb-hw
ARTIFACTS_DIR   := artifacts
ROOTFS_BUILD    := $(ARTIFACTS_DIR)/rootfs_build

# Repositories (Git Submodules or Clones)
ATF_DIR         := arm-trusted-firmware
OPTEE_OS_DIR    := optee_os
OPTEE_CLI_DIR   := optee_client
OPTEE_EX_DIR    := optee_examples
SECURE_SW_DIR   := secure_switch
UBOOT_DIR       := u-boot-xlnx
BUSYBOX_VER     := 1.36.1
BUSYBOX_VER     := 1.36.1
BUSYBOX_DIR     := busybox-$(BUSYBOX_VER)
LINUX_DIR       := linux-xlnx

# --- Input Artifacts (From Vitis) ---
FSBL_ELF        := $(VENDOR_DIR)/fsbl.elf 
PMUFW_ELF       := $(VENDOR_DIR)/pmufw.elf 

# --- Final Outputs ---
BOOT_BIN        := $(ARTIFACTS_DIR)/BOOT.BIN
UINITRD         := $(ARTIFACTS_DIR)/uInitrd
SYSTEM_DTB      := $(ARTIFACTS_DIR)/system.dtb
UBOOT_ELF       := $(ARTIFACTS_DIR)/u-boot.elf
ATF_ELF         := $(ARTIFACTS_DIR)/bl31.elf
ATF_ELF         := $(ARTIFACTS_DIR)/bl31.elf
OPTEE_ELF       := $(ARTIFACTS_DIR)/optee_os.elf
UTEE_ITB        := $(ARTIFACTS_DIR)/uTee
BOOT_SCR        := $(ARTIFACTS_DIR)/boot_tee.scr
BITSTREAM       := $(ARTIFACTS_DIR)/bitstream.bit
ZIMAGE          := $(ARTIFACTS_DIR)/zImage

# ==============================================================================
#  Main Targets
# ==============================================================================
.PHONY: all setup clean help check_vitis rootfs atf optee uboot linux clean-atf clean-optee clean-uboot clean-rootfs clean-linux

all: setup check_vitis $(BOOT_BIN) $(UINITRD) $(SYSTEM_DTB) $(UTEE_ITB) $(BOOT_SCR) $(ZIMAGE) $(BITSTREAM)
	@echo "============================================================"
	@echo " Build Complete!"
	@echo " 1. Copy these to SD Card (FAT32 partition):"
	@echo "    - $(BOOT_BIN)"
	@echo "    - $(UINITRD)"
	@echo "    - $(SYSTEM_DTB)"
	@echo "    - Image (Linux Kernel - build separately or copy from PetaLinux)"
	@echo "============================================================"

check_vitis:
	@mkdir -p $(ARTIFACTS_DIR) $(VENDOR_DIR)
	@if [ ! -f $(FSBL_ELF) ]; then echo "❌ ERROR: $(FSBL_ELF) missing. Please copy from Vitis!"; exit 1; fi
	@if [ ! -f $(PMUFW_ELF) ]; then echo "❌ ERROR: $(PMUFW_ELF) missing. Please copy from Vitis!"; exit 1; fi
	@cp $(FSBL_ELF) $(ARTIFACTS_DIR)/
	@cp $(PMUFW_ELF) $(ARTIFACTS_DIR)/
	@# Check for XSA if bitstream is missing
	@if [ ! -f $(BITSTREAM) ]; then \
		XSA_FILE=$$(find $(VENDOR_DIR) -name "*.xsa" | head -n 1); \
		if [ -z "$$XSA_FILE" ]; then \
			echo "❌ ERROR: No .xsa file found in $(VENDOR_DIR). Please provide an XSA or $(BITSTREAM)!"; \
			exit 1; \
		else \
			echo ">>> Found XSA: $$XSA_FILE. Bitstream will be extracted."; \
		fi \
	fi

# ==============================================================================
#  0. Set Up Directories
# ==============================================================================
setup:
	@echo "============================================================"
	@echo " Setting up development environment..."
	@echo "============================================================"
	@mkdir -p $(ARTIFACTS_DIR) $(VENDOR_DIR) $(ROOTFS_BUILD)

	@echo ">>> Initializing Git Submodules (or cloning if not present)..."
	@if [ ! -d $(ATF_DIR) ]; then git clone https://github.com/ARM-software/arm-trusted-firmware $(ATF_DIR); fi
	@if [ ! -d $(OPTEE_OS_DIR) ]; then git clone https://github.com/OP-TEE/optee_os $(OPTEE_OS_DIR); fi
	@if [ ! -d $(OPTEE_CLI_DIR) ]; then git clone https://github.com/OP-TEE/optee_client $(OPTEE_CLI_DIR); fi
	@if [ ! -d $(OPTEE_EX_DIR) ]; then git clone https://github.com/linaro-swg/optee_examples $(OPTEE_EX_DIR); fi
	@if [ ! -d $(UBOOT_DIR) ]; then git clone https://github.com/Xilinx/u-boot-xlnx $(UBOOT_DIR); fi
	@if [ ! -d $(LINUX_DIR) ]; then \
		echo ">>> Cloning Linux Kernel (This may take a while)..."; \
		git clone --depth 1 -b xlnx_rebase_v6.6_LTS_2024.1 https://github.com/Xilinx/linux-xlnx.git $(LINUX_DIR); \
	fi
	@if [ ! -d gnu/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu ]; then \
		echo ">>> Downloading ARM GNU Toolchain..."; \
		wget https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz -O /tmp/arm-gnu-toolchain.tar.xz && \
		wget https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-elf.tar.xz -O /tmp/arm-gnu-toolchain-elf.tar.xz && \
		mkdir -p gnu && \
		tar xf /tmp/arm-gnu-toolchain.tar.xz -C gnu && \
		tar xf /tmp/arm-gnu-toolchain-elf.tar.xz -C gnu && \
		rm /tmp/arm-gnu-toolchain.tar.xz /tmp/arm-gnu-toolchain-elf.tar.xz; \
	else \
		echo ">>> ARM GNU Toolchain already present."; \
	fi


# ==============================================================================
#  1. Arm Trusted Firmware (ATF / BL31)
# ==============================================================================
$(ATF_ELF):
	@echo ">>> Building ATF (EL3 Secure Monitor)..."
	$(MAKE) -C $(ATF_DIR) \
		CROSS_COMPILE=$(CROSS_COMPILE_BARE) \
		PLAT=zynqmp \
		SPD=opteed \
		PRELOADED_BL33_BASE=0x8000000 \
		ZYNQMP_ATF_MEM_BASE=0x20000000 \
		ZYNQMP_ATF_MEM_SIZE=0x80000 \
		ZYNQMP_BL32_MEM_BASE=0x1E000000 \
		ZYNQMP_BL32_MEM_SIZE=0x02000000 \
		BL32_BASE=0x1E000000 \
		BL32_MEM_BASE=0x1E000000 \
		DEBUG=1 \
		LOG_LEVEL=50 \
		ZYNQMP_CONSOLE=cadence1 \
		bl31
	if [ -f $(ATF_DIR)/build/zynqmp/debug/bl31/bl31.elf ]; then \
		cp $(ATF_DIR)/build/zynqmp/debug/bl31/bl31.elf $@; \
	else \
		cp $(ATF_DIR)/build/zynqmp/release/bl31/bl31.elf $@; \
	fi

# ==============================================================================
#  2. OP-TEE OS (BL32)
# ==============================================================================
# Set CFG_TEE_CORE_LOG_LEVEL to 2 for debug, 0 for release, 4 for verbose
$(OPTEE_ELF):
	@echo ">>> Building OP-TEE OS..."
	$(MAKE) -C $(OPTEE_OS_DIR) \
		CROSS_COMPILE=$(CROSS_COMPILE_BARE) \
		CROSS_COMPILE64=$(CROSS_COMPILE_BARE) \
		CROSS_COMPILE_ta_arm64=$(CROSS_COMPILE_AARCH64) \
		CFG_USER_TA_TARGETS=ta_arm64 \
		PLATFORM=zynqmp \
		CFG_ARM64_core=y \
		CFG_UART_BASE=UART1_BASE \
		CFG_UART_IT=IT_UART1 \
		CFG_UART_CLK_HZ=100000000 \
		CFG_DDR_SIZE=0x100000000 \
		CFG_TEE_CORE_LOG_LEVEL=4 \
		CFG_CORE_TXLAT_TABLES=32 \
		CFG_CORE_RESERVED_SHM=n \
		CFG_TZDRAM_START=$(TZDRAM_START) \
		CFG_TZDRAM_SIZE=$(TZDRAM_SIZE) \
		CFG_SHMEM_START=$(SHMEM_START) \
		CFG_SHMEM_SIZE=$(SHMEM_SIZE)
	cp $(OPTEE_OS_DIR)/out/arm-plat-zynqmp/core/tee.elf $@

# ==============================================================================
#  3. U-Boot (BL33)
# ==============================================================================
$(UBOOT_ELF):
	@echo ">>> Building U-Boot..."
	# Using generic virtualization config which is standard for ZynqMP
	$(MAKE) -C $(UBOOT_DIR) xilinx_zynqmp_virt_defconfig
	$(MAKE) -C $(UBOOT_DIR) \
		CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		DEVICE_TREE=zynqmp-zcu102-rev1.0 \
		all
	cp $(UBOOT_DIR)/u-boot.elf $@

# ==============================================================================
#  3.1. Boot Script (boot.scr)
# ==============================================================================
$(BOOT_SCR): boot.cmd
	@echo ">>> Compiling Boot Script..."
	$(MKIMAGE) -C none -A arm -T script -d boot.cmd $@

# ==============================================================================
#  3.2. uTee (OP-TEE Image for U-Boot)
# ==============================================================================
$(UTEE_ITB): $(OPTEE_ELF)
	@echo ">>> Generating uTee..."
	$(CROSS_COMPILE_AARCH64)objcopy -O binary $(OPTEE_ELF) $(OPTEE_OS_DIR)/tee.bin
	$(MKIMAGE) -A arm64 -O linux -C none -T kernel -a $(TZDRAM_START) -e $(TZDRAM_START) \
		-n "OP-TEE" -d $(OPTEE_OS_DIR)/tee.bin $@

# ==============================================================================
#  4. Device Tree (Patched for OP-TEE)
# ==============================================================================
$(SYSTEM_DTB): $(UBOOT_ELF)
	@echo ">>> Generating Device Tree with OP-TEE Memory Reservation..."
	# 1. Pre-process the ZCU102 DTS (closest relative to AUP Z3 in mainline)
	$(CROSS_COMPILE_AARCH64)cpp -E -nostdinc -I$(UBOOT_DIR)/arch/arm/dts -I$(UBOOT_DIR)/include -I$(UBOOT_DIR)/dts/upstream/include \
		-D__DTS__ -x assembler-with-cpp \
		$(UBOOT_DIR)/arch/arm/dts/zynqmp-zcu102-rev1.0.dts \
		-o $(ARTIFACTS_DIR)/pre_system.dts
	
	# 2. Append OP-TEE Memory Node
	# We strictly reserve the memory so Linux doesn't crash accessing Secure World
	echo "/ { reserved-memory { \
		#address-cells = <2>; #size-cells = <2>; ranges; \
		optee_reserved: optee@1E000000 { \
			reg = <0x0 0x1E000000 0x0 0x02000000>; \
			no-map; \
		}; \
	}; };" >> $(ARTIFACTS_DIR)/pre_system.dts

	# 3. Compile
	dtc -I dts -O dtb -o $@ $(ARTIFACTS_DIR)/pre_system.dts

# ==============================================================================
#  5. Root Filesystem (BusyBox + OP-TEE Client/Examples)
# ==============================================================================
# Helper to fetch busybox if missing
busybox_src:
	@if [ ! -d $(BUSYBOX_DIR) ]; then \
		wget https://busybox.net/downloads/$(BUSYBOX_DIR).tar.bz2; \
		tar -xjf $(BUSYBOX_DIR).tar.bz2; \
	fi

# Build BusyBox Statically
busybox_build: busybox_src
	$(MAKE) -C $(BUSYBOX_DIR) defconfig
	sed -i 's/^.*CONFIG_STATIC[^_].*/CONFIG_STATIC=y/' $(BUSYBOX_DIR)/.config
	$(MAKE) -C $(BUSYBOX_DIR) CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) install CONFIG_PREFIX=$(abspath $(ROOTFS_BUILD))

# Build OP-TEE Client (libteec / tee-supplicant)
optee_client_build:
	$(MAKE) -C $(OPTEE_CLI_DIR) \
		CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		WITH_TEEACL=0 \
		CFG_TEE_CLIENT_LOG_LEVEL=2
	mkdir -p $(ROOTFS_BUILD)/usr/lib $(ROOTFS_BUILD)/usr/sbin
	cp $(OPTEE_CLI_DIR)/out/libteec/libteec.so.2.0.0 $(ROOTFS_BUILD)/usr/lib/libteec.so.2
	ln -sf libteec.so.2 $(ROOTFS_BUILD)/usr/lib/libteec.so
	cp $(OPTEE_CLI_DIR)/out/tee-supplicant/tee-supplicant $(ROOTFS_BUILD)/usr/sbin/

# Build Examples
optee_examples_build: $(OPTEE_ELF) optee_client_build
	$(MAKE) -C $(OPTEE_EX_DIR) \
		HOST_CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		TA_CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		TEEC_EXPORT=$(abspath $(OPTEE_CLI_DIR)/out/export/usr) \
		TA_DEV_KIT_DIR=$(abspath $(OPTEE_OS_DIR)/out/arm-plat-zynqmp/export-ta_arm64)
	mkdir -p $(ROOTFS_BUILD)/usr/bin $(ROOTFS_BUILD)/lib/optee_armtz
	find $(OPTEE_EX_DIR)/out/ca -type f -executable -exec cp {} $(ROOTFS_BUILD)/usr/bin/ \;
	find $(OPTEE_EX_DIR)/out/ta -name "*.ta" -exec cp {} $(ROOTFS_BUILD)/lib/optee_armtz/ \;

# Build Secure Switch Benchmark (TA + CA)
secure_switch_build: $(OPTEE_ELF) optee_client_build
	@echo ">>> Building Secure Switch Benchmark TA/CA..."
	$(MAKE) -C $(SECURE_SW_DIR)/ta \
		CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		TA_DEV_KIT_DIR=$(abspath $(OPTEE_OS_DIR)/out/arm-plat-zynqmp/export-ta_arm64)
	$(MAKE) -C $(SECURE_SW_DIR)/host \
		CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) \
		TEEC_EXPORT=$(abspath $(OPTEE_CLI_DIR)/out/export/usr) \
		--no-builtin-variables
	mkdir -p $(ROOTFS_BUILD)/usr/bin $(ROOTFS_BUILD)/lib/optee_armtz
	cp $(SECURE_SW_DIR)/host/optee_benchmark_switch $(ROOTFS_BUILD)/usr/bin/
	cp $(SECURE_SW_DIR)/ta/*.ta $(ROOTFS_BUILD)/lib/optee_armtz/

# Create Init Script
init_script:
	mkdir -p $(ROOTFS_BUILD)/proc $(ROOTFS_BUILD)/sys $(ROOTFS_BUILD)/dev $(ROOTFS_BUILD)/tmp
	echo '#!/bin/sh' > $(ROOTFS_BUILD)/init
	echo 'mount -t proc proc /proc' >> $(ROOTFS_BUILD)/init
	echo 'mount -t sysfs sysfs /sys' >> $(ROOTFS_BUILD)/init
	echo 'mount -t devtmpfs devtmpfs /dev' >> $(ROOTFS_BUILD)/init
	echo 'echo "--- Starting OP-TEE Supplicant ---"' >> $(ROOTFS_BUILD)/init
	echo '/usr/sbin/tee-supplicant &' >> $(ROOTFS_BUILD)/init
	echo 'sleep 1' >> $(ROOTFS_BUILD)/init
	echo 'echo "--- Boot Complete. Spawning shell... ---"' >> $(ROOTFS_BUILD)/init
	echo 'exec /bin/sh' >> $(ROOTFS_BUILD)/init
	chmod +x $(ROOTFS_BUILD)/init

# Assemble RootFS Image (uInitrd)
MKIMAGE := $(abspath u-boot-xlnx/tools/mkimage)

$(UINITRD): busybox_build optee_client_build optee_examples_build secure_switch_build init_script
	@echo ">>> Packing Initramfs..."
	cd $(ROOTFS_BUILD) && find . | cpio -H newc -o | gzip > ../rootfs.cpio.gz
	$(MKIMAGE) -A arm64 -T ramdisk -C gzip -d $(ARTIFACTS_DIR)/rootfs.cpio.gz $@

# ==============================================================================
#  5.1. Linux Kernel (zImage)
# ==============================================================================
$(ZIMAGE):
	@echo ">>> Building Linux Kernel..."
	$(MAKE) -C $(LINUX_DIR) ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) xilinx_zynqmp_defconfig
	$(MAKE) -C $(LINUX_DIR) ARCH=arm64 CROSS_COMPILE=$(CROSS_COMPILE_AARCH64) -j$$(nproc) Image
	cp $(LINUX_DIR)/arch/arm64/boot/Image $@

# ==============================================================================
#  6. Boot Image Generation (BOOT.BIN)
# ==============================================================================
BOOTGEN := /tools/xilinx/2025.1/Vivado/bin/bootgen

$(BOOT_BIN): $(FSBL_ELF) $(PMUFW_ELF) $(ATF_ELF) $(OPTEE_ELF) $(UBOOT_ELF)
	@echo ">>> Generating BOOT.BIN..."
	# Create BIF file dynamically
	echo "the_ROM_image: {" > artifacts/boot.bif
	echo "  [bootloader, destination_cpu=a53-0] $(FSBL_ELF)" >> artifacts/boot.bif
	echo "  [destination_cpu=pmu] $(PMUFW_ELF)" >> artifacts/boot.bif
	echo "  [destination_cpu=a53-0, exception_level=el-3, trustzone] $(ATF_ELF)" >> artifacts/boot.bif
	echo "  [destination_cpu=a53-0, destination_device=ps] $(OPTEE_ELF)" >> artifacts/boot.bif
	echo "  [destination_cpu=a53-0, exception_level=el-2] $(UBOOT_ELF)" >> artifacts/boot.bif
	echo "}" >> artifacts/boot.bif
	$(BOOTGEN) -arch zynqmp -image artifacts/boot.bif -w -o $@

# ==============================================================================
#  7. Bitstream Extraction
# ==============================================================================
$(BITSTREAM):
	@echo ">>> Extracting Bitstream from XSA..."
	@XSA_FILE=$$(find $(VENDOR_DIR) -name "*.xsa" | head -n 1); \
	if [ -z "$$XSA_FILE" ]; then echo "❌ ERROR: No XSA found!"; exit 1; fi; \
	unzip -p $$XSA_FILE *.bit > $@

# ==============================================================================
#  Clean
# ==============================================================================
clean: clean-atf clean-optee clean-uboot clean-rootfs clean-linux
	rm -rf $(ARTIFACTS_DIR)

clean-atf:
	rm -f $(ATF_ELF)
	$(MAKE) -C $(ATF_DIR) distclean

clean-optee:
	rm -f $(OPTEE_ELF) $(UTEE_ITB)
	$(MAKE) -C $(OPTEE_OS_DIR) clean

clean-uboot:
	rm -f $(UBOOT_ELF) $(BOOT_SCR) $(SYSTEM_DTB)
	$(MAKE) -C $(UBOOT_DIR) distclean

clean-rootfs:
	rm -f $(UINITRD)
	rm -rf $(ROOTFS_BUILD)
	$(MAKE) -C $(OPTEE_CLI_DIR) clean
	$(MAKE) -C $(OPTEE_EX_DIR) clean
	@if [ -d $(BUSYBOX_DIR) ]; then $(MAKE) -C $(BUSYBOX_DIR) clean; fi

clean-linux:
	rm -f $(ZIMAGE)
	$(MAKE) -C $(LINUX_DIR) clean