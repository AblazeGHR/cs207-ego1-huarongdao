# ---------------------------------------------------------------------------
# add_sources.tcl
# 在 Vivado 中打开 proj.xpr 后，于 Tcl Console 执行：
#     source scripts/add_sources.tcl
# 即可把 rtl/、constrs/、sim/ 下的文件加入工程并设置顶层。
# ---------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

set rtl_files [glob -nocomplain [file join $root_dir rtl *.v]]
set sim_files [glob -nocomplain [file join $root_dir sim *.v]]
set xdc_file  [file join $root_dir constrs ego1.xdc]

if {[llength $rtl_files] == 0} {
    error "No RTL files found under $root_dir/rtl"
}
if {![file exists $xdc_file]} {
    error "Constraint file not found: $xdc_file"
}

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_file

if {[llength $sim_files] > 0} {
    add_files -fileset sim_1 -norecurse $sim_files
}

set_property top top [get_filesets sources_1]
if {[llength $sim_files] > 0} {
    set_property top tb_top [get_filesets sim_1]
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Added [llength $rtl_files] RTL files, 1 XDC, [llength $sim_files] simulation files."
puts "Top module: top"
