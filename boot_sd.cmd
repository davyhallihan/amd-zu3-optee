# Boot script for SD Card (MMC)
echo "--- Booting ZynqMP from SD Card ---"

# Set kernel arguments
# rootwait: Wait for SD card to be ready
setenv bootargs "console=ttyPS0,115200 root=/dev/ram0 rw earlycon clk_ignore_unused rootwait"

# Load artifacts from first partition of MMC device 0 (SD Card)
# Addresses match those used in JTAG script
echo "Loading Image..."
fatload mmc 0:1 0x03000000 Image

echo "Loading Device Tree..."
fatload mmc 0:1 0x02A00000 system.dtb

echo "Loading Initrd..."
fatload mmc 0:1 0x05000000 uInitrd

# Boot
echo "Booting..."
booti 0x03000000 0x05000000 0x02A00000
