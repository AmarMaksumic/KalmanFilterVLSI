module matrix_add #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 32
)(
    input logic clk,
    input logic rst,
    input logic start,
    output logic done,

    output logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:143],

    input int index_A,
    input int index_B,
    input int index_C
);

    logic [15:0] idx;
    logic computing;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            computing <= 0;
        end else begin
            if (start && !computing) begin
                $display("[RESULT] matrix_add output (index %0d):", index_C);
                idx <= 0;
                computing <= 1;
                done <= 0;
            end else if (computing) begin
                matrix_pool[index_C][idx] <= matrix_pool[index_A][idx] + matrix_pool[index_B][idx];
                $display("%0d", matrix_pool[index_C][idx]);
                if (idx < 143)
                    idx <= idx + 1;
                else begin
                    computing <= 0;
                    done <= 1;
                end
            end
        end
    end

endmodule
