# ---------------------------------------------------------------------------
# build_batch.tcl
# 不打开 GUI 工程，独立创建构建工程并跑综合/实现/bitstream。
# 用法（在 proj 目录下）：
#   vivado.bat -mode batch -source scripts/build_batch.tcl
# 输出：../build/proj_build.runs/impl_1/top.bit
# ---------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set build_dir  [file normalize [file join $root_dir .. build]]

puts "ROOT  = $root_dir"
puts "BUILD = $build_dir"

create_project -force proj_build $build_dir -part xc7a35tcsg324-1

set rtl_files [glob -nocomplain [file join $root_dir rtl *.v]]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root_dir constrs ego1.xdc]

set_property top top [get_filesets sources_1]
update_compile_order -fileset sources_1

# 综合
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed"
    exit 1
}
puts "SYNTH OK"

# 实现 + bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: implementation failed"
    exit 1
}

set bitfile [file join $build_dir proj_build.runs impl_1 top.bit]
if {[file exists $bitfile]} {
    puts "BITSTREAM OK: $bitfile"
} else {
    puts "ERROR: bitstream not found: $bitfile"
    exit 1
}

# 资源与时序摘要
open_run impl_1
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -file [file join $build_dir timing_summary.rpt]
puts "REPORTS: $build_dir"
exit 0
