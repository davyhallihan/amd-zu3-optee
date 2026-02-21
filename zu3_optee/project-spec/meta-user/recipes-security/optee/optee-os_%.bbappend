FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://0001-add-aup-zu3-target.patch"

COMPATIBLE_MACHINE:zynqmp = ".*"
OPTEEMACHINE:zynqmp = "zynqmp"
EXTRA_OEMAKE:append:zynqmp = " PLATFORM_FLAVOR=aup_zu3 CFG_TEE_CORE_LOG_LEVEL=4 CFG_TZDRAM_START=0x1E001000 CFG_CORE_TXLAT_TABLES=32 MAX_XLAT_TABLES=32 CFG_CORE_RESERVED_SHM=n"
CFLAGS:append:zynqmp = " -DMAX_XLAT_TABLES=32"

do_compile:prepend() {
    # Force configuration variables
    export CFG_DDR_SIZE=0x100000000
    export CFG_CORE_TXLAT_TABLES=32
    export MAX_XLAT_TABLES=32
    
    echo "DEBUG: Starting do_compile:prepend"
}

do_compile:append() {
    # Debug: Check conf.h AFTER build
    find ${B} -name "conf.h" -exec echo "DEBUG: Found conf.h at {}" \; -exec cat {} \;

    # Patch tee-header_v2.bin to jump to 0x1E001000
    # Use python to safely write binary data
    if [ -f "${B}/core/tee-header_v2.bin" ]; then
        python3 -c "import sys; sys.stdout.buffer.write(b'\x00\x04\x00\x14')" | dd of="${B}/core/tee-header_v2.bin" bs=1 count=4 conv=notrunc
    fi
}

do_deploy:append() {
    # Automatically copy artifacts to images/linux
    install -d ${TOPDIR}/../images/linux
    
    # Artifacts are deployed into an 'optee' subdirectory
    if [ -f "${DEPLOYDIR}/optee/tee-header_v2.bin" ]; then
        install -m 0644 ${DEPLOYDIR}/optee/tee-header_v2.bin ${TOPDIR}/../images/linux/tee-header_v2.bin
    fi
    if [ -f "${DEPLOYDIR}/optee/tee-raw.bin" ]; then
        install -m 0644 ${DEPLOYDIR}/optee/tee-raw.bin ${TOPDIR}/../images/linux/tee-raw.bin
    fi
    if [ -f "${DEPLOYDIR}/optee/tee.elf" ]; then
        install -m 0644 ${DEPLOYDIR}/optee/tee.elf ${TOPDIR}/../images/linux/bl32.elf
    fi
}
