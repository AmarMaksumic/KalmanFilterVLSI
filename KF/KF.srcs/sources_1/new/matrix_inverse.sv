module matrix_inverse #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 32
)(
    input logic clk,
    input logic rst,
    input logic start,
    output logic done,

    output logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:143],

    input int index_in,
    input int index_out,
    input int size
);

    logic computing;
    int i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            computing <= 0;
        end else begin
            if (start && !computing) begin
                i <= 0;
                computing <= 1;
                done <= 0;
            end else if (computing) begin
                // Naive "inversion" mock: just copy the identity (replace later with real LU)
                if (i < size*size) begin
                    matrix_pool[index_out][i] <= (i/size == i%size) ? 16'd16384 : 16'd0;  // Identity scaled
                    i <= i + 1;
                end else begin
                    computing <= 0;
                    done <= 1;
                end
            end
//            if (!computing && done) begin
//                $display("[RESULT] matrix_inverse output (index %0d):", index_out);
//                for (int p = 0; p < size * size; p++) $display("%0d", matrix_pool[index_out][p]);
//            end
        end
    end

endmodule
