# Connect to hw_server
if { [catch {connect -url TCP:172.31.224.1:3121} err] } {
    puts "Error connecting to hw_server: $err"
    exit 1
}
puts "Connected to hw_server"

# 1. Disable Security Gates to allow PMU access
puts "Disabling Security Gates..."
if { [catch {targets -set -filter {name =~ "PSU"}} err] } {
    puts "Error selecting PSU: $err"
} else {
    # Write to JTAG_CTRL register to disable security gates
    mwr 0xffca0038 0x1ff
    after 500
}

# Debug: List targets to see if MicroBlaze PMU is visible
puts "Targets after disabling security gates:"
puts [targets]

# 2. Load and Run PMU Firmware on PMU Target
puts "Selecting MicroBlaze PMU..."
if { [catch {targets -set -filter {name =~ "*MicroBlaze PMU*"}} err] } {
    puts "Error selecting MicroBlaze PMU: $err"
} else {
    puts "Loading PMUFW..."
    dow artifacts/pmufw.elf
    con
    after 500
}

# 3. Select A53 Core 0
puts "Selecting Cortex-A53 #0..."
if { [catch {targets -set -filter {name =~ "Cortex-A53 #0"}} err] } {
    puts "Error selecting A53 #0: $err"
    # Fallback/Debug: Print available targets
    puts "Available targets:"
    puts [targets]
    exit 1
}

# 4. Reset the processor (Clear Reset)
puts "Resetting Processor..."
rst -processor

# 4. Select A53 Core 0 again
puts "Selecting Cortex-A53 #0..."
targets -set -filter {name =~ "Cortex-A53 #0"}

# 5. Download and Run FSBL to initialize system
puts "Loading FSBL..."
dow artifacts/fsbl.elf
con
after 5000
stop

# 4. Load Bitstream (PL Configuration)
puts "Loading Bitstream..."
fpga artifacts/bitstream.bit

# 5. Load PMU Firmware
# (Loaded earlier)

# 6. Load ATF (BL31)
puts "Loading ATF (BL31)..."
dow artifacts/bl31.elf

# 7. Load OP-TEE (BL32)
puts "Loading OP-TEE (BL32)..."
dow artifacts/optee_os.elf
# ATF jumps to 0x1E000000 but the optee_os.elf _start is at 0x1E001000.
# The area at 0x1E000000 contains the 'OPTE' magic header when built via bin format,
# but via ELF it's empty/uninitialized memory. We must put a branch here.
puts "Patching OP-TEE header (0x1E000000) with branch to 0x1E001000..."
mwr 0x1E000000 0x14000400

# 8. Load U-Boot (BL33)
puts "Loading U-Boot (BL33)..."
dow artifacts/u-boot.elf

# 9. Load Linux Images (Kernel, DTB, Initrd, Boot Script)
puts "Loading Linux Kernel..."
dow -data artifacts/zImage 0x03000000

puts "Loading Device Tree..."
dow -data artifacts/system.dtb 0x02A00000

puts "Loading Initrd..."
dow -data artifacts/uInitrd 0x05000000

puts "Loading Boot Script..."
dow -data artifacts/boot_tee.scr 0x02000000

# 10. Start Execution (ATF -> OP-TEE -> U-Boot)
puts "Setting PC to ATF Entry Point (0x20000000)..."
rwr pc 0x20000000

puts "Booting..."
con
