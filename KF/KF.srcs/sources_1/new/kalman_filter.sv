// kalman_filter.sv
// Full Kalman Filter: Prediction + Correction + Matrix operations (mult, add, transpose, inverse) with debug logs

module kalman_filter #(
    parameter int STATE_SIZE = 4,
    parameter int DATA_WIDTH = 16,
    parameter int NUM_MATRICES = 32
)(
    input logic clk,
    input logic rst,
    input logic start,
    output logic done,

    output logic signed [DATA_WIDTH-1:0] matrix_pool [0:NUM_MATRICES-1][0:143],

    output int mult_M,
    output int mult_K,
    output int mult_N
);

    typedef enum logic [5:0] {
        IDLE, A_MU, B_U, MU_PREDICT, A_SIGMA, TRANS_A, A_SIGMA_AT, SIGMA_PREDICT_ADD_Q,
        C_SIGMA, TRANS_C, C_SIGMA_CT, S_TEMP_ADD_R, S_INVERSE, SIGMA_CT, KALMAN_GAIN,
        Y_TEMP, K_Y, MU_UPDATE, K_C, I_MINUS_KC, SIGMA_UPDATE, DONE
    } state_t;

    state_t state, next;

    logic loaded;
    logic start_mult, start_add, start_trans, start_inv;
    logic done_mult, done_add, done_trans, done_inv;
    int index_A, index_B, index_C;

    matrix_mult #(.DATA_WIDTH(DATA_WIDTH), .NUM_MATRICES(NUM_MATRICES)) mult_inst (
        .clk(clk), .rst(rst), .start(start_mult), .done(done_mult),
        .mult_M(mult_M), .mult_K(mult_K), .mult_N(mult_N),
        .matrix_pool(matrix_pool), .index_A(index_A), .index_B(index_B), .index_C(index_C)
    );

    matrix_add #(.DATA_WIDTH(DATA_WIDTH), .NUM_MATRICES(NUM_MATRICES)) add_inst (
        .clk(clk), .rst(rst), .start(start_add), .done(done_add),
        .matrix_pool(matrix_pool), .index_A(index_A), .index_B(index_B), .index_C(index_C)
    );

    matrix_transpose #(.DATA_WIDTH(DATA_WIDTH), .NUM_MATRICES(NUM_MATRICES)) trans_inst (
        .clk(clk), .rst(rst), .start(start_trans), .done(done_trans),
        .matrix_pool(matrix_pool), .index_in(index_A), .index_out(index_C),
        .rows(mult_M), .cols(mult_K)
    );

    matrix_inverse #(.DATA_WIDTH(DATA_WIDTH), .NUM_MATRICES(NUM_MATRICES)) inv_inst (
        .clk(clk), .rst(rst), .start(start_inv), .done(done_inv),
        .matrix_pool(matrix_pool), .index_in(index_A), .index_out(index_C),
        .size(mult_M)
    );

    initial begin
        loaded = 0;
        $readmemh("A_matrix.mem", matrix_pool[0]);
        $readmemh("B_matrix.mem", matrix_pool[1]);
        $readmemh("C_matrix.mem", matrix_pool[2]);
        $readmemh("z_vector.mem", matrix_pool[3]);
        $readmemh("Q_matrix.mem", matrix_pool[4]);
        $readmemh("R_matrix.mem", matrix_pool[5]);
        $readmemh("mu_prev.mem", matrix_pool[6]);
        $readmemh("Sigma_prev.mem", matrix_pool[7]);
        $readmemh("u_vector.mem", matrix_pool[8]);
        $display("[INFO] Matrices loaded inside kalman_filter.");
        #2;
        loaded = 1;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next;
    end

    always_comb begin
        next = state;
        start_mult = 0;
        start_add = 0;
        start_trans = 0;
        start_inv = 0;
        index_A = 0;
        index_B = 0;
        index_C = 0;
        mult_M = STATE_SIZE;
        mult_K = STATE_SIZE;
        mult_N = 1;
        done = 0;

        case (state)
            IDLE: if (start && loaded) begin $display("[STATE] IDLE -> A_MU"); next = A_MU; end
            A_MU: begin $display("[STATE] A_MU"); index_A = 0; index_B = 6; index_C = 9; start_mult = 1; if (done_mult) next = B_U; end
            B_U: begin $display("[STATE] B_U"); index_A = 1; index_B = 8; index_C = 10; start_mult = 1; mult_K = STATE_SIZE/2; if (done_mult) next = MU_PREDICT; end
            MU_PREDICT: begin $display("[STATE] MU_PREDICT"); index_A = 9; index_B = 10; index_C = 11; start_add = 1; if (done_add) next = A_SIGMA; end
            A_SIGMA: begin $display("[STATE] A_SIGMA"); index_A = 0; index_B = 7; index_C = 12; start_mult = 1; if (done_mult) next = TRANS_A; end
            TRANS_A: begin $display("[STATE] TRANS_A"); index_A = 0; index_C = 27; start_trans = 1; if (done_trans) next = A_SIGMA_AT; end
            A_SIGMA_AT: begin $display("[STATE] A_SIGMA_AT"); index_A = 12; index_B = 27; index_C = 13; start_mult = 1; if (done_mult) next = SIGMA_PREDICT_ADD_Q; end
            SIGMA_PREDICT_ADD_Q: begin $display("[STATE] SIGMA_PREDICT_ADD_Q"); index_A = 13; index_B = 4; index_C = 14; start_add = 1; if (done_add) next = C_SIGMA; end
            C_SIGMA: begin $display("[STATE] C_SIGMA"); index_A = 2; index_B = 14; index_C = 15; start_mult = 1; if (done_mult) next = TRANS_C; end
            TRANS_C: begin $display("[STATE] TRANS_C"); index_A = 2; index_C = 28; start_trans = 1; if (done_trans) next = C_SIGMA_CT; end
            C_SIGMA_CT: begin $display("[STATE] C_SIGMA_CT"); index_A = 15; index_B = 28; index_C = 16; start_mult = 1; if (done_mult) next = S_TEMP_ADD_R; end
            S_TEMP_ADD_R: begin $display("[STATE] S_TEMP_ADD_R"); index_A = 16; index_B = 5; index_C = 17; start_add = 1; if (done_add) next = S_INVERSE; end
            S_INVERSE: begin $display("[STATE] S_INVERSE"); index_A = 17; index_C = 18; start_inv = 1; if (done_inv) next = SIGMA_CT; end
            SIGMA_CT: begin $display("[STATE] SIGMA_CT"); index_A = 14; index_B = 28; index_C = 19; start_mult = 1; if (done_mult) next = KALMAN_GAIN; end
            KALMAN_GAIN: begin $display("[STATE] KALMAN_GAIN"); index_A = 19; index_B = 18; index_C = 20; start_mult = 1; if (done_mult) next = Y_TEMP; end
            Y_TEMP: begin $display("[STATE] Y_TEMP"); index_A = 3; index_B = 2; index_C = 21; start_add = 1; if (done_add) next = K_Y; end
            K_Y: begin $display("[STATE] K_Y"); index_A = 20; index_B = 21; index_C = 22; start_mult = 1; if (done_mult) next = MU_UPDATE; end
            MU_UPDATE: begin $display("[STATE] MU_UPDATE"); index_A = 11; index_B = 22; index_C = 29; start_add = 1; if (done_add) next = K_C; end
            K_C: begin $display("[STATE] K_C"); index_A = 20; index_B = 2; index_C = 24; start_mult = 1; if (done_mult) next = I_MINUS_KC; end
            I_MINUS_KC: begin $display("[STATE] I_MINUS_KC"); index_A = 2; index_B = 24; index_C = 25; start_add = 1; if (done_add) next = SIGMA_UPDATE; end
            SIGMA_UPDATE: begin $display("[STATE] SIGMA_UPDATE"); index_A = 25; index_B = 14; index_C = 30; start_mult = 1; if (done_mult) next = DONE; end
            DONE: begin $display("[STATE] DONE"); done = 1; end
        endcase
    end

endmodule : kalman_filter
