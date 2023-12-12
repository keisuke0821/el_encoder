# script
set ip_name "axi_gb_rotary"
create_project $ip_name . -force

# file
set proj_fileset [get_filesets sources_1]
add_files -norecurse -scan_for_includes -fileset $proj_fileset [list \
"axi_gb_rotary.v" \
"axi_gb_rotary_S00_AXI.v" \
"encoder_read.v" \
"pos_status.v" \
"rising_edge_ms.v" \
]
set_property "top" "axi_gb_rotary" $proj_fileset


# ip package

ipx::package_project -root_dir . -vendor kuhep -library user -taxonomy /kuhep
set_property name $ip_name [ipx::current_core]
set_property vendor_display_name {kuhep} [ipx::current_core]
ipx::save_core [ipx::current_core]


# interfaces

ipx::remove_all_bus_interface [ipx::current_core]
set memory_maps [ipx::get_memory_maps * -of_objects [ipx::current_core]]
foreach map $memory_maps {
    ipx::remove_memory_map [lindex $map 2] [ipx::current_core ]
}
ipx::save_core

# dev_clk

ipx::infer_bus_interface dev_clk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]

# S_AXI

ipx::infer_bus_interface {\
    s_axi_awvalid \
    s_axi_awaddr \
    s_axi_awprot \
    s_axi_awready \
    s_axi_wvalid \
    s_axi_wdata \
    s_axi_wstrb \
    s_axi_wready \
    s_axi_bvalid \
    s_axi_bresp \
    s_axi_bready \
    s_axi_arvalid \
    s_axi_araddr \
    s_axi_arprot \
    s_axi_arready \
    s_axi_rvalid \
    s_axi_rdata \
    s_axi_rresp \
    s_axi_rready} \
xilinx.com:interface:aximm_rtl:1.0 [ipx::current_core]

ipx::infer_bus_interface s_axi_aclk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface s_axi_aresetn xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]

set range 4
ipx::add_memory_map {s_axi} [ipx::current_core]
set_property slave_memory_map_ref {s_axi} [ipx::get_bus_interfaces s_axi -of_objects [ipx::current_core]]
ipx::add_address_block {axi_lite} [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]
set_property range $range [ipx::get_address_blocks axi_lite \
    -of_objects [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]]
ipx::associate_bus_interfaces -clock s_axi_aclk -reset s_axi_aresetn [ipx::current_core]
ipx::save_core [ipx::current_core]

# M AXIS

ipx::infer_bus_interface {\
    m_axis_tdata \
    m_axis_tlast \
    m_axis_tvalid \
    m_axis_tready} \
xilinx.com:interface:axis_rtl:1.0 [ipx::current_core]

ipx::associate_bus_interfaces \
    -busif m_axis -clock dev_clk \
[ipx::current_core]

ipx::save_core [ipx::current_core]
