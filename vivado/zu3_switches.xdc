# AUP-ZU3 Slide Switch Pin Constraints
# From AUP-ZU3 Reference Manual, Appendix A — PL Pinout Table
# All 8 switches are on an HDIO bank with LVCMOS12 IOSTANDARD.
# This design uses SW0 and SW1 (matching the PYNQ-Z2 2-switch peripheral).
#
# Full pin map for reference:
#   PL_USER_SW0 = AB1    PL_USER_SW4 = AC1
#   PL_USER_SW1 = AF1    PL_USER_SW5 = AD6
#   PL_USER_SW2 = AE3    PL_USER_SW6 = AD1
#   PL_USER_SW3 = AC2    PL_USER_SW7 = AD2

# --- SW0 ---
set_property PACKAGE_PIN AB1 [get_ports {sw[0]}]
set_property IOSTANDARD LVCMOS12 [get_ports {sw[0]}]

# --- SW1 ---
set_property PACKAGE_PIN AF1 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports {sw[1]}]
