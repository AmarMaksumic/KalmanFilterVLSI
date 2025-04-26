module tb_lu_decomposition_12x12;
    reg clk;
    reg reset;
    reg [15:0] A[11:0][11:0];  // Input 12x12 matrix A
    wire [15:0] L[11:0][11:0]; // Output Lower triangular matrix L
    wire [15:0] U[11:0][11:0]; // Output Upper triangular matrix U

    // Instantiate the LU decomposition module
    lu_decomposition_12x12 #(
        .WIDTH(16)
    ) uut (
        .clk(clk),
        .reset(reset),
        .A(A),
        .L(L),
        .U(U)
    );

    // Generate clock signal
    always begin
        #5 clk = ~clk;  // Clock period of 10ns (100 MHz)
    end

    initial begin
        // Initialize clock and reset signals
        clk = 0;
        reset = 1;

        // Initialize the input matrix A with test values (identity matrix)
        for (int i = 0; i < 12; i++) begin
            for (int j = 0; j < 12; j++) begin
                A[i][j] = (i == j) ? 16'h0001 : 16'h0000; // Identity matrix
            end
        end

        // Apply reset
        reset = 1;
        #10 reset = 0;

        // Wait for LU decomposition to complete
        #100;  // Adjust this delay to ensure LU decomposition completes

        // Display the resulting lower triangular matrix L
        $display("Lower Triangular Matrix L:");
        for (int i = 0; i < 12; i++) begin
            $display("%h %h %h %h %h %h %h %h %h %h %h %h", 
                L[i][0], L[i][1], L[i][2], L[i][3], L[i][4], 
                L[i][5], L[i][6], L[i][7], L[i][8], L[i][9], 
                L[i][10], L[i][11]);
        end

        // Display the resulting upper triangular matrix U
        $display("Upper Triangular Matrix U:");
        for (int i = 0; i < 12; i++) begin
            $display("%h %h %h %h %h %h %h %h %h %h %h %h", 
                U[i][0], U[i][1], U[i][2], U[i][3], U[i][4], 
                U[i][5], U[i][6], U[i][7], U[i][8], U[i][9], 
                U[i][10], U[i][11]);
        end

        // Finish the simulation
        $finish;
    end
endmodule
