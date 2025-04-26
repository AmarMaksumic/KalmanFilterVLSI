# Clock constraint onto 44.1 kHz
create_clock -period 22676.0 -name clk [get_ports clk]

# Input delay (example: 2 ns)
set_input_delay -clock clk 2.0 [get_ports x_in]

# Output delay (example: 3 ns)
set_output_delay -clock clk 3.0 [get_ports y_out]