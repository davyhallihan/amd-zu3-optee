# This is a boot script for U-Boot
# It assumes artifacts are loaded into memory by JTAG (or loaded from SD)

echo "--- Booting ZynqMP from JTAG/RAM ---"

# Set kernel arguments
# console=ttyPS0,115200: Serial console
# root=/dev/ram0: Root filesystem in RAM (initrd)
# rw: Read-write
# earlycon: Early console for debugging
setenv bootargs "console=ttyPS0,115200 root=/dev/ram0 rw earlycon clk_ignore_unused"

# Boot command
# booti <kernel_addr> <initrd_addr> <dtb_addr>
# Addresses must match boot_jtag.tcl
booti 0x03000000 0x05000000 0x02A00000
