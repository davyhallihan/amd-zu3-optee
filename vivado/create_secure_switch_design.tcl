# create_secure_switch_design.tcl -- AUP-ZU3 (Zynq UltraScale+)
#
# Creates a Vivado block design with two instances of secure_switch_axi
# connected to the ZynqMP PS via an AXI interconnect:
#
#   ZynqMP M_AXI_HPM0_FPD --> AXI Interconnect --> M00: secure_switch_0  (TZ-protected)
#                                               --> M01: ns_switch_0      (non-secure)
#
# Both peripherals read the same physical switches. M00_SECURE=1 is always
# enabled here because the ZU3's AXI interconnect correctly does per-port
# security filtering (unlike the Zynq-7000 which blocks all non-secure
# traffic when any port is marked secure).
#
# Usage:
#   vivado -mode batch -source create_secure_switch_design.tcl
#
# Prerequisites:
#   AUP-ZU3 board files installed in Vivado board store
#   (see: https://realdigital.org/hardware/aup-zu3)
#
# Outputs:
#   output/hardware_design.xsa
#   output/bitstream.bit

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file join $script_dir "vivado_project"]
set output_dir [file join $script_dir "output"]

file mkdir $output_dir

# --- Create project ---
puts "=== Creating Vivado project for AUP-ZU3 ==="
create_project secure_switch_zu3 $proj_dir -part xczu3eg-sfvc784-2-e -force

# Try board files (8GB variant first, then 4GB)
set board_set 0
foreach bp {realdigital.org:aup-zu3-8gb:part0:1.0 realdigital.org:aup-zu3-4gb:part0:1.0} {
    if {![catch {set_property board_part $bp [current_project]}]} {
        puts "INFO: Board part set to $bp"
        set board_set 1
        break
    }
}
if {!$board_set} {
    puts "WARNING: Could not set board_part (board files may not be installed)."
    puts "Install from: https://github.com/RealDigitalOrg/aup-zu3-bsp/tree/master/board-files"
}

# --- Add RTL and constraints ---
puts "=== Adding source files ==="
add_files -norecurse [file join $script_dir "secure_switch_axi.v"]
add_files -fileset constrs_1 -norecurse [file join $script_dir "zu3_switches.xdc"]
update_compile_order -fileset sources_1

# --- Block design ---
puts "=== Creating block design ==="
create_bd_design "system"

# ZynqMP PS
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ps

# Apply board preset (DDR timing, MIO config, clocks, etc.)
if {[catch {apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ps]} err]} {
    puts "WARNING: Board automation failed: $err"
    puts "Falling back to manual PS configuration."
}

# Enable what the board preset might not cover
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__PROTECTION__ENABLE {1} \
] [get_bd_cells zynq_ps]

# Two instances of our switch peripheral
create_bd_cell -type module -reference secure_switch_axi secure_switch_0
create_bd_cell -type module -reference secure_switch_axi ns_switch_0

# AXI interconnect with 2 master ports (one per peripheral)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI {2} [get_bd_cells axi_interconnect_0]

# --- Wiring ---
puts "=== Wiring block design ==="

# Clock: PS PL_CLK0 (100 MHz) drives everything
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins zynq_ps/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/M01_ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins secure_switch_0/s_axi_aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins ns_switch_0/s_axi_aclk]

# Reset: PS PL_RESETN0
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/M01_ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins secure_switch_0/s_axi_aresetn]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins ns_switch_0/s_axi_aresetn]

# AXI data path: PS -> interconnect -> peripherals
connect_bd_intf_net [get_bd_intf_pins zynq_ps/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins secure_switch_0/s_axi]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] [get_bd_intf_pins ns_switch_0/s_axi]

# TrustZone: M00 is secure-only (ZU3 interconnect handles this per-port)
set_property CONFIG.M00_SECURE {1} [get_bd_cells axi_interconnect_0]

# Both peripherals share the same physical switch pins
create_bd_port -dir I -from 1 -to 0 sw
connect_bd_net [get_bd_ports sw] [get_bd_pins secure_switch_0/sw]
connect_bd_net [get_bd_ports sw] [get_bd_pins ns_switch_0/sw]

# --- Address assignment ---
puts "=== Assigning addresses ==="
assign_bd_address

puts "=============================================="
foreach {inst label} {secure_switch_0 "SECURE" ns_switch_0 "NON-SECURE"} {
    set addr_segs [get_bd_addr_segs -of_objects [get_bd_intf_pins ${inst}/s_axi]]
    foreach seg $addr_segs {
        set offset [get_property OFFSET $seg]
        set range  [get_property RANGE $seg]
        puts "  $label PERIPHERAL ($inst): $offset  RANGE: $range"
    }
}
puts "  Use secure address for CFG_SWITCH_BASE in OP-TEE build"
puts "  Use non-secure address for NS_SWITCH_ADDR in host app build"
puts "=============================================="

# --- Validate and save ---
puts "=== Validating design ==="
validate_bd_design
save_bd_design

set wrapper [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper
update_compile_order -fileset sources_1

# --- Build ---
puts "=== Running synthesis ==="
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts "=== Running implementation + bitstream ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    puts "ERROR: Implementation/bitstream failed!"
    exit 1
}

# --- Export ---
puts "=== Exporting XSA and bitstream ==="

write_hw_platform -fixed -include_bit -force [file join $output_dir "hardware_design.xsa"]

set bit_file [glob -nocomplain [file join $proj_dir "secure_switch_zu3.runs" "impl_1" "*.bit"]]
if {[llength $bit_file] > 0} {
    file copy -force [lindex $bit_file 0] [file join $output_dir "bitstream.bit"]
} else {
    puts "WARNING: Could not find .bit file to copy"
}

puts ""
puts "=============================================="
puts "  BUILD COMPLETE"
puts "  XSA: [file join $output_dir hardware_design.xsa]"
puts "  BIT: [file join $output_dir bitstream.bit]"
puts ""
puts "  Next: copy XSA to PetaLinux project hardware source"
puts "=============================================="

exit
