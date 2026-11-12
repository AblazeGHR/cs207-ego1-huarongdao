# ---------------------------------------------------------------------------
# update_project.tcl
# 把 rtl/、constrs/、sim/ 加入仓库内的 proj.xpr 并保存。
# 用法（在 proj 目录下）：
#   vivado.bat -mode batch -source scripts/update_project.tcl
# 注意：运行前请关闭该工程的 GUI，避免工程被占用。
# ---------------------------------------------------------------------------

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set xpr_file   [file join $root_dir proj.xpr]

if {![file exists $xpr_file]} {
    error "Project not found: $xpr_file"
}

open_project $xpr_file

set rtl_files [glob -nocomplain [file join $root_dir rtl *.v]]
set sim_files [glob -nocomplain [file join $root_dir sim *.v]]
set xdc_file  [file join $root_dir constrs ego1.xdc]

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

close_project
puts "Project updated: $xpr_file"
exit 0
