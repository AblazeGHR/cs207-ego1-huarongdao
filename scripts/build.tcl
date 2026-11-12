# ---------------------------------------------------------------------------
# build.tcl
# 打开 proj.xpr 并加入源码后执行：
#     source scripts/build.tcl
# 依次完成综合、实现、生成 bitstream。
# ---------------------------------------------------------------------------

if {[llength [get_runs synth_1]] == 0} {
    error "synth_1 run not found; open proj.xpr first."
}

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed. Check the Vivado log."
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed. Check the Vivado log."
}

puts "Bitstream: [get_property DIRECTORY [get_runs impl_1]]/top.bit"
