FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://0001-add-aup-zu3-target.patch"

COMPATIBLE_MACHINE:zynqmp = ".*"
OPTEEMACHINE:zynqmp = "zynqmp"
EXTRA_OEMAKE:append:zynqmp = " PLATFORM_FLAVOR=aup_zu3"
