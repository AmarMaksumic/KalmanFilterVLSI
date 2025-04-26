module matrix_transpose #(
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
    input int rows,
    input int cols
);

    int i, j;
    logic computing;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            computing <= 0;
        end else begin
            if (start && !computing) begin
                i <= 0; j <= 0;
                done <= 0;
                computing <= 1;
            end else if (computing) begin
                matrix_pool[index_out][j*rows+i] <= matrix_pool[index_in][i*cols+j];
                if (j < cols-1) begin
                    j <= j + 1;
                end else if (i < rows-1) begin
                    i <= i + 1;
                    j <= 0;
                end else begin
                    computing <= 0;
                    done <= 1;
                end
            end
            if (!computing && done) begin
                $display("[RESULT] matrix_transpose output (index %0d):", index_out);
                for (int p = 0; p < rows * cols; p++) $display("%0d", matrix_pool[index_out][p]);
            end
        end
    end

endmodule
