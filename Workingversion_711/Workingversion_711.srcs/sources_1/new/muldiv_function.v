// ======================= muldiv_function.v (explicit sign via XOR) =======================
`timescale 1ns/1ps
module muldiv_function #(
  parameter WIDTH              = 32,
  parameter DEC_PLACES         = 3,   // number of fractional decimal digits in fixed-point
  parameter SUPPRESS_NEG_ZERO  = 1    // 1: hide "-0" when exact zero magnitude; 0: show sign always
)(
  input                   clk,
  input                   rst,
  input                   sym_pulse,
  input         [4:0]     sym_code,
  input                   delete_pulse,  // NEW: undo last symbol
  input         [4:0]     delete_sym,    // NEW: which symbol to delete

  output reg  [WIDTH-1:0] res_mag,       // |result| truncated to WIDTH
  output reg              res_neg,       // sign flag to display
  output reg  [15:0]      res_low16,     // low 16 bits (debug/LEDs)
  output reg              res_valid,     // one-cycle pulse
  output reg              overflow,      // overflow of WIDTH after truncation
  output reg              div_by_zero,   // one-cycle pulse

  output      [3:0]       res_scale,     // equals DEC_PLACES
  output                  res_is_decimal // DEC_PLACES != 0
);

  // -------------------- Input decoding (unchanged interface expectations) --------------------
  wire is_digit = (sym_code <= 5'd9);
  wire is_mul   = (sym_code == 5'd12);
  wire is_div   = (sym_code == 5'd13);
  wire is_eq    = (sym_code == 5'd14);
  wire is_plus  = (sym_code == 5'd10);
  wire is_minus = (sym_code == 5'd11);
  wire is_dot   = (sym_code == 5'd15);

  // -------------------- 10^n helper for decimal scaling --------------------
  function [31:0] p10; input [3:0] s; begin
    case (s)
      4'd0: p10=32'd1;          4'd1: p10=32'd10;
      4'd2: p10=32'd100;        4'd3: p10=32'd1000;
      4'd4: p10=32'd10000;      4'd5: p10=32'd100000;
      4'd6: p10=32'd1000000;    4'd7: p10=32'd10000000;
      4'd8: p10=32'd100000000;  4'd9: p10=32'd1000000000;
      default: p10=32'd1;
    endcase
  end endfunction

  localparam [31:0] SCALE_K = p10(DEC_PLACES[3:0]);
  assign res_scale      = DEC_PLACES[3:0];
  assign res_is_decimal = (DEC_PLACES != 0);

  // -------------------- Typing / tokenizing a term (signed fixed-point) --------------------
  localparam WBIG = 64;

  reg  [WIDTH-1:0] term_int;
  reg  [3:0]       term_frac_cnt;
  reg              term_has_dot;
  reg              term_neg;        // unary minus on the term being typed
  reg              op_armed;        // true once we have something typed for current term

  reg  signed [WBIG-1:0] acc;       // running accumulator in scaled fixed-point
  reg                    have_acc;  // whether 'acc' has a value yet

  // next operator to apply when next term arrives: 1='*', 0='/'
  reg                    op_next;
  reg                    op_do_mul; // latched operator for current pair
  
  // Track if we just emitted a result (for clear-on-next behavior)
  reg                    result_emitted;

  // No need to track last_sym internally anymore - it comes from input

  // helpers
  function [WBIG-1:0] abs64; input signed [WBIG-1:0] s; begin
    abs64 = s[WBIG-1] ? (~s + 1'b1) : s;
  end endfunction

  function [31:0] abs32; input signed [31:0] s; begin
    abs32 = s[31] ? (~s + 1'b1) : s;
  end endfunction

  function [WIDTH-1:0] mul10; input [WIDTH-1:0] v; begin
    mul10 = (v<<3)+(v<<1);
  end endfunction

  // Convert typed term to fixed-point WBIG with DEC_PLACES
  function signed [WBIG-1:0] make_fixed;
    input [WIDTH-1:0] mag_no_dot;
    input [3:0]       frac_cnt;
    input             is_neg;
    reg   signed [WBIG-1:0] w;
    reg   [31:0] pad;
    begin
      pad = (frac_cnt >= DEC_PLACES[3:0]) ? 32'd1 : p10(DEC_PLACES[3:0]-frac_cnt);
      w   = $signed({{(WBIG-WIDTH){1'b0}}, mag_no_dot})
          * $signed({{(WBIG-32){1'b0}}, pad});
      if (is_neg && (mag_no_dot!=0)) w = -w;  // keep typed "-0" as +0
      make_fixed = w;
    end
  endfunction

  wire signed [WBIG-1:0] current_term_fixed = make_fixed(term_int, term_frac_cnt, term_neg);

  // -------------------- Multiplier & Divider --------------------
  // For '*', we multiply, then divide by SCALE_K to keep DEC_PLACES
  reg  signed [WBIG-1:0] a_reg, b_reg;  // operands in fixed-point
  reg                    res_sign_xor;  // XOR(sign(a), sign(b)) computed up front

  // 96-bit temp for product (WBIG*32 is enough here due to scaling path used)
  wire signed [95:0] prod_mul =
      $signed({{(96-WBIG){a_reg[WBIG-1]}}, a_reg})
    * $signed({{(96-32){b_reg[31]}},       b_reg[31:0]});
  wire signed [63:0] prod64_trunc = prod_mul[63:0];

  // sequential unsigned divider (we always divide positive magnitudes)
  localparam WN_DIV = 64;
  reg  [WN_DIV-1:0] d_dividend;
  reg  [31:0]       d_divisor;
  wire              d_busy, d_done;
  wire [63:0]       d_quot;
  wire [31:0]       d_rem;

  reg d_start;
  seq_udiv_64 #(.WN(WN_DIV), .WD(32), .WQ(64)) udiv (
    .clk(clk), .rst(rst), .start(d_start),
    .dividend(d_dividend), .divisor(d_divisor),
    .busy(d_busy), .done(d_done),
    .quotient(d_quot), .remainder(d_rem)
  );

  // -------------------- FSM --------------------
  localparam S_IDLE=3'd0, S_PREP=3'd1, S_DIV_WAIT=3'd2, S_COMMIT=3'd3, S_EMIT=3'd4;
  reg [2:0] state;
  reg       emit_after;     // if user pressed '='
  reg       div0_latch;     // sticky until EMIT to pulse div_by_zero

  // -------------------- Main --------------------
  reg  signed [WIDTH-1:0] trunc;
  reg  signed [WBIG-1:0]  sext;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      term_int<=0; term_frac_cnt<=0; term_has_dot<=1'b0; term_neg<=1'b0; op_armed<=1'b0;
      acc<=0; have_acc<=1'b0; op_next<=1'b1; op_do_mul<=1'b1;

      a_reg<=0; b_reg<=0; res_sign_xor<=1'b0;
      state<=S_IDLE; emit_after<=1'b0;

      d_start<=1'b0; div0_latch<=1'b0;

      res_mag<=0; res_neg<=1'b0; res_low16<=16'h0000;
      res_valid<=1'b0; overflow<=1'b0; div_by_zero<=1'b0;
      result_emitted<=1'b0;

    end else begin
      // defaults each cycle
      res_valid   <= 1'b0;
      overflow    <= 1'b0;
      div_by_zero <= 1'b0;
      d_start     <= 1'b0;
      
      // Clear result_emitted flag on any new input (except delete)
      if (sym_pulse && state==S_IDLE && !delete_pulse && 
          (is_digit || is_dot || is_minus || is_plus || is_mul || is_div)) begin
        result_emitted <= 1'b0;
      end

      // -------- DELETE handling --------
      if (delete_pulse && state == S_IDLE && delete_sym != 5'd31) begin
        // Reverse the effect of the symbol specified by delete_sym
        if (delete_sym <= 5'd9) begin
          // Delete a digit: reverse "term_int = mul10(term_int) + digit"
          term_int <= (term_int - {{(WIDTH-5){1'b0}}, delete_sym}) / 32'd10;
          if (term_has_dot && term_frac_cnt > 0) term_frac_cnt <= term_frac_cnt - 4'd1;
          // Check if term is now empty
          if ((term_int - {{(WIDTH-5){1'b0}}, delete_sym}) / 32'd10 == 0 && !term_has_dot && !term_neg)
            op_armed <= 1'b0;
          
        end else if (delete_sym == 5'd15) begin
          // Delete dot
          term_has_dot  <= 1'b0;
          term_frac_cnt <= 4'd0;
          op_armed      <= (term_int != 0 || term_neg);
          
        end else if (delete_sym == 5'd11) begin
          // Delete unary minus
          term_neg <= 1'b0;
          op_armed <= (term_int != 0 || term_has_dot);
          
        end else if (delete_sym == 5'd12 || delete_sym == 5'd13) begin
          // Delete operator
          op_armed <= (term_int != 0 || term_has_dot || term_neg);
        end
        
      end else

      // ---------------- Typing state ----------------
      if (state==S_IDLE && sym_pulse) begin
        if (is_digit) begin
          term_int <= mul10(term_int) + {{(WIDTH-4){1'b0}}, sym_code[3:0]};
          if (term_has_dot && term_frac_cnt < DEC_PLACES[3:0])
            term_frac_cnt <= term_frac_cnt + 4'd1;
          op_armed <= 1'b1;

        end else if (is_dot) begin
          if (!term_has_dot) begin term_has_dot <= 1'b1; op_armed <= 1'b1; end

        end else if (!op_armed) begin
          // unary sign before any digits
          if (is_minus) begin term_neg <= 1'b1; op_armed <= 1'b1; end
          else if (is_plus && !have_acc) begin term_neg <= 1'b0; op_armed <= 1'b1; end

        end else if (is_mul || is_div || is_eq) begin
          if (op_armed) begin
            if (!have_acc && (is_mul || is_div)) begin
              // seed acc with first term
              acc      <= current_term_fixed;
              have_acc <= 1'b1;
              op_next  <= is_mul;
            end else begin
              // have acc & current term -> perform previous op_next
              a_reg       <= acc;
              b_reg       <= current_term_fixed;

              // --------- SIGN RULE: result_sign = sign(a) XOR sign(b) ---------
              res_sign_xor<= acc[WBIG-1] ^ current_term_fixed[WBIG-1];

              op_do_mul   <= op_next;
              emit_after  <= is_eq;
              state       <= S_PREP;

              if (is_mul || is_div) op_next <= is_mul;
            end
            // clear typed term
            term_int<=0; term_frac_cnt<=0; term_has_dot<=1'b0; term_neg<=1'b0; op_armed<=1'b0;

          end else if (is_eq) begin
            emit_after <= 1'b1;
            state      <= S_EMIT;
          end
        end
      end

      // ---------------- Engine states ----------------
      case (state)
        S_IDLE: begin end

        S_PREP: begin
          if (op_do_mul) begin
            // Multiply: (a * b) / SCALE_K
            d_dividend <= abs64(prod64_trunc);
            d_divisor  <= SCALE_K;
            d_start    <= 1'b1;
            state      <= S_DIV_WAIT;

          end else begin
            // Divide: (a * SCALE_K) / b
            if (b_reg == 0) begin
              div0_latch <= 1'b1;
              have_acc   <= 1'b0;     // reset chain
              state      <= S_EMIT;
            end else begin
              d_dividend <= abs64($signed(abs64(a_reg)) * $signed(SCALE_K));
              d_divisor  <= abs32(b_reg[31:0]);
              d_start    <= 1'b1;
              state      <= S_DIV_WAIT;
            end
          end
        end

        S_DIV_WAIT: begin
          if (d_done) state <= S_COMMIT;
        end

        S_COMMIT: begin
          // Apply sign AFTER magnitude operation
          acc      <= res_sign_xor ? -$signed(d_quot) : $signed(d_quot);
          have_acc <= 1'b1;
          state    <= (emit_after ? S_EMIT : S_IDLE);
        end

        S_EMIT: begin
          // pulse error flag this cycle if div0 occurred
          div_by_zero <= div0_latch;

          // width truncation & overflow detect
          trunc    = acc[WIDTH-1:0];
          sext     = {{(WBIG-WIDTH){trunc[WIDTH-1]}}, trunc};
          overflow <= (acc != sext) & ~div0_latch;   // ignore on div0

          res_low16 <= trunc[15:0];
          res_mag   <= trunc[WIDTH-1] ? (~trunc + 1'b1) : trunc;

          // --------- DISPLAY SIGN LOGIC ----------
          // base sign from XOR of operand signs
          // (already captured in res_sign_xor, independent of magnitude).
          if (SUPPRESS_NEG_ZERO) begin
            // Hide "-0" only when the final *exact* fixed-point value is zero.
            // This does NOT hide "-0.xxx" (fractional negatives).
            res_neg <= (acc == 0) ? 1'b0 : res_sign_xor;
          end else begin
            res_neg <= res_sign_xor;
          end

          res_valid <= 1'b1;
          result_emitted <= 1'b1;

          if (div0_latch) div0_latch <= 1'b0; // clear sticky

          if (emit_after) begin
            have_acc   <= 1'b0;
            emit_after <= 1'b0;
          end
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
