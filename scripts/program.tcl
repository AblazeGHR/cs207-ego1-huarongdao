# ---------------------------------------------------------------------------
# program.tcl
# 连接 EGO1 并下载 ../build/proj_build.runs/impl_1/top.bit
# 用法（在 proj 目录下，先连接板子并上电）：
#   vivado.bat -mode batch -source scripts/program.tcl
# ---------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set bitfile    [file normalize [file join $root_dir .. build proj_build.runs impl_1 top.bit]]

if {![file exists $bitfile]} {
    error "Bitstream not found: $bitfile (run scripts/build_batch.tcl first)"
}

open_hw
connect_hw_server
refresh_hw_server

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    error "No JTAG target found. Check USB cable, board power, and Digilent driver."
}

current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    error "No FPGA device found on target."
}
current_hw_device [lindex $devices 0]
refresh_hw_device -update_hw_probes false [current_hw_device]

set_property PROGRAM.FILE $bitfile [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAMMED: $bitfile"

close_hw_target
disconnect_hw_server
close_hw
exit 0
