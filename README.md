# Kalman Filter Design

### by <img src="README_resources/AmarRed.png" alt="signature" width="30"/>

## Intro
This repository gives a walk through on the complete design process of a Kalman Filter on an FPGA for various purposes. This report is divided into several sections:

0. [Necessary software and setup](#necessary-software-and-setup)
1. [Filter Design](#filter-design)
2. [Filter Architecture](#filter-architecture)
    * Overview
    * Matrix Multiplication
    * Matrix Addition and Subtraction
    * Matrix Transpose
    * Matrix Inversion
3. [Filter Implementation and Testing](#filter-implementation-and-testing)
    * Description of how the filter will be tested, and what criteria will be measured:
        * performance
        * power
        * critical path timing
        * space/resource usage on FPGA will be analyzed
4. [Pipelined FIR Filter Results](#pipelined-fir-filter-results)
5. [L2 Parallel FIR Filter Results](#l2-parallel-fir-filter-results)
6. [L3 Parallel FIR Filter Results](#l3-parallel-fir-filter-results)
7. [Pipelined, L3 Parallel FIR Filter Results](#pipelined-l3-parallel-fir-filter-results)
8. [Comparison of Filters and Conclusion](#comparison-of-filters-and-conclusion)
9. [Resources](#resources)

> [!NOTE]  
> If you do not know what an FIR filter is or the principles of pipelining and paralelization in DSP design, I would recommend touching up on that first. Some links are provided in the [Resources](#resources) section.

## Necessary software and setup

- [AMD Vivado](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html)




# WIP STILL


## Filter Design

First, we will start by selecting the operating frequency for this FIR Filter. As we are only given a general transition region (0.2 $\pi$ to 0.23 $\pi$ rad/sample), I will assume that it is fair game to arbitrarily choose the sampling frequency for this. As such, this filter will be operating inside of an audio filtering device of CD quality (sampling rate = 44.1kHz). It will remove high frequencies above the pass band range of 4.41 kHz to 5.07 kHz from this audio file; so things like high pitched whines or electric noise. 

> [!NOTE]  
> In design of the basic filter, the sampling frequency is not super important. It does not affect the coefficients for the filter itself assuming we preserve the same general transition region across all normalized frequencies. However, for implementing and testing the filter later, it will be important for determining the clock of the filter and generation of our test signal.

Moving forward, the next step is to compute the coefficients for the FIR filter. To do this, I developed a MATLAB script that uses Parks-McClellan algorithm to generate the filter coefficients. The following parameters were provided to the algorithm:

* Number of Taps => 102
* Start Frequency (Normalized) => 0
* Passband Edge Frequency (Normalized) => 0.2
* Stopband Edge Frequency (Normalized) => 0.23
* End Frequency (Normalized) => 1
* Ampltiude Vector
    * Full attenuation from start to passband edge, no attenuation after stopband.
* Stopband Attenuation Weighting -> -80dB

Most parameters in this list are taken directly from the project description file. One element which I did change was the number of taps. In order to work with the parallelized filters later, I needed the number of taps to be a multiple of 2 and 3, but also greater than or equal to 100. 102 taps is the smallest count which fits these requirements.

From here, the built-in MATLAB function derives our filter coefficients. However, they are in floating point representation. For our implementation, we prefer fixed point representation as it is easier to perform integer math than floating point math on hardware. As such, we will convert to fixed point representation and then quantize the data. 

I used MATLAB's built in ```fi``` function to convert from floating point representatio to fixed point. When quantizing the data, I tried using 16-bit vs 32-bit signed representation. Below are my graphs showing the results of each:

<div align="center">
  <img src="README_resources/16bitfilter.png" width="500">
  <br>
  <p>Figure 1: 16-bit quantizied 102-tap filter</p>
</div>

<br>

<div align="center">
  <img src="README_resources/24bitfilter.png" alt="" width="500">
  <br>
  <p>Figure 2: 24-bit quantizied 102-tap filter</p>
</div>

<br>

<div align="center">
  <img src="README_resources/32bitfilter.png" alt="" width="500">
  <br>
  <p>Figure 3: 32-bit quantizied 102-tap filter</p>
</div>

<br>

The 16-bit representation is more space efficient and maintains the integrity of the signal before the stop band. However, after the stop band, there are extreme attenuations that sometimes have the signal go above -80dB. While the 32-bit representation will need more space and computing resources, it is more precise. The 24-bit representation gives the best of both worlds, and is within the range traditionally used for audio processing[^1]. While it has some attenuation differences after the stopband compared to the original model, all attenuations are kept bellow -80dB.

The filter coefficients are then stored into ```.mem``` files, with [decimal](fir_coeffs_decimal.mem) and [binary](fir_coeffs_binary.mem) representations. The mem files can later be loaded into the System Verilog code for the FIR filters.

## Filter Architecture

In this section, I will go over the high-level design for the four filters created.

### Pipelined FIR
<div align="center">
  <img src="README_resources/pipelinefirfilter.jpg" alt="" width="500">
  <br>
  <p>Figure 4: Vertically Pipelined FIR filter[^2] </p>
</div>

<br>

To design the pipelined filter, I simply added delay blocks onto each stage of the accumulator line of the filter[^2]. For future reference, I will call this vertical pipelining of the filter. This optimization reduced the critical path to the time of one addder plus time of one multiplier. For this to work, delay blocks must also be added onto the delay line, essentially doubing the delay of each step. 

An alternative solution is to pipeline between the adders and multipliers. For future reference, I will call this horizontal pipelining of the filter. However, given that the input and output are registers, this would make the critical path 102 (the number of taps) multiplied by the time for one adder. This is a lot worse of a critical path than the proposed solution above, assuming that a multiplication operation does not take much longer than an addition (i.e. 8ns vs 20ns).

I did experiment with combining both methods above, but ran into issues with combining horizontal direction and vertical direction pipelinig. In addition, this introduced extreme latency issues due to the number of delay blocks between ```x(n)``` and ```y(n)```. As such, I went with only vertical pipelining shown with red blocks in figure 4.

### L2 Parallel FIR
<div align="center">
  <img src="README_resources/l2firfilter.png" alt="" width="500">
  <br>
  <p>Figure 5: 2-Parallel Reduced-Complexity Fast FIR filter[^3]</p>
</div>

<br>

To design the 2-Parallel Reduced-Complexity Fast filter, I followed the slides from Parhi's Chapter 9 lecture[^3], and took the design from there. This requires the generation of two sub filters, H0 and H1, with tap size of N/2, so 51 taps in our case. We split the coefficients up in an even-odd fashion (i.e. H0 = {h0, h2, h4, etc.} and H1 = {h1, h3, h5, etc.}). We generate the combined filter H0+H1 by combinging the coefficients at each index (i.e. H0+H1 = {h0+h1, h2+h3, h4+h5, etc.})/ Now that we have the sub filters, all that is needed is to copy the implementation provided by Parhi. Note that each "sub-filter" will be a non-pipelined filter.

### L3 Parallel FIR
<div align="center">
  <img src="README_resources/l3firfilter.png" alt="" width="500">
  <br>
  <p>Figure 6: 3-Parallel Fast FIR filter[^3]</p>
</div>

<br>

Similar process to the 2-Parallel Reduced-Complexity Fast filter, but make three sub filters (H0, H1, H2) instead of taps N/3 => 34, and repeat the same process for combining and implementing.

### Pipelined, L3 Parallel FIR

<div align="center">
  <img src="README_resources/l3firfilterpiped.png" alt="" width="500">
  <br>
  <p>Figure 7: 3-Parallel Optimal Pipelined Fast FIR filter</p>
</div>

<br>

Similar process to the 3-Parallel Reduced-Complexity Fast filter, but use a pipelined filter within each "sub-filter." Did not pipeline the input or output recommputation as worth critical path is 3*adder, which is less time than adder+multiplication. There would be no critical path benefit, and we would increase computation time by 3 cycles (one pipeline on input, two pipeline on output in image shown above).

## Filter Implementation and Testing

### Implementation

All filter's were developed in AMD's Vivado software using System Verilog. ```.mem``` files are used to store coefficients, and to also store input data for testbench files. There are four folders above prefixed with "FIR," each of which contain implementation for the four filters mentioned in the previous section. Link to the system verilog files are listed below:

* Pipelined FIR [FIR_Pipelined]
    * Implementation: [fir_filter.sv](FIR_Pipelined\FIR_Pipelined.srcs\sources_1\new\fir_filter.sv)
    * Testbench: [fir_filter_tb.sv](FIR_Pipelined\FIR_Pipelined.srcs\sim_1\new\fir_filter_tb.sv)
* L2 Parallel FIR [FIR_L2]
    * Implementation: [fir_filter.sv](FIR_L2\FIR_L2.srcs\sources_1\new\fir_filter.sv), [l2_wrapper.sv](FIR_L2\FIR_L2.srcs\sources_1\new\l2_wrapper.sv)
    * Testbench: [fir_filter_tb.sv](FIR_L2\FIR_L2.srcs\sim_1\new\fir_filter_tb.sv)
* L3 Parallel FIR [FIR_L3]
    * Implementation: [fir_filter.sv](FIR_L3\FIR_L3.srcs\sources_1\new\fir_filter.sv), [l3_wrapper.sv](FIR_L3\FIR_L3.srcs\sources_1\new\l3_wrapper.sv)
    * Testbench: [fir_filter_tb.sv](FIR_L3\FIR_L3.srcs\sim_1\new\fir_filter_tb.sv)
* Pipelined, L3 Parallel FIR [FIR_Pipelined_L3]
    * Implementation: [fir_filter.sv](FIR_Pipelined_L3\FIR_Pipelined_L3.srcs\sources_1\new\fir_filter.sv), [l3_wrapper.sv](FIR_Pipelined_L3\FIR_Pipelined_L3.srcs\sources_1\new\l3_wrapper.sv)
    * Testbench: [fir_filter_tb.sv](FIR_Pipelined_L3\FIR_Pipelined_L3.srcs\sim_1\new\fir_filter_tb.sv)

Each FIR filter processes a 16-bit input signal. The filter coefficients are 24-bit, as configured earlier. To maintain precision during filtering, each input sample is multiplied by a 24-bit coefficient, producing a 40-bit intermediate result (16-bit × 24-bit multiplication). Since multiple taps contribute to the final output, these 40-bit products are accumulated in a 40-bit register. To ensure the output remains in a 16-bit format, a 24-bit right shift is applied to remove excess precision and scale the result appropriately. This final step helps mitigate quantization effects while preserving signal integrity.

For implementing the parallelized filters, I made a system verilog file with a basic, non-pipelined filter implementation. From here, I made a wrapper system verilog file to create instances of these filters as needed and use them in the higher level DFGs from earlier. For the pipelined L3 parallelized filter, I replace the basic, non-pipelined filter implementation with the pipelined filter from ```Pipelined FIR```. To support this, the coefficients file is separated as needed for h0, h1, h0+h1, etc. sub-filters for parallelization using the scripts in ```coeff_splitter```.

### Test Signal
For the testbenches to work, they require an input signal. This input signal is generated using the script [wave_gen.py](wave_gen.py). This script has a function ```sine_wave_sweep``` which takes in the following and generates a trajectory for a logarithmically increasing sine wave:

* File name
* Start frequency
* End frequency
* Number of Steps (for generating the number of frequencies in logspace)
* Samples per Frequency (for number of sample points per frequency in logspace)
* Clock cycle in ns

An input wave form sweeping 500Hz to 41.1kHz with 50 steps and 200 samples per frequencies is provided in the [input.mem](input.mem) file. 

> [!NOTE]  
> This file is intended to work with filters sampling at 44.1 kHz. If you are using a different sampling rate, you will need to produce a new file using the linked python script.

### Testing criteria (and how to derive)
Two schematics and Four criteria will be tested for:
* Filter Schematic
    * Question: What does our filter schematic look like? Does it match our design schematic?
    * Run: n the flow navigator run "RTL Analysis," then select "Schematic" under "Open Elaborated Design" in the "RTL Analysis" dropdown.
* Device Layout on FPGA
    * Question: What does our filter look like on the FPGA? The white line represents the critical path.
    * Run: In the flow navigator, run "Implementation." Device layout should open up after implementation is complete.
* Behavioral Simulation
    * Question: How does the filter respond to the input signal?
    * Run: In the flow navigator left-click "Run Simulation." A window will show up called "Untitled." Click on the "Zoom to Fit" icon (four arrows pointing away from each other). Right-click on ```x_in``` and ```y_out``` signals to set "Waveform Style" to "Analog" and "Radix" to "Signed Decimal."
> [!NOTE]  
> You may need to change the simulation time to fit the full plot. To do this, before left-clicking "Run Simulation," right-click "Run Simulation" instead and select "Simulation Settings." Under "Simulation -> Simulation" set "xsim.simulate.runtime*" to your desired runtime. In this case, I am using 200ms
* Timing
    * Question: What is critical path of the filter?
    * Run: To find this, we run the command ```report_timing -delay_type max -path_type full``` in the tcl terminal. This will return a report with the path offending the lowest "slack" time. The slack time is the difference between the clock cycle and critical path. To find the critical path from this, we look for the "data path delay."
* Power
    * Question: How many watts does the filter consume? What is the distribution of power consumption among components?
    * Run: In the flow navigator, run "Implementation." After the implementation completes, in the console select "Power."
* Area / Resource Utilization
    * Question: How many resources on the FPGA are used? Rough conversion to area using this equation: $A_{\text{FPGA}} \approx (0.0002 \times U_{\text{LUT}}) + (0.0001 \times U_{\text{FF}}) + (0.03 \times U_{\text{DSP}}) + (0.02 \times U_{\text{IO}})$ with the following sizes arbitrarily chosen by ChatGPT: 
    * | Resource | mm^2 |
      |----------|-------:|
      | LUTs     | 0.0002 |
      | FFs      | 0.0001 |
      | DSPs     | 0.03   |
      | IOs      | 0.02   |
    * Run: In the flow navigator, run "Implementation." After the implementation completes, in the console select "Utilization."

## Pipelined FIR Filter Results

### Circuit Schematic

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined/rtlschem.png" alt="" width="1000">
  <br>
  <p>Figure 8: Pipelined FIR Filter RTL Schematic</p>
</div>

<br>

This schematic has been reduced to only 3 taps, but it looks like this implementation follows the design proposed in [Pipelined FIR](#pipelined-fir)

### Device Layout on FPGA

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined/device.png" alt="" height="500">
  <br>
  <p>Figure 9: Pipelined FIR Filter on FPGA</p>
</div>

<br>

No major comments. Resource utilization from this device layout seems minimal, and the critical path spans the whole device. However, it looks like a small operation/data transfer that could consist of a single adder and multiplier. So overall, the impact is not that large other than device static times for this movement.

### Behavioral Sim

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined/behavioralsim.png" alt="" width="1000">
  <br>
  <p>Figure 10: Pipelined FIR Filter Behavioral Sim</p>
</div>

<br>

It is evident that the filter is operating as intended. In the beginning, we can see the three large pulses before the pass band, and then quickly after that we get attenuated response from the filter given the input signal. As the input file is from logarithmic scale, the testing output looks compressed towards the right side compared to the linear scaled MATLAB graphs from the beginning. 

There is a pretty significant delay of about 204 clock cycles before the filter starts outputting data. This is due to the doubly pipelined delay line. Thus, latency with this solution is pretty high.

### Timing

```
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
| Date         : Tue Mar 18 21:00:03 2025
| Host         : Amars-XPS running 64-bit major release  (build 9200)
| Command      : report_timing -delay_type max -path_type full
| Design       : fir_filter
| Device       : 7k70t-fbv676
| Speed File   : -1  PRODUCTION 1.12 2017-02-17
| Design State : Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Timing Report

Slack (MET) :             22659.553ns  (required time - arrival time)
  Source:                 accumulator_pipeline_reg[101]/CLK
                            (rising edge-triggered cell DSP48E1 clocked by clk  {rise@0.000ns fall@11338.000ns period=22676.000ns})
  Destination:            y_out[3]
                            (output port clocked by clk  {rise@0.000ns fall@11338.000ns period=22676.000ns})
  Path Group:             clk
  Path Type:              Max at Slow Process Corner
  Requirement:            22676.000ns  (clk rise@22676.000ns - clk rise@0.000ns)
  Data Path Delay:        8.663ns  (logic 2.852ns (32.923%)  route 5.811ns (67.077%))
  Logic Levels:           1  (OBUF=1)
  Output Delay:           3.000ns
  Clock Path Skew:        -4.750ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    0.000ns = ( 22676.000 - 22676.000 ) 
    Source Clock Delay      (SCD):    4.750ns
    Clock Pessimism Removal (CPR):    0.000ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock clk rise edge)        0.000     0.000 r  
                         propagated clock network latency
                                                      4.750     4.750    
    DSP48_X0Y79          DSP48E1                      0.000     4.750 r  accumulator_pipeline_reg[101]/CLK
    DSP48_X0Y79          DSP48E1 (Prop_dsp48e1_CLK_P[26])
                                                      0.383     5.133 r  accumulator_pipeline_reg[101]/P[26]
                         net (fo=1, routed)           5.811    10.944    y_out_OBUF[3]
    T24                  OBUF (Prop_obuf_I_O)         2.469    13.414 r  y_out_OBUF[3]_inst/O
                         net (fo=0)                   0.000    13.414    y_out[3]
    T24                                                               r  y_out[3] (OUT)
  -------------------------------------------------------------------    -------------------

                         (clock clk rise edge)    22676.000 22676.000 r  
                         propagated clock network latency
                                                      0.000 22676.000    
                         clock pessimism              0.000 22676.000    
                         clock uncertainty           -0.035 22675.965    
                         output delay                -3.000 22672.965    
  -------------------------------------------------------------------
                         required time                      22672.967    
                         arrival time                         -13.414    
  -------------------------------------------------------------------
                         slack                              22659.553
```

<br>

The critical path per the report is 8.663ns on the FPGA. A majority of this time (about 5.811ns) is due to the physical route that is taken on the FPGA. The logic only takes 2.852ns. We can also see that this occurred on the accumulator pipeline @ tap 101. My implementation handles multiplying the current tap by its coefficient and adding to the previous accumulations within this step/region:

    accumulator_pipeline[j] <= (accumulator_pipeline[j-1] + delay_pipeline[2*(j-1)+1] * coeffs[j]);

This location of the critical path aligns with where I would expect the critical path to be.

### Power

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined/power.png" alt="" width="500">
  <br>
  <p>Figure 11: Pipelined FIR Filter Power</p>
</div>

<br>

The total on-chip power shown is about 0.081 Watts, which is very good. Diging deeper it is clear that most power is consumed from device statics. After that, device I/O takes up the most power. Other components which are integral to the algorithm itself do not take up that much power in comparison to the I/O and statics. Choosing to go with only a 16-bit input and 24-bit coefficient size has definitely helped to save on power consumption; which will also hold true for the other implementations.

### Area / Resource Utilization

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined/util.png" alt="" width="500">
  <br>
  <p>Figure 12: Pipelined FIR Filter Resource Utilization</p>
</div>

<br>

Using our equation from above, we derive: $A_{\text{FPGA}} \approx (0.0002 \times 0) + (0.0001 \times 3232) + (0.03 \times 102) + (0.02 \times 34) = 4.0632$ mm^2

## L2 Parallel FIR Filter Results

### Circuit Schematic

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/rtlschem.png" alt="" width="1000">
  <br>
  <p>Figure 13: L2 Parallel FIR Filter RTL Schematic, High-Level</p>
</div>

<br>

The high-level schematic exactly replicates the proposed implementation from earlier. It is interesting to see how similar the DFGs can be to the in-real-life implementation of DSP designs.

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/rtlschem2.png" alt="" width="1000">
  <br>
  <p>Figure 14: L2 Parallel FIR Filter RTL Schematic, Low-Level</p>
</div>

<br>

Inside any of the ```fir_filter``` in the high-level diagram, we can see the operation of the non-pipelined FIR filter. This looks as expected, and it will be interesting to see the effects of this non-pipelined implementation in the timing analysis later

### Device Layout on FPGA

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/device.png" alt="" height="500">
  <br>
  <p>Figure 15: L2 Parallel FIR Filter on FPGA</p>
</div>

<br>

In comparison to the pipelined FIR filter, we can immediately see two things:

1. Higher resource utilization.
2. Much more dense and longer critical path.

From this analysis, it is safe to say that we'll see a big increase in silicon usage and critical path time. I will assume this critical path is that of all the adders on the accumulation path; none of which are pipelined.

### Behavioral Sim

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/behavioralsim.png" alt="" width="1000">
  <br>
  <p>Figure 16: L2 Parallel FIR Filter Behavioral Sim</p>
</div>

<br>

It is evident that the filter is operating as intended on both inputs/outputs. In the beginning, we can see the three large pulses before the pass band, and then quickly after that we get attenuated response from the filter given the input signal. As the input file is from logarithmic scale, the testing output looks compressed towards the right side compared to the linear scaled MATLAB graphs from the beginning. 

There is a small delay of about 51 clock cycles before the filter starts outputting data. In addition, this filter completes the operation in about half the time of the pipelined FIR filter. Granted, both filter's have lots of slack time given their low operating frequency.

### Timing

I have linked the output file [here](TEST_RESULTS/FIR_L2/timing.txt) for the timing results, as it is pretty large. Just like the file size, the critical path for this filter is huge in comparison to the pipelined FIR filter from last test: standing at 80.171ns. This time around, the logic delay hinders performance more than the route delay. Due to the non-pipelined accumulator line, the logic delay is 74.571ns. To improve this, it may be worthwhile to pipeline the individual FIR filters, or to reduce the size of the filters by reducing the number of taps through parallelization.

### Power

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/power.png" alt="" width="500">
  <br>
  <p>Figure 17: L2 Parallel FIR Filter Power</p>
</div>

<br>

The total on-chip power shown is about 0.081 Watts, which is very good. Diging deeper it is clear that most power is consumed from device statics. After that, device DSP takes up the most power. I/O usage is decently low given the doubled number of inputs and outputs. However, since there is 1.5x "the amount of FIR filter" now (3 half-tap filters) along with some other logic on the very input and output of the parallelized setup, it makes sense that there has been an extreme increase in usage of DSP units and power consumption from said DSP units.

### Area / Resource Utilization

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/util.png" alt="" width="500">
  <br>
  <p>Figure 18: L2 Parallel FIR Filter Resource Utilization</p>
</div>

<br>

Using our equation from above, we derive: $A_{\text{FPGA}} \approx (0.0002 \times 49) + (0.0001 \times 2416) + (0.03 \times 153) + (0.02 \times 114) = 7.1214$ mm^2

It is interesting to note that there are almost exactly 50% more DSP units used, which builds off the analysis from power where we have 1.5x "the amount of FIR filter" now. There is a reduction in FF units, most likely due to no pipelining and thus fewer delayblocks. Interestingly, there is a 3.3x increase in the number of I/O usage, which is tough for me to explain. My only stipulation is that it is considering the inner I/O of the system verilog wrapping of the three FIR filters for H0, H1, and H0+H1.

<div align="center">
  <img src="TEST_RESULTS/FIR_L2/util2.png" alt="" width="500">
  <br>
  <p>Figure 19: L2 Parallel FIR Filter Resource Utilization</p>
</div>

From the above report, we can also see that the resource utilization across the three filters is almost identical.

<br>

## L3 Parallel FIR Filter Results

### Circuit Schematic

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/rtlschem.png" alt="" width="1000">
  <br>
  <p>Figure 20: L3 Parallel FIR Filter RTL Schematic, High-Level</p>
</div>

<br>

The high-level schematic exactly replicates the proposed implementation from earlier. The per-filter schematic is similar as with the L2 filter, with the only difference being the number of taps going down from N/2 to N/3.

### Device Layout on FPGA

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/device.png" alt="" height="500">
  <br>
  <p>Figure 21: L3 Parallel FIR Filter on FPGA</p>
</div>

<br>

In comparison to the L2 Parallel FIR filter, we can immediately see two things:

1. Higher resource utilization.
2. Equally dense, but shorter critical path.

From this analysis, it is safe to say that we'll see a big increase in silicon usage, but decrease in critical path time compared to the L2 Parallel FIR filter. However, both silicon usage and critical path time will be higher than with the pipelined implementation. I will assume this critical path is that of all the adders on the accumulation path; none of which are pipelined.

### Behavioral Sim

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/behavioralsim.png" alt="" width="1000">
  <br>
  <p>Figure 22: L3 Parallel FIR Filter Behavioral Sim</p>
</div>

<br>

It is evident that the filter is operating almost as intended on all three inputs/outputs. In the beginning, we can see the three large pulses before the pass band, and then quickly after that we get attenuated response from the filter given the input signal. However, now we have some lack of attenuation on the lower frequency end. One of my theories as to why this occurs is because of the extreme segmentation of the filtering now, as it is parallelized into three levels. In addition, this could potentially be due to the use of 24-bit coefficients instead of 32-bit coefficients, allowing the effects of quantization of such a segmented signal to start showing.

There is a small delay of about 34 clock cycles before the filter starts outputting data. In addition, this filter completes the operation in about a third of the time of the pipelined FIR filter. Granted, both filter's have lots of slack time given their low operating frequency.

### Timing

I have linked the output file [here](TEST_RESULTS/FIR_L3/timing.txt) for the timing results. The critical path for this filter is decently large at 56.794ns, with the logic delay hindering performance more than the route delay. Due to the non-pipelined accumulator line, the logic delay is 50.536ns. To improve this, it may be worthwhile to pipeline the individual FIR filters. Further reducing the size of the filters by parallelizing even more may lead to poor output quality like I have ran into.

### Power

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/power.png" alt="" width="500">
  <br>
  <p>Figure 23: L3 Parallel FIR Filter Power</p>
</div>

<br>

The total on-chip power shown is about 0.081 Watts, which is very good. Diging deeper it is clear that most power is consumed from device statics. After that, device DSP takes up the most power. I/O power usage is also pretty high, sitting at 30% of dynamic power. Given that we have 6 FIR filters wrapped into this implementation, the additional I/O strain onto communicating with them is most likely leading to this increase of I/O power usage.

### Area / Resource Utilization

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/util.png" alt="" width="500">
  <br>
  <p>Figure 24: L3 Parallel FIR Filter Resource Utilization</p>
</div>

<br>

Using our equation from above, we derive: $A_{\text{FPGA}} \approx (0.0002 \times 230) + (0.0001 \times 3200) + (0.03 \times 204) + (0.02 \times 170) = 9.886$ mm^2

Like before, there is a reasonable increase in the DSP units. This time, we have 6 * (N/3) DSPs, which is 204 DPS. the amount of other resources also increased by reasonable amounts and aligns to theories for I/O proposed in the L2 Parallel analysis.

<div align="center">
  <img src="TEST_RESULTS/FIR_L3/util2.png" alt="" width="500">
  <br>
  <p>Figure 25: L3 Parallel FIR Filter Resource Utilization</p>
</div>

From the above report, we can also see that the resource utilization across the six filters is almost identical.

<br>

## Pipelined, L3 Parallel FIR Filter Results

### Circuit Schematic

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/rtlschem.png" alt="" width="1000">
  <br>
  <p>Figure 26: Pipelined L3 Parallel FIR Filter RTL Schematic, High-Level</p>
</div>

<br>

The high-level schematic exactly replicates the proposed implementation from earlier. The per-filter schematic is similar with the pipelined filter, with the only difference being the number of taps going down from N to N/3.

### Device Layout on FPGA

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/device.png" alt="" height="500">
  <br>
  <p>Figure 27: Pipelined L3 Parallel FIR Filter on FPGA</p>
</div>

<br>

In comparison to the L3 Parallel FIR filter, we can immediately see two things:

1. Higher resource utilization.
2. Less dense, and shorter critical path.

From this analysis, it is safe to say that we'll see a big increase in silicon usage, primarily from increase in registers/flip flops for the delay blocks. However, the critical path will be much shorter, either equal to or slightly greater than the pipelined filter critical path.

### Behavioral Sim

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/behavioralsim.png" alt="" width="1000">
  <br>
  <p>Figure 28: Pipelined L3 Parallel FIR Filter Behavioral Sim</p>
</div>

<br>

It is evident that the filter is operating almost as intended on all three inputs/outputs. In the beginning, we can see the three large pulses before the pass band, and then quickly after that we get attenuated response from the filter given the input signal. However, now we have some lack of attenuation on the lower frequency end. One of my theories as to why this occurs is because of the extreme segmentation of the filtering now, as it is parallelized into three levels. In addition, this could potentially be due to the use of 24-bit coefficients instead of 32-bit coefficients, allowing the effects of quantization of such a segmented signal to start showing.

There is a small delay of about 68 clock cycles before the filter starts outputting data. In addition, this filter completes the operation in about a third of the time of the pure-pipelined FIR filter. Granted, both filter's have lots of slack time given their low operating frequency.

### Timing

I have linked the output file [here](TEST_RESULTS/FIR_Pipelined_L3/timing.txt) for the timing results. The critical path for this filter is relatively small at 11.881ns, with the logic delay being smaller than the route delay. The logic delay is 4.324ns, with the route delay being 7.668ns. From the contents of the output file, it looks like this occurs after the output of the H-filters, and along the recomposition into ```y_out_1```. In this path, there are multiplier adders without any pipelining on them. There is definitely some way to pipeline this output to optimize it, but that comes at the cost of adding more cycles. As such, I think this pipelining is not necessary as it is close to the time of one adder plus one multiplier (the critical path inside of the pipelined FIR filter).

### Power

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/power.png" alt="" width="500">
  <br>
  <p>Figure 29: Pipelined L3 Parallel FIR Filter Power</p>
</div>

<br>

The total on-chip power shown is about 0.081 Watts, which is very good. Diging deeper it is clear that most power is consumed from device statics. After that, device DSP takes up the most power. I/O power usage is also pretty high, sitting at 25% of dynamic power. Given that we have 6 FIR filters wrapped into this implementation, the additional I/O strain onto communicating with them is most likely leading to this increase of I/O power usage.

### Area / Resource Utilization

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/util.png" alt="" width="500">
  <br>
  <p>Figure 30: Pipelined L3 Parallel FIR Filter Resource Utilization</p>
</div>

<br>

Using our equation from above, we derive: $A_{\text{FPGA}} \approx (0.0002 \times 230) + (0.0001 \times 6368) + (0.03 \times 204) + (0.02 \times 170) = 10.2028$ mm^2

Like before, there is a reasonable amount of DSP units as we have 6 * (N/3) DSPs, which is 204 DPS. the amount of other resources also increased by reasonable amounts, with flip-flop count almost doubling because of pipelining, and aligns to theories for I/O proposed in the L2 Parallel analysis.

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L3/util2.png" alt="" width="500">
  <br>
  <p>Figure 31: Pipelined L3 Parallel FIR Filter Resource Utilization</p>
</div>

From the above report, we can also see that the resource utilization across the six filters is almost identical; minus some trading of SLICE LUTs, Slice Registers, Slice, and LUT for logic across the filters.

<br>

## Comparison of Filters and Conclusion

To compare the different FIR filter implementations, we analyze key resource utilization metrics and performance characteristics. The table below provides a summary of the resource usage for each filter.

| Filter Type                   | LUT  |  FF  | DSP  | IO  | Area (mm²) | Critical Path (ns) | Logic Delay | Cycle Time (clk) | Max clk (MHz) | Power (W) |
|-------------------------------|------|------|------|-----|------------|--------------------|-------------|------------------|---------------|-----------|
| **Pipelined FIR**             |    0 | 3232 |  102 |  34 |     4.0632 |              8.663 |       2.852 |              204 |         115.4 |     0.081 |
| **L2 Parallel FIR**           |   49 | 2416 |  153 | 114 |     7.1214 |             80.171 |      74.571 |               51 |          12.5 |     0.081 |
| **L3 Parallel FIR**           |  230 | 3200 |  204 | 170 |      9.886 |             56.794 |      50.536 |               34 |          17.6 |     0.081 |
| **Pipelined L3 Parallel FIR** |  230 | 6368 |  204 | 170 |    10.2028 |             11.881 |       4.324 |               68 |          84.2 |     0.081 |

As seen in the table above, with variations in parallelization along with pipelining implementation, we can derive FIR filters with various critical paths and latency. It seems that for improved latency, it is better to perform parallelization since it reduces the number of clock cycles needed for an output. However, to have the best throughput, it is better to pipeline since it reduces the critical path. Power consumption was the same across all filters, although further simulation should be done to support this claim as it seems odd. 

Given better fixed point quantization or maybe an increase in taps, the Pipelined L3 Parallel FIR filter could excel in this scenario. It would provide us with the best of both throughput and latency. However, this does come with the tradeoff of resource utilization and area. An abundance of flip flops and DSP units were used to support this configuration, and it had the largest potential silicone area. In addition, it also had some weird output behavior on the tail end of the frequency response. This could be attributed to the taps and quantizied coefficients that I have developed, but I am not sure. More study into the effect of the number of taps and the scale of the quantizied coefficients will need to be done to support that (i.e. 24-bit vs 32-bit).

This got me thinking that with the FIR filter coefficients I have developed, a pipelined L2 Parallel FIR filter might excel. It could give us the best of throughput, latency, area, and also precision. The behavioral simulation and timing analysis is attached bellow, and updated table of information right after:

<div align="center">
  <img src="TEST_RESULTS/FIR_Pipelined_L2/behavioralsim.png" alt="" width="1000">
  <br>
  <p>Figure 32: Pipelined L2 Parallel FIR Filter Behavioral Simulation</p>
</div>

<br>


```
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
| Date         : Wed Mar 19 05:24:19 2025
| Host         : Amars-XPS running 64-bit major release  (build 9200)
| Command      : report_timing -delay_type max -path_type full
| Design       : l2_wrapper
| Device       : 7k70t-fbv676
| Speed File   : -1  PRODUCTION 1.12 2017-02-17
| Design State : Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Timing Report

Slack (MET) :             22659.512ns  (required time - arrival time)
  Source:                 y2k_pipeline_reg[2]/C
                            (rising edge-triggered cell FDRE clocked by clk  {rise@0.000ns fall@11338.000ns period=22676.000ns})
  Destination:            y_out_0[16]
                            (output port clocked by clk  {rise@0.000ns fall@11338.000ns period=22676.000ns})
  Path Group:             clk
  Path Type:              Max at Slow Process Corner
  Requirement:            22676.000ns  (clk rise@22676.000ns - clk rise@0.000ns)
  Data Path Delay:        8.895ns  (logic 3.506ns (39.415%)  route 5.389ns (60.585%))
  Logic Levels:           7  (CARRY4=5 LUT2=1 OBUF=1)
  Output Delay:           3.000ns
  Clock Path Skew:        -4.561ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    0.000ns = ( 22676.000 - 22676.000 ) 
    Source Clock Delay      (SCD):    4.561ns
    Clock Pessimism Removal (CPR):    0.000ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock clk rise edge)        0.000     0.000 r  
                         propagated clock network latency
                                                      4.561     4.561    
    SLICE_X5Y148         FDRE                         0.000     4.561 r  y2k_pipeline_reg[2]/C
    SLICE_X5Y148         FDRE (Prop_fdre_C_Q)         0.269     4.830 r  y2k_pipeline_reg[2]/Q
                         net (fo=3, routed)           1.036     5.866    y2k_pipeline_reg_n_0_[2]
    SLICE_X4Y137         LUT2 (Prop_lut2_I0_O)        0.053     5.919 r  y_out_0_OBUF[3]_inst_i_3/O
                         net (fo=1, routed)           0.000     5.919    y_out_0_OBUF[3]_inst_i_3_n_0
    SLICE_X4Y137         CARRY4 (Prop_carry4_S[2]_CO[3])
                                                      0.235     6.154 r  y_out_0_OBUF[3]_inst_i_1/CO[3]
                         net (fo=1, routed)           0.000     6.154    y_out_0_OBUF[3]_inst_i_1_n_0
    SLICE_X4Y138         CARRY4 (Prop_carry4_CI_CO[3])
                                                      0.058     6.212 r  y_out_0_OBUF[7]_inst_i_1/CO[3]
                         net (fo=1, routed)           0.000     6.212    y_out_0_OBUF[7]_inst_i_1_n_0
    SLICE_X4Y139         CARRY4 (Prop_carry4_CI_CO[3])
                                                      0.058     6.270 r  y_out_0_OBUF[11]_inst_i_1/CO[3]
                         net (fo=1, routed)           0.000     6.270    y_out_0_OBUF[11]_inst_i_1_n_0
    SLICE_X4Y140         CARRY4 (Prop_carry4_CI_CO[3])
                                                      0.058     6.328 r  y_out_0_OBUF[15]_inst_i_1/CO[3]
                         net (fo=1, routed)           0.000     6.328    y_out_0_OBUF[15]_inst_i_1_n_0
    SLICE_X4Y141         CARRY4 (Prop_carry4_CI_O[0])
                                                      0.139     6.467 r  y_out_0_OBUF[39]_inst_i_1/O[0]
                         net (fo=24, routed)          4.353    10.820    y_out_0_OBUF[16]
    F25                  OBUF (Prop_obuf_I_O)         2.636    13.456 r  y_out_0_OBUF[16]_inst/O
                         net (fo=0)                   0.000    13.456    y_out_0[16]
    F25                                                               r  y_out_0[16] (OUT)
  -------------------------------------------------------------------    -------------------

                         (clock clk rise edge)    22676.000 22676.000 r  
                         propagated clock network latency
                                                      0.000 22676.000    
                         clock pessimism              0.000 22676.000    
                         clock uncertainty           -0.035 22675.965    
                         output delay                -3.000 22672.965    
  -------------------------------------------------------------------
                         required time                      22672.967    
                         arrival time                         -13.456    
  -------------------------------------------------------------------
                         slack                              22659.512    
```

| Filter Type                   | LUT  |  FF  | DSP  | IO  | Area (mm²) | Critical Path (ns) | Logic Delay | Cycle Time (clk) | Max clk (MHz) | Power (W) |
|-------------------------------|------|------|------|-----|------------|--------------------|-------------|------------------|---------------|-----------|
| **Pipelined FIR**             |    0 | 3232 |  102 |  34 |     4.0632 |              8.663 |       2.852 |              204 |         115.4 |     0.081 |
| **L2 Parallel FIR**           |   49 | 2416 |  153 | 114 |     7.1214 |             80.171 |      74.571 |               51 |          12.5 |     0.081 |
| **L3 Parallel FIR**           |  230 | 3200 |  204 | 170 |      9.886 |             56.794 |      50.536 |               34 |          17.6 |     0.081 |
| **Pipelined L2 Parallel FIR** |   65 | 4864 |  153 | 114 |     7.3694 |              8.895 |       3.506 |              102 |         112.4 |     0.081 |
| **Pipelined L3 Parallel FIR** |  230 | 6368 |  204 | 170 |    10.2028 |             11.881 |       4.324 |               68 |          84.2 |     0.081 |

While the pipelined L2 Parallel FIR filter does take a few more clock cycles to update than the pipelined L3 Parallel FIR filter resulting in about 100ns extra of processing time per input (102 x 8.895 - 68 x 11.881), it is still very low latency with higher throughput. It uses less silicon and hardware components than the pipelined L3 Parallel FIR filter, and takes up a smaller area. Overall, I think this is a worthy tradeoff: especially considering the behavioral sim for the pipelined L2 Parallel FIR filter is more true to our desired response than the pipelined L3 Parallel FIR filter which suffered on the higher frequency end.

<br>


## Resources

### Textbook: 
[VLSI Digital Signal Processing Systems: Design and Implementation](https://www.amazon.com/VLSI-Digital-Signal-Processing-Systems/dp/0471241865)

### Youtube Videos:
- [Introduction to FIR Filters](https://www.youtube.com/watch?v=NvRKtdrssFA)
- [Pipelining Principles](https://www.youtube.com/watch?v=zPmfprtdzCE)
- [Parallel Computing Explained in 3 Minutes](https://www.youtube.com/watch?v=q7sgzDH1cR8)
- [Pipelining FIR Filter](https://www.youtube.com/watch?v=ClBw7TxUDM4)

### Sources:
[^1]: D. Zaucha, “How many bits do you need? A discussion of precision for digital audio filters*,” EE Times, [https://www.eetimes.com/how-many-bits-do-you-need-a-discussion-of-precision-for-digital-audio-filters/](https://www.eetimes.com/how-many-bits-do-you-need-a-discussion-of-precision-for-digital-audio-filters/) (accessed Mar. 18, 2025). 

[^2]: S. Arar, “Pipelined direct form FIR versus the transposed structure - technical articles,” All About Circuits, [https://www.allaboutcircuits.com/technical-articles/pipelined-direct-form-fir-versus-the-transposed-structure/](https://www.allaboutcircuits.com/technical-articles/pipelined-direct-form-fir-versus-the-transposed-structure/) (accessed Mar. 18, 2025). 

[^3]: K. Parhi, "Chapter 9: Algorithmic Strength Reduction in Filters and Transforms," [https://people.ece.umn.edu/users/parhi/SLIDES/chap9.pdf](https://people.ece.umn.edu/users/parhi/SLIDES/chap9.pdf) (accessed Mar. 18, 2025). 