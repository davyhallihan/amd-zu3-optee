set url [lindex $argv 0]
if {$url == ""} {
    set url "TCP:127.0.0.1:3121"
}
connect -url $url
puts "Connected to hw_server"
puts "Available targets:"
set target_list [targets]
puts $target_list

if {[llength $target_list] == 0} {
    puts "ERROR: No targets found. Please check:"
    puts "1. Is the board powered on?"
    puts "2. Is the USB/JTAG cable connected?"
    puts "3. Do you have the necessary cable drivers installed?"
    puts "4. Is the boot mode jumper set correctly (JTAG mode)?"
    exit 1
}

if {[catch {targets -set -nocase -filter {name =~ "arm*#0"}} err]} {
    puts "Error selecting ARM target: $err"
    puts "Trying to select any target to inspect..."
    exit 1
}

# Reset system
rst -system
after 1000

# 1. Program FPGA
puts "Loading Bitstream..."
fpga artifacts/bitstream.bit

# 2. Download and run FSBL
puts "Loading FSBL..."
dow artifacts/fsbl.elf
con
after 5000
stop

# 3. Download PMU Firmware (Required for ZynqMP)
puts "Loading PMU Firmware..."
dow artifacts/pmufw.elf

# 4. Download ATF (Arm Trusted Firmware)
puts "Loading ATF..."
dow artifacts/bl31.elf

# 5. Download U-Boot
puts "Loading U-Boot..."
dow artifacts/u-boot.elf

# 6. Download Kernel
puts "Loading Kernel..."
dow -data artifacts/Image 0x80000

# 7. Download Device Tree
puts "Loading Device Tree..."
dow -data artifacts/system.dtb 0x100000

# 8. Download boot.scr (if used)
puts "Loading Boot Script..."
dow -data artifacts/boot.scr 0x20000000

# Start execution
puts "Booting..."
con
