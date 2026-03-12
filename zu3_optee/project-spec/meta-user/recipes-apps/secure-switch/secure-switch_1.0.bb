SUMMARY = "Secure Switch OP-TEE Trusted Application and Client Application"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit externalsrc python3native

# Point bitbake to the source code directory directly
EXTERNALSRC = "${THISDIR}/../../../../../secure_switch"
EXTERNALSRC_BUILD = "${EXTERNALSRC}"

DEPENDS = "optee-client optee-os optee-os-tadevkit python3-pycryptodomex-native python3-cryptography-native"

EXTRA_OEMAKE = " \
    TA_DEV_KIT_DIR=${STAGING_INCDIR}/optee/export-user_ta \
    TEEC_EXPORT=${STAGING_DIR_HOST}/usr \
    HOST_CROSS_COMPILE=${HOST_PREFIX} \
    TA_CROSS_COMPILE=${HOST_PREFIX} \
    V=1 \
"

do_compile() {
    export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
    export CFLAGS="${CFLAGS} --sysroot=${STAGING_DIR_HOST}"
    export LDFLAGS="${LDFLAGS} --sysroot=${STAGING_DIR_HOST}"
    oe_runmake -C ${S} all
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/host/optee_benchmark ${D}${bindir}

    install -d ${D}${nonarch_base_libdir}/optee_armtz
    install -m 0444 ${B}/ta/*.ta ${D}${nonarch_base_libdir}/optee_armtz
}

FILES:${PN} += "${nonarch_base_libdir}/optee_armtz/"
