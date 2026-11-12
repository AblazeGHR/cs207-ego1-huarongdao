# 只检测 JTAG 线是否连接，不下载任何东西。
open_hw
if {[catch {connect_hw_server} err]} {
    puts "NO_HW_SERVER: $err"
    exit 0
}
set targets [get_hw_targets]
puts "HW_TARGETS: $targets"
foreach t $targets {
    puts "TARGET: $t"
}
disconnect_hw_server
close_hw
exit 0
