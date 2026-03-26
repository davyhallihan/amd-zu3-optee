# Top-level Makefile for AUP-ZU3 OP-TEE benchmark
#
# Prerequisites:
#   source /tools/xilinx/petalinux/2025.1/settings.sh
#
# Full build from scratch:
#   make bitstream    (requires Vivado, ~15 min)
#   make all          (petalinux-build + copy bitstream, ~30-60 min)
#
# Rebuild just the benchmark app:
#   make benchmark

VIVADO ?= /tools/xilinx/2025.2/Vivado/bin/vivado
PETALINUX_DIR = zu3_optee
IMAGES = $(PETALINUX_DIR)/images/linux

.PHONY: all bitstream build copy_bitstream benchmark clean

all: build copy_bitstream

bitstream:
	cd vivado && $(VIVADO) -mode batch -source create_secure_switch_design.tcl
	cp vivado/output/bitstream.bit $(PETALINUX_DIR)/project-spec/hw-description/hardware_design.bit

build:
	@if [ ! -f $(PETALINUX_DIR)/project-spec/hw-description/hardware_design.bit ]; then \
		echo "ERROR: hardware_design.bit not found."; \
		echo "  Run 'make bitstream' first (requires Vivado)."; \
		exit 1; \
	fi
	cd $(PETALINUX_DIR) && petalinux-build

# petalinux-build overwrites system.bit — copy our Vivado bitstream back
copy_bitstream:
	cp vivado/output/bitstream.bit $(IMAGES)/system.bit

benchmark:
	cd $(PETALINUX_DIR) && petalinux-build -c secure-switch -x cleansstate && petalinux-build -c secure-switch
	@echo "Rebuild rootfs to include updated benchmark..."
	cd $(PETALINUX_DIR) && petalinux-build -c petalinux-image-minimal -x cleansstate && petalinux-build

clean:
	cd $(PETALINUX_DIR) && petalinux-build -x mrproper
