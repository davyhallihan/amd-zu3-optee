# create_secure_switch_design.tcl
# ============================================================================
# Batch-mode Vivado script to create a Zynq UltraScale+ block design with a
# TrustZone-secured AXI switch reader peripheral for the AUP-ZU3 board.
#
# Usage:
#   vivado -mode batch -source create_secure_switch_design.tcl
#
# Prerequisites:
#   - AUP-ZU3 board files installed in Vivado board store
#     (see: https://realdigital.org/hardware/aup-zu3)
#   - XDC pin assignments updated in zu3_switches.xdc
#
# Outputs:
#   output/hardware_design.xsa   — Hardware platform (XSA) with bitstream
#   output/bitstream.bit         — Standalone bitstream copy
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file join $script_dir "vivado_project"]
set output_dir [file join $script_dir "output"]

file mkdir $output_dir

# ----------------------------------------------------------------------------
# 1. Create Project — Zynq UltraScale+ (XCZU3EG)
# ----------------------------------------------------------------------------
puts "=== Creating Vivado project for AUP-ZU3 ==="
create_project secure_switch_zu3 $proj_dir -part xczu3eg-sfvc784-2-e -force

# Try to set board part (requires installed board files)
# Try 8GB variant first, then 4GB
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
    puts "Continuing with part-only project — PS will need manual preset."
    puts "Install board files from: https://github.com/RealDigitalOrg/aup-zu3-bsp/tree/master/board-files"
}

# ----------------------------------------------------------------------------
# 2. Add RTL source and constraints
# ----------------------------------------------------------------------------
puts "=== Adding source files ==="
add_files -norecurse [file join $script_dir "secure_switch_axi.v"]
add_files -fileset constrs_1 -norecurse [file join $script_dir "zu3_switches.xdc"]
update_compile_order -fileset sources_1

# ----------------------------------------------------------------------------
# 3. Create Block Design
# ----------------------------------------------------------------------------
puts "=== Creating block design ==="
create_bd_design "system"

# Add Zynq UltraScale+ MPSoC PS
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ps

# Apply board preset if board files are available
if {[catch {apply_board_connection -board_interface "default" -ip_intf "zynq_ps/default" -diagram "system"} err]} {
    puts "INFO: Board automation not available, configuring PS manually."
}

# Configure the PS — essential settings for AUP-ZU3
# Enable M_AXI_HPM0_FPD (AXI master for our PL peripheral)
# Enable UART1 (console on AUP-ZU3), basic DDR
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__PROTECTION__ENABLE {1} \
] [get_bd_cells zynq_ps]

# Add our secure switch reader as an RTL module reference
create_bd_cell -type module -reference secure_switch_axi secure_switch_0

# Create AXI Interconnect to bridge PS HPM0_FPD to our peripheral
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_interconnect_0]

# ----------------------------------------------------------------------------
# 4. Connect everything
# ----------------------------------------------------------------------------
puts "=== Wiring block design ==="

# Clocking: PS PL_CLK0 drives everything
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins zynq_ps/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins secure_switch_0/s_axi_aclk]

# Reset: PS PL_RESETN0
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins secure_switch_0/s_axi_aresetn]

# AXI bus: PS HPM0_FPD → Interconnect → Switch reader
connect_bd_intf_net [get_bd_intf_pins zynq_ps/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins secure_switch_0/s_axi]

# Make switches external
create_bd_port -dir I -from 1 -to 0 sw
connect_bd_net [get_bd_ports sw] [get_bd_pins secure_switch_0/sw]

# ----------------------------------------------------------------------------
# 5. Assign address
# ----------------------------------------------------------------------------
puts "=== Assigning addresses ==="
assign_bd_address

# Print the assigned address so the user can use it in OP-TEE
set addr_segs [get_bd_addr_segs -of_objects [get_bd_intf_pins secure_switch_0/s_axi]]
foreach seg $addr_segs {
    set offset [get_property OFFSET $seg]
    set range  [get_property RANGE $seg]
    puts "=============================================="
    puts "  PERIPHERAL ADDRESS: $offset  RANGE: $range"
    puts "  Use this address in OP-TEE platform_config.h"
    puts "=============================================="
}

# ----------------------------------------------------------------------------
# 6. Validate and save
# ----------------------------------------------------------------------------
puts "=== Validating design ==="
validate_bd_design
save_bd_design

# Create HDL wrapper
set wrapper [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper
update_compile_order -fileset sources_1

# ----------------------------------------------------------------------------
# 7. Synthesize, Implement, Generate Bitstream
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# 8. Export outputs
# ----------------------------------------------------------------------------
puts "=== Exporting XSA and bitstream ==="

# Export XSA with bitstream included
write_hw_platform -fixed -include_bit -force [file join $output_dir "hardware_design.xsa"]

# Also copy the bitstream directly
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
puts "  Copy XSA to build directory:"
puts "    cp vivado/output/hardware_design.xsa aup-zu3-8gb-hw/"
puts "=============================================="

exit
