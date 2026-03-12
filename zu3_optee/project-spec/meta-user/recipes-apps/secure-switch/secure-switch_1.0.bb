SUMMARY = "Secure Switch Benchmark - OP-TEE Client Application"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit externalsrc python3native

# Point bitbake to the source code directory directly
EXTERNALSRC = "${THISDIR}/../../../../../secure_switch"
EXTERNALSRC_BUILD = "${EXTERNALSRC}"

DEPENDS = "optee-client"

EXTRA_OEMAKE = " \
    TEEC_EXPORT=${STAGING_DIR_HOST}/usr \
    HOST_CROSS_COMPILE=${HOST_PREFIX} \
    V=1 \
"

do_compile() {
    export CFLAGS="${CFLAGS} --sysroot=${STAGING_DIR_HOST}"
    export LDFLAGS="${LDFLAGS} --sysroot=${STAGING_DIR_HOST}"
    oe_runmake -C ${S} all
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/host/optee_benchmark ${D}${bindir}
}

FILES:${PN} = "${bindir}/optee_benchmark"
