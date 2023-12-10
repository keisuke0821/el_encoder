## Elevation encoder
# Start the project

# Modify this later
# This project is for ZyboZ7-20
set p_device "xc7z020clg400-1"
set p_board "digilentinc.com:zybo-z7-20:part0:1.2"

set sys_zynq 1
set project_name el_encoder
set lib_dirs ../

set project_system_dir "./$project_name.srcs/sources_1/bd/system"
create_project $project_name . -part $p_device -force
set_property board_part $p_board [current_project]

set_property ip_repo_paths $lib_dirs [current_fileset]
update_ip_catalog

create_bd_design "system"

############## Zynq
create_bd_cell -type ip -vlnv [get_ipdefs "*processing_system7*"] sys_ps7

# Board automation
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
-config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" }  \
[get_bd_cells sys_ps7]

# enable interrupt
set_property -dict [list \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1}] \
    [get_bd_cells sys_ps7]

set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0}\
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0}\
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0}\
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0}] \
[get_bd_cells sys_ps7]

# Instantiate AXI GB rotary
create_bd_cell -type ip -vlnv [get_ipdefs -name "*axi_gb_rotary*"] axi_gb_rotary

# Connect AXI GB rotary to CPU
connect_bd_net [get_bd_pins sys_ps7/FCLK_CLK0] [get_bd_pins axi_gb_rotary/dev_clk]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
-config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
Master {/sys_ps7/M_AXI_GP0} Slave {/axi_gb_rotary/s_axi} \
intc_ip {New AXI Interconnect} master_apm {0}}  \
[get_bd_intf_pins axi_gb_rotary/s_axi]


# AXI Stream FIFO
create_bd_cell -type ip -vlnv [get_ipdefs "*axi_fifo_mm_s*"] axi_fifo_mm_s
set_property -dict [list CONFIG.C_USE_TX_DATA {0} CONFIG.C_USE_TX_CTRL {0}] [get_bd_cells axi_fifo_mm_s]
connect_bd_intf_net [get_bd_intf_pins axi_gb_rotary/m_axis] [get_bd_intf_pins axi_fifo_mm_s/AXI_STR_RXD]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
-config { Clk_master {/sys_ps7/FCLK_CLK0 (50 MHz)} Clk_slave {Auto} Clk_xbar {/sys_ps7/FCLK_CLK0 (50 MHz)} \
Master {/sys_ps7/M_AXI_GP0} Slave {/axi_fifo_mm_s/S_AXI} \
intc_ip {/sys_ps7_axi_periph} master_apm {0}}  \
[get_bd_intf_pins axi_fifo_mm_s/S_AXI]

# AXI UART Lite
create_bd_cell -type ip -vlnv [get_ipdefs "*axi_uartlite*"] axi_uartlite
set_property -dict [list CONFIG.C_BAUDRATE {115200} CONFIG.PARITY {Even} CONFIG.C_USE_PARITY {1}] [get_bd_cells axi_uartlite]
apply_bd_automation \
    -rule xilinx.com:bd_rule:axi4 \
    -config { Clk_master {/sys_ps7/FCLK_CLK0 (50 MHz)} Clk_slave {Auto} Clk_xbar {/sys_ps7/FCLK_CLK0 (50 MHz)} Master {/sys_ps7/M_AXI_GP0} Slave {/axi_uartlite/S_AXI} intc_ip {/sys_ps7_axi_periph} master_apm {0}}  \
    [get_bd_intf_pins axi_uartlite/S_AXI]
make_bd_pins_external  -name uart [get_bd_pins axi_uartlite/rx]


# Interrupt
create_bd_cell -type ip -vlnv [get_ipdefs "*xlconcat*"] xlconcat
connect_bd_net [get_bd_pins axi_gb_rotary/interrupt] [get_bd_pins xlconcat/In0]
connect_bd_net [get_bd_pins axi_uartlite/interrupt] [get_bd_pins xlconcat/In1]
connect_bd_net [get_bd_pins xlconcat/dout] [get_bd_pins sys_ps7/IRQ_F2P]


# Interface pin
make_bd_pins_external  -name rot_a [get_bd_pins axi_gb_rotary/rot_a]
make_bd_pins_external  -name rot_b [get_bd_pins axi_gb_rotary/rot_b]
make_bd_pins_external  -name rot_z [get_bd_pins axi_gb_rotary/rot_z]
make_bd_pins_external  -name ex_sync [get_bd_pins axi_gb_rotary/ex_sync]

create_bd_port -dir O -type clk f_clk
connect_bd_net [get_bd_pins /sys_ps7/FCLK_CLK0] [get_bd_ports f_clk]
create_bd_port -dir O -type rst f_rstn
connect_bd_net [get_bd_ports f_rstn] [get_bd_pins rst_sys_ps7_50M/peripheral_aresetn]


save_bd_design
validate_bd_design

set_property synth_checkpoint_mode None [get_files  $project_system_dir/system.bd]
generate_target {synthesis implementation} [get_files  $project_system_dir/system.bd]
make_wrapper -files [get_files $project_system_dir/system.bd] -top


import_files -force -norecurse -fileset sources_1 $project_system_dir/hdl/system_wrapper.v
add_files -norecurse -fileset sources_1 [list \
    "el_encoder.xdc" \
    "system_top.v" \
    "sync_splitter.v"]
set_property top system_top [current_fileset]


# Synthesize
launch_runs synth_1
wait_on_run synth_1
open_run synth_1
report_timing_summary -file timing_synth.log

# Implementation
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
open_run impl_1
report_timing_summary -file timing_impl.log

# Make .sdk folder
file copy -force $project_name.runs/impl_1/system_top.sysdef noos/system_top.hdf
