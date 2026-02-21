COMPATIBLE_MACHINE:zynqmp = ".*"
OPTEEMACHINE:zynqmp = "zynqmp"
# PLATFORM_FLAVOR is not strictly needed here but good for consistency if recipes change
EXTRA_OEMAKE:append:zynqmp = " PLATFORM_FLAVOR=aup_zu3"
