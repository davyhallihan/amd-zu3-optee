connect -url tcp:172.31.224.1:3121
configparams force-mem-access 1

# Try to reset the whole system first
targets -set -nocase -filter {name =~ "*PSU*"}
rst -system
after 2000

puts stderr "INFO: Configuring the FPGA..."
fpga "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/system.bit"

targets -set -nocase -filter {name =~ "*PSU*"}
mask_write 0xFFCA0038 0x1C0 0x1C0
targets -set -nocase -filter {name =~ "*MicroBlaze PMU*"}

if { [string first "Stopped" [state]] != 0 } {
	stop
}
puts stderr "INFO: Downloading PMUFW..."
dow "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/pmufw.elf"
con
after 500

targets -set -nocase -filter {name =~ "*A53*#0"}
rst -processor -clear-registers

source /home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/project-spec/hw-description/psu_init.tcl
puts stderr "INFO: Downloading FSBL..."
dow "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/zynqmp_fsbl.elf"
con
after 3000
stop
after 1000
psu_ps_pl_isolation_removal; psu_ps_pl_reset_config

# Ensure AFI (PS-PL AXI bridge) is out of reset and configured
# Release AFIFM0-5 resets in FPD (RST_FPD_TOP)
psu_mask_write 0xFD1A0100 0x00001F80 0x00000000
# Release AFIFM6 reset in LPD (RST_LPD_TOP)
psu_mask_write 0xFF5E023C 0x00080000 0x00000000
# Set AFIFM fabric width to 32-bit for HPM0_FPD (afi_fs)
psu_mask_write 0xFD615000 0x00000300 0x00000000

# Diagnostic: verify AFI and PL clock configuration
puts stderr "INFO: Verifying PS-PL bridge configuration..."
puts stderr "  RST_FPD_TOP (0xFD1A0100) - AFIFM bits [12:7] should be 0:"
puts stderr "    [mrd -force 0xFD1A0100]"
puts stderr "  RST_LPD_TOP (0xFF5E023C) - AFIFM6 bit [19] should be 0:"
puts stderr "    [mrd -force 0xFF5E023C]"
puts stderr "  AFI_FS (0xFD615000) - fabric width bits [9:8] should be 0 (32-bit):"
puts stderr "    [mrd -force 0xFD615000]"
puts stderr "  PL_CLK0 (PL0_REF_CTRL @ 0xFF5E00C0) - should be enabled:"
puts stderr "    [mrd -force 0xFF5E00C0]"
puts stderr "  Try reading PL peripheral at 0xA0000000 (ns_switch):"
if {[catch {puts stderr "    [mrd -force 0xA0000000]"} err]} {
    puts stderr "    FAILED: $err"
} else {
    puts stderr "    SUCCESS - PL AXI is working!"
}

puts stderr "INFO: Loading DTB..."
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/system.dtb" 0x100000

puts stderr "INFO: Downloading Kernel (Image)..."
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/Image" 0x00200000

puts stderr "INFO: Downloading RootFS..."
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/rootfs.cpio.gz.u-boot" 0x04000000

puts stderr "INFO: Downloading Boot Script..."
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/boot.scr" 0x20000000

puts stderr "INFO: Downloading U-Boot..."
dow "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/u-boot.elf"

puts stderr "INFO: Downloading OP-TEE..."
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/tee-header_v2.bin" 0x1E000000
dow -data "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/tee-raw.bin" 0x1E001000

puts stderr "INFO: Downloading BL31..."
dow "/home/davy/research/pynq-tee/amd-zu3-optee/zu3_optee/images/linux/bl31.elf"

puts stderr "INFO: Booting..."
con
