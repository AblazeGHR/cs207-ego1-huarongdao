## EGO1 (XC7A35T-1CSG324C) pin constraints
## 依据：EGo1 用户手册 v1.1 引脚表 + 课程 PDF 的 LED/数码管编号约定
## 约定：多 bit 输入/输出均“最左侧为最高位”

## ---------------------------------------------------------------------------
## Clock / reset / buttons
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports clk100]
create_clock -period 10.000 -name sys_clk [get_ports clk100]

set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports rst_btn]

## btn[4:0] = {S4, S3, S2, S1, S0}
set_property -dict { PACKAGE_PIN U4  IOSTANDARD LVCMOS33 } [get_ports {btn[4]}]
set_property -dict { PACKAGE_PIN V1  IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]

## ---------------------------------------------------------------------------
## Slide switches: sw[7] = 最左 SW0, sw[0] = 最右 SW7
## 棋子编号使用最左 4 个：sw[7:4] (SW0..SW3)
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN P5 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN P4 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN P3 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN P2 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN R2 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN M4 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN N4 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN R1 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]

## ---------------------------------------------------------------------------
## LEDs (active high)
## led[15:8] = D0..D7   (F6,G4,G3,J4,H4,J3,J2,K2)  左 -> 右
## led[7:4]  = D8..D11  (K1,H6,H5,J5)              左 -> 右
## led[3:0]  = D12..D15 (K6,L1,M1,K3)
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN F6 IOSTANDARD LVCMOS33 } [get_ports {led[15]}]
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN G3 IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN J4 IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN H4 IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN J3 IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN K1 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN H6 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN K6 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN M1 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN K3 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]

## ---------------------------------------------------------------------------
## 7-segment displays (common cathode, segment & digit enable active high)
## seg0 = left 4 digits, seg1 = right 4 digits
## seg[7:0] = {A,B,C,D,E,F,G,DP}
## seg_en[7] = 最左位 ... seg_en[0] = 最右位
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN B4 IOSTANDARD LVCMOS33 } [get_ports {seg0[7]}]
set_property -dict { PACKAGE_PIN A4 IOSTANDARD LVCMOS33 } [get_ports {seg0[6]}]
set_property -dict { PACKAGE_PIN A3 IOSTANDARD LVCMOS33 } [get_ports {seg0[5]}]
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports {seg0[4]}]
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports {seg0[3]}]
set_property -dict { PACKAGE_PIN B3 IOSTANDARD LVCMOS33 } [get_ports {seg0[2]}]
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports {seg0[1]}]
set_property -dict { PACKAGE_PIN D5 IOSTANDARD LVCMOS33 } [get_ports {seg0[0]}]

set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports {seg1[7]}]
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports {seg1[6]}]
set_property -dict { PACKAGE_PIN D3 IOSTANDARD LVCMOS33 } [get_ports {seg1[5]}]
set_property -dict { PACKAGE_PIN F4 IOSTANDARD LVCMOS33 } [get_ports {seg1[4]}]
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports {seg1[3]}]
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports {seg1[2]}]
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports {seg1[1]}]
set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports {seg1[0]}]

set_property -dict { PACKAGE_PIN G2 IOSTANDARD LVCMOS33 } [get_ports {seg_en[7]}]
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports {seg_en[6]}]
set_property -dict { PACKAGE_PIN C1 IOSTANDARD LVCMOS33 } [get_ports {seg_en[5]}]
set_property -dict { PACKAGE_PIN H1 IOSTANDARD LVCMOS33 } [get_ports {seg_en[4]}]
set_property -dict { PACKAGE_PIN G1 IOSTANDARD LVCMOS33 } [get_ports {seg_en[3]}]
set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports {seg_en[2]}]
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports {seg_en[1]}]
set_property -dict { PACKAGE_PIN G6 IOSTANDARD LVCMOS33 } [get_ports {seg_en[0]}]

## ---------------------------------------------------------------------------
## UART outputs
##   N2: Bluetooth BLE-CC41-A (current module not detected, kept for compatibility)
##   T4: onboard CP2102 USB-UART (FPGA TX)
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN N2 IOSTANDARD LVCMOS33 } [get_ports bt_tx]
set_property -dict { PACKAGE_PIN T4 IOSTANDARD LVCMOS33 } [get_ports uart_tx]

## ---------------------------------------------------------------------------
## Configuration
## ---------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
