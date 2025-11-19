`timescale 1ns/1ps
// Decimal add/sub with seeding support.
// sym_code: 0..9 digits, 10:'+', 11:'-', 14:'=', 15:'.'
module addsub_function #(
  parameter WIDTH      = 32,
  parameter MAX_SCALE  = 9
)(
  input                   clk,
  input                   rst,
  input                   sym_pulse,
  input        [4:0]      sym_code,
  input                   delete_pulse,    // NEW: undo last symbol
  input        [4:0]      delete_sym,      // NEW: which symbol to delete

  // ---- NEW: seed interface (loads accumulator directly) ----
  input                   seed_valid,      // pulse: load acc = seed (scaled integer)
  input       [WIDTH-1:0] seed_mag,
  input                   seed_neg,
  input       [3:0]       seed_scale,

  // Outputs
  output reg  [WIDTH-1:0] sum_mag,
  output reg              sum_neg,
  output reg  [15:0]      sum_low16,
  output reg              sum_valid,
  output reg              overflow,

  output reg  [3:0]       res_scale,
  output reg              res_is_decimal
);

  // decode
  wire is_digit = (sym_code <= 5'd9);
  wire is_plus  = (sym_code == 5'd10);
  wire is_minus = (sym_code == 5'd11);
  wire is_eq    = (sym_code == 5'd14);
  wire is_dot   = (sym_code == 5'd15);

  // helpers
  function [31:0] pow10; input [3:0] s; begin
    case (s)
      4'd0: pow10=32'd1;         4'd1: pow10=32'd10;
      4'd2: pow10=32'd100;       4'd3: pow10=32'd1000;
      4'd4: pow10=32'd10000;     4'd5: pow10=32'd100000;
      4'd6: pow10=32'd1000000;   4'd7: pow10=32'd10000000;
      4'd8: pow10=32'd100000000; 4'd9: pow10=32'd1000000000;
      default: pow10=32'd1;
    endcase
  end endfunction

  function [WIDTH-1:0] mul10; input [WIDTH-1:0] v; begin
    mul10 = (v<<3)+(v<<1);
  end endfunction

  // current typed term
  reg  [WIDTH-1:0] term_int;
  reg  [3:0]       term_scale;
  reg              term_has_dot;
  reg              op_add;     // next op (1:+, 0:-)
  reg              op_armed;

  // accumulator
  localparam WACC = 2*WIDTH + 16;
  reg  signed [WACC-1:0] acc;
  reg  [3:0]             acc_scale;
  reg                    have_acc;
  
  // Track if we just emitted a result (for clear-on-next behavior)
  reg                    result_emitted;

  // No need to track last_sym internally anymore - it comes from input

  // temps
  reg  [3:0]             S;
  reg  signed [WACC-1:0] a_al, t_al, final_w;
  reg  [31:0]            k;

  // stretch seed for 1 cycle (priority over operator pulse)
  reg seed_q;
  reg [3:0] S2; reg [31:0] k2; reg signed [WACC-1:0] a2, t2;
  reg signed [WIDTH-1:0] trunc;
  reg signed [WACC-1:0]  sext_trunc;
  always @(posedge clk or posedge rst) begin
    if (rst) seed_q <= 1'b0;
    else      seed_q <= seed_valid;
  end
  wire seed_fire = seed_valid | seed_q;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      term_int<=0; term_scale<=0; term_has_dot<=1'b0; op_add<=1'b1; op_armed<=1'b0;
      acc<=0; acc_scale<=0; have_acc<=1'b0;
      sum_mag<=0; sum_neg<=1'b0; sum_low16<=0; sum_valid<=1'b0; overflow<=1'b0;
      res_scale<=0; res_is_decimal<=1'b0;
      result_emitted<=1'b0;

    end else begin
      sum_valid <= 1'b0;
      
      // Clear result_emitted flag on any new input (except delete)
      if (sym_pulse && !delete_pulse && (is_digit || is_dot || is_plus || is_minus)) begin
        result_emitted <= 1'b0;
      end

      // -------- DELETE handling --------
      if (delete_pulse && delete_sym != 5'd31) begin
        // Reverse the effect of the symbol specified by delete_sym
        if (delete_sym <= 5'd9) begin
          // Delete a digit: reverse "term_int = mul10(term_int) + digit"
          term_int <= (term_int - {{(WIDTH-5){1'b0}}, delete_sym}) / 32'd10;
          if (term_has_dot && term_scale > 0) term_scale <= term_scale - 4'd1;
          // Check if term is now empty
          if ((term_int - {{(WIDTH-5){1'b0}}, delete_sym}) / 32'd10 == 0 && !term_has_dot) 
            op_armed <= 1'b0;
          
        end else if (delete_sym == 5'd15) begin
          // Delete dot
          term_has_dot <= 1'b0;
          term_scale   <= 4'd0;
          op_armed     <= (term_int != 0);
          
        end else if (delete_sym == 5'd10 || delete_sym == 5'd11) begin
          // Delete operator
          op_armed <= (term_int != 0 || term_has_dot);
        end
        
      end else if (seed_fire) begin
        // -------- SEED takes priority --------
        acc        <= seed_neg
                      ? -$signed({{(WACC-WIDTH){1'b0}}, seed_mag})
                      :  $signed({{(WACC-WIDTH){1'b0}}, seed_mag});
        acc_scale  <= seed_scale;
        have_acc   <= 1'b1;

        // clear current term
        term_int<=0; term_scale<=0; term_has_dot<=1'b0; op_armed<=1'b0;

      end else if (sym_pulse) begin
        if (is_digit) begin
          term_int   <= mul10(term_int) + {{(WIDTH-4){1'b0}}, sym_code[3:0]};
          if (term_has_dot && term_scale < MAX_SCALE[3:0]) term_scale <= term_scale + 4'd1;
          op_armed   <= 1'b1;

        end else if (is_dot) begin
          if (!term_has_dot) begin term_has_dot <= 1'b1; op_armed <= 1'b1; end

        end else if (is_plus || is_minus) begin
          // commit pending term if any
          if (op_armed) begin
            if (!have_acc) begin
              // Apply the current op_add sign to the first term
              acc       <= op_add ? $signed({{(WACC-WIDTH){1'b0}}, term_int}) 
                                  : -$signed({{(WACC-WIDTH){1'b0}}, term_int});
              acc_scale <= term_scale;
              have_acc  <= 1'b1;
            end else begin
              S   = (acc_scale >= term_scale) ? acc_scale : term_scale;

              a_al = acc;
              if (acc_scale < S) begin
                k    = pow10(S-acc_scale);
                a_al = a_al * $signed({{(WACC-32){1'b0}}, k});
              end

              t_al = $signed({{(WACC-WIDTH){1'b0}}, term_int});
              if (term_scale < S) begin
                k    = pow10(S-term_scale);
                t_al = t_al * $signed({{(WACC-32){1'b0}}, k});
              end

              acc       <= op_add ? (a_al + t_al) : (a_al - t_al);
              acc_scale <= S;
            end

            term_int<=0; term_scale<=0; term_has_dot<=1'b0; op_armed<=1'b0;
          end

          op_add <= is_plus; // set next op

        end else if (is_eq) begin
          // finalize with pending term (if any)
          final_w = acc;
          S       = acc_scale;

          if (op_armed) begin
           
            S2 = (acc_scale >= term_scale) ? acc_scale : term_scale;

            a2 = acc;
            if (acc_scale < S2) begin
              k2 = pow10(S2-acc_scale); a2 = a2 * $signed({{(WACC-32){1'b0}}, k2});
            end
            t2 = $signed({{(WACC-WIDTH){1'b0}}, term_int});
            if (term_scale < S2) begin
              k2 = pow10(S2-term_scale); t2 = t2 * $signed({{(WACC-32){1'b0}}, k2});
            end

            final_w = op_add ? (a2 + t2) : (a2 - t2);
            S       = S2;
          end

          // pack result

          trunc      = final_w[WIDTH-1:0];
          sext_trunc = {{(WACC-WIDTH){trunc[WIDTH-1]}}, trunc};
          overflow   <= (final_w != sext_trunc);

          sum_low16  <= trunc[15:0];
          sum_neg    <= trunc[WIDTH-1];
          sum_mag    <= trunc[WIDTH-1] ? (~trunc + 1'b1) : trunc;

          res_scale      <= S;
          res_is_decimal <= (S != 0);
          sum_valid      <= 1'b1;
          result_emitted <= 1'b1;

          // reset chain
          term_int<=0; term_scale<=0; term_has_dot<=1'b0; op_armed<=1'b0;
          acc<=0; acc_scale<=0; have_acc<=1'b0; op_add<=1'b1;
        end
      end
    end
  end
endmodule
