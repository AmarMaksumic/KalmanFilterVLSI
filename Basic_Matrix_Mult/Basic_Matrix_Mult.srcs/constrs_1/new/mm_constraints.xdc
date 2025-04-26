# Clock constraint onto 50 kHz
create_clock -period 1000.0 -name clk [get_ports clk]

# Input delay (example: 2 ns)
set_input_delay -clock clk 2.0 [get_ports A]

# Input delay (example: 2 ns)
set_input_delay -clock clk 2.0 [get_ports B]

# Output delay (example: 3 ns)
set_output_delay -clock clk 3.0 [get_ports C]