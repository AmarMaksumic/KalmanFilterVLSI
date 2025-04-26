// kalman_filter.sv
// Clean Kalman Filter Top using basic matrix operations, no FSMs

module kalman_filter #(
    parameter int STATE_SIZE = 4,
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 16
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    output logic done,

    ref logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:STATE_SIZE*STATE_SIZE-1]
);

    // Internal control
    logic predict_mu_done;
    logic predict_sigma_done;
    logic transpose_done;
    logic add_noise_done;
    logic invert_done;

    logic predict_mu_start;
    logic predict_sigma_start;
    logic transpose_start;
    logic add_noise_start;
    logic invert_start;

    // --- Instantiate matrix operations ---

    matrix_mult #(
        .M(STATE_SIZE), .N(STATE_SIZE), .K(1),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES)
    ) mu_predict (
        .clk(clk),
        .rst(rst),
        .start(predict_mu_start),
        .done(predict_mu_done),
        .matrix_pool(matrix_pool),
        .index_A(0),  // A
        .index_B(6),  // mu_prev
        .index_C(8)   // mu_predict
    );

    matrix_mult #(
        .M(STATE_SIZE), .N(STATE_SIZE), .K(STATE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES)
    ) sigma_predict (
        .clk(clk),
        .rst(rst),
        .start(predict_sigma_start),
        .done(predict_sigma_done),
        .matrix_pool(matrix_pool),
        .index_A(0),   // A
        .index_B(7),   // Sigma_prev
        .index_C(9)    // A * Sigma_prev
    );

    matrix_transpose #(
        .M(STATE_SIZE), .N(STATE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES)
    ) A_transpose (
        .clk(clk),
        .rst(rst),
        .start(transpose_start),
        .done(transpose_done),
        .matrix_pool(matrix_pool),
        .index_A(0),    // A
        .index_C(10)    // A_T
    );

    matrix_add #(
        .M(STATE_SIZE), .N(STATE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES
    ) sigma_add_noise (
        .clk(clk),
        .rst(rst),
        .start(add_noise_start),
        .done(add_noise_done),
        .matrix_pool(matrix_pool),
        .index_A(9),    // A * Sigma
        .index_B(4),    // Q (process noise)
        .index_C(11)    // Sigma_predict + Q
    );

    matrix_inverse #(
        .STATE_SIZE(STATE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_MATRICES(NUM_MATRICES
    ) invert_sigma (
        .clk(clk),
        .rst(rst),
        .start(invert_start),
        .done(invert_done),
        .matrix_pool(matrix_pool),
        .index_A(11),   // Sigma_predict + Q
        .index_C(12)    // Inverted Sigma
    );

    // --- Controller ---
    typedef enum logic [2:0] {
        IDLE,
        START_PREDICT_MU,
        WAIT_PREDICT_MU,
        START_PREDICT_SIGMA,
        WAIT_PREDICT_SIGMA,
        START_TRANSPOSE,
        WAIT_TRANSPOSE,
        START_ADD_NOISE,
        WAIT_ADD_NOISE,
        START_INVERT,
        WAIT_INVERT,
        COMPLETE
    } state_t;
    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: if (start) state <= START_PREDICT_MU;
                START_PREDICT_MU: state <= WAIT_PREDICT_MU;
                WAIT_PREDICT_MU: if (predict_mu_done) state <= START_PREDICT_SIGMA;
                START_PREDICT_SIGMA: state <= WAIT_PREDICT_SIGMA;
                WAIT_PREDICT_SIGMA: if (predict_sigma_done) state <= START_TRANSPOSE;
                START_TRANSPOSE: state <= WAIT_TRANSPOSE;
                WAIT_TRANSPOSE: if (transpose_done) state <= START_ADD_NOISE;
                START_ADD_NOISE: state <= WAIT_ADD_NOISE;
                WAIT_ADD_NOISE: if (add_noise_done) state <= START_INVERT;
                START_INVERT: state <= WAIT_INVERT;
                WAIT_INVERT: if (invert_done) state <= COMPLETE;
                COMPLETE: state <= COMPLETE;
                default: state <= IDLE;
            endcase
        end
    end

    // Start signals
    always_comb begin
        predict_mu_start = (state == START_PREDICT_MU);
        predict_sigma_start = (state == START_PREDICT_SIGMA);
        transpose_start = (state == START_TRANSPOSE);
        add_noise_start = (state == START_ADD_NOISE);
        invert_start = (state == START_INVERT);
    end

    assign done = (state == COMPLETE);

endmodule : kalman_filter
