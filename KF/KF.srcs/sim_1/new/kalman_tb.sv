// kalman_tb.sv
// Testbench for full Kalman Filter with detailed debug output

`timescale 1ns / 1ps

module kalman_tb;

    logic clk;
    logic rst;
    logic start;
    logic done;

    localparam STATE_SIZE = 4;
    localparam DATA_WIDTH = 16;
    localparam NUM_MATRICES = 32;

    logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:143];

    // Instantiate DUT
    kalman_filter #(
        .STATE_SIZE(STATE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .matrix_pool(matrix_pool)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Debug monitor
//    always_ff @(posedge clk) begin
//        $display("[DEBUG] clk=%0d rst=%0d start=%0d done=%0d", clk, rst, start, done);
//    end

    // Load matrices from .mem files and start simulation
    initial begin
        rst = 1;
        start = 0;
        #20;
        rst = 0;

        $readmemh("A_matrix.mem", matrix_pool[0]);
        $readmemh("B_matrix.mem", matrix_pool[1]);
        $readmemh("C_matrix.mem", matrix_pool[2]);
        $readmemh("z_vector.mem", matrix_pool[3]);
        $readmemh("Q_matrix.mem", matrix_pool[4]);
        $readmemh("R_matrix.mem", matrix_pool[5]);
        $readmemh("mu_prev.mem", matrix_pool[6]);
        $readmemh("Sigma_prev.mem", matrix_pool[7]);
        $readmemh("u_vector.mem", matrix_pool[8]);

        $display("[INFO] Matrices loaded from mem files.");

        #10;
        start = 1;
        $display("[INFO] Start signal sent.");
        #10;
        start = 0;

        // Wait for completion
        $display("[INFO] Waiting for done...");
        wait (done);

        $display("[INFO] Kalman filter operation completed!");

        // Print final outputs
        $display("=== Kalman Filter Outputs ===");

        // Final mu_new
        $display("=== Final mu_new (matrix_pool[29]) ===");
        for (int i = 0; i < STATE_SIZE; i++) begin
            $display("mu_new[%0d] = %0d", i, matrix_pool[29][i]);
        end

        // Final Sigma_new
        $display("=== Final Sigma_new (matrix_pool[30]) ===");
        for (int i = 0; i < STATE_SIZE; i++) begin
            for (int j = 0; j < STATE_SIZE; j++) begin
                $write("%0d ", matrix_pool[30][i * STATE_SIZE + j]);
            end
            $display("");
        end

        // Kalman Gain K
        $display("=== Kalman Gain K (matrix_pool[20]) ===");
        for (int i = 0; i < STATE_SIZE; i++) begin
            for (int j = 0; j < STATE_SIZE; j++) begin
                $write("%0d ", matrix_pool[20][i * STATE_SIZE + j]);
            end
            $display("");
        end

        $display("=== End of Kalman Filter Simulation ===");

        $finish;
    end

endmodule : kalman_tb
