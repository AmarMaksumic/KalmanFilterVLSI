// matrix_sub.sv
// Clean, no FSM, pure matrix subtraction module

module matrix_sub #(
    parameter int M = 4,
    parameter int N = 4,
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 16
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    ref logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:M*N-1],
    input  logic [$clog2(NUM_MATRICES)-1:0] index_A,
    input  logic [$clog2(NUM_MATRICES)-1:0] index_B,
    input  logic [$clog2(NUM_MATRICES)-1:0] index_C
);

    logic [$clog2(M*N)-1:0] idx;
    logic busy;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            idx <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            if (start && !busy) begin
                idx <= 0;
                busy <= 1;
                done <= 0;
            end else if (busy) begin
                matrix_pool[index_C][idx] <= matrix_pool[index_A][idx] - matrix_pool[index_B][idx];
                if (idx == M*N-1) begin
                    busy <= 0;
                    done <= 1;
                end else begin
                    idx <= idx + 1;
                end
            end else begin
                done <= 0;
            end
        end
    end

endmodule : matrix_sub