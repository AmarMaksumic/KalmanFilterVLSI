module matrix_mult #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 32
)(
    input logic clk,
    input logic rst,
    input logic start,
    output logic done,

    input int mult_M,
    input int mult_K,
    input int mult_N,

    output logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:143],

    input int index_A,
    input int index_B,
    input int index_C
);

    logic [15:0] i, j, k;
    logic signed [DATA_WIDTH-1:0] sum;
    logic computing;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            computing <= 0;
        end else begin
            if (start && !computing) begin
                done <= 0;
                computing <= 1;
                i <= 0; j <= 0; k <= 0;
                sum <= 0;
            end else if (computing) begin
                if (k < mult_K) begin
                    sum <= sum + (matrix_pool[index_A][i*mult_K+k] * matrix_pool[index_B][k*mult_N+j]);
                    k <= k + 1;
                end else begin
                    matrix_pool[index_C][i*mult_N+j] <= sum;
                    sum <= 0;
                    if (j < mult_N-1) begin
                        j <= j + 1;
                        k <= 0;
                    end else if (i < mult_M-1) begin
                        i <= i + 1;
                        j <= 0;
                        k <= 0;
                    end else begin
                        computing <= 0;
                        done <= 1;
                    end
                end
            end
        end
        if (!computing && done) begin
            $display("[RESULT] matrix_mult output (index %0d):", index_C);
            for (int p = 0; p < mult_M * mult_N; p++) $display("%0d", matrix_pool[index_C][p]);
        end
    end

endmodule
