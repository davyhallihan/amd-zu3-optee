connect -url tcp:172.31.224.1:3121
puts stderr "INFO: Configuring the FPGA..."
fpga "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/system.bit"

targets -set -nocase -filter {name =~ "*PSU*"}
mask_write 0xFFCA0038 0x1C0 0x1C0
targets -set -nocase -filter {name =~ "*MicroBlaze PMU*"}

if { [string first "Stopped" [state]] != 0 } {
	stop
}
puts stderr "INFO: Downloading PMUFW..."
dow "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/pmufw.elf"
con

targets -set -nocase -filter {name =~ "*A53*#0"}
rst -processor -clear-registers

source /home/davy/research/optee/zup_pl_project/zu3_optee/project-spec/hw-description/psu_init.tcl
puts stderr "INFO: Downloading FSBL..."
dow "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/zynqmp_fsbl.elf"
con
after 3000
stop
psu_ps_pl_isolation_removal; psu_ps_pl_reset_config

puts stderr "INFO: Loading DTB..."
dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/system.dtb" 0x100000

# puts stderr "INFO: Downloading Kernel (Image)..."
# dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/Image" 0x00200000

# puts stderr "INFO: Downloading RootFS..."
# dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/rootfs.cpio.gz.u-boot" 0x04000000

puts stderr "INFO: Downloading Boot Script..."
dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/boot.scr" 0x20000000

puts stderr "INFO: Downloading U-Boot..."
dow "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/u-boot.elf"

puts stderr "INFO: Downloading OP-TEE..."
dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/tee-header_v2.bin" 0x1E000000
dow -data "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/tee-raw.bin" 0x1E001000

puts stderr "INFO: Downloading BL31..."
dow "/home/davy/research/optee/zup_pl_project/zu3_optee/images/linux/bl31.elf"

puts stderr "INFO: Booting..."
con
