#Outputs go in outputs directory
set ::output_dir "./outputs"
file mkdir $::output_dir

set ::ip_build_dir "./outputs/ip/build"
file mkdir $::ip_build_dir

set ::root_dir ".."

#Generate the VIO IP
create_project ip_project -in_memory -part xcku3p-ffvb676-2-e -ip
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0 -dir ${::ip_build_dir} -force

set_property -dict \
    [list \
        CONFIG.C_PROBE_OUT0_WIDTH {1} \
        CONFIG.C_PROBE_OUT1_WIDTH {1} \
        CONFIG.C_PROBE_OUT2_WIDTH {1} \
        CONFIG.C_PROBE_OUT3_WIDTH {1} \
        CONFIG.C_PROBE_OUT4_WIDTH {64} \
        CONFIG.C_PROBE_OUT5_WIDTH {64} \
        CONFIG.C_NUM_PROBE_OUT    {6} \
        CONFIG.C_NUM_PROBE_IN     {0} \
    ] \
    [get_ips vio_0]

generate_target {instantiation_template} [get_files vio_0.xci]
generate_target all [get_files  vio_0.xci]

close_project

#Build the project
create_project -part xcku3p-ffvb676-2-e -in_memory 

#Read the sources
read_ip -verbose ${::ip_build_dir}/vio_0/vio_0.xci
read_verilog -quiet [glob -nocomplain -directory $::root_dir/src   *.sv]
read_verilog -quiet [glob -nocomplain -directory $::root_dir/demo *.sv]

#Do the IP dance
upgrade_ip [get_ips]
set_property generate_synth_checkpoint false [get_files ${::ip_build_dir}/vio_0/vio_0.xci]
generate_target all [get_ips]
validate_ip -verbose [get_ips]

#Synthesize the design
synth_design \
    -top top \
    -flatten_hierarchy rebuilt 

write_checkpoint -force "${::output_dir}/post_synth.dcp"

source "constraints.xdc"

#Insert the ILA
#See the section "Using XDC Commands to Insert Debug Cores" in UG908
set debug_nets [lsort -dictionary [get_nets -hier -filter {mark_debug}]]
set n_nets [llength $debug_nets]

if { $n_nets > 0 } {
    create_debug_core u_ila_0 ila

    set_property C_DATA_DEPTH          1024  [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN           false [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN          false [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER         false [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES   0     [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL        false [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU     true  [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 1     [get_debug_cores u_ila_0]

    set_property port_width 1 [get_debug_ports u_ila_0/clk]
    connect_debug_port u_ila_0/clk [get_nets clk]

    set_property port_width $n_nets [get_debug_ports u_ila_0/probe0]
    connect_debug_port u_ila_0/probe0 $debug_nets
}

#Continue with implementation
opt_design
write_checkpoint -force "${::output_dir}/post_opt.dcp"

place_design -directive Explore
write_checkpoint -force "${::output_dir}/post_place.dcp"

phys_opt_design -directive AggressiveExplore
write_checkpoint -force "${::output_dir}/post_phys_opt.dcp"

route_design -directive Explore -tns_cleanup
write_checkpoint -force "${::output_dir}/post_route.dcp"

phys_opt_design -directive Explore
write_checkpoint -force "${::output_dir}/post_route_phys_opt.dcp"

#Reports
report_clocks -file "${::output_dir}/clocks.rpt"
report_timing_summary -file "${::output_dir}/timing.rpt"
report_utilization -file "${::output_dir}/utilization.rpt"

#Outputs
write_bitstream "${::output_dir}/image.bit" -force
write_debug_probes "${::output_dir}/probes.ltx" -force
