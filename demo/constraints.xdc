#Modify these to match your board. Only port needed is the clock.

create_clock -name sys_clk -period 10 [get_ports sys_clk_p]
set_property package_pin V7 [get_ports sys_clk_p]
set_property package_pin V6 [get_ports sys_clk_n]

