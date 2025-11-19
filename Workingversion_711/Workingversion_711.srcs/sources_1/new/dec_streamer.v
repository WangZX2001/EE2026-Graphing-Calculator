// ======================= dec_streamer_scaled.v (sign always emitted when neg==1) =======================
`timescale 1ns/1ps
// Converts (neg flag, scaled integer magnitude, scale) to symbol codes MS-first.
// Emits optional leading '-' (code 11), digits, and '.' (code 15) when scale>0.
module dec_streamer_scaled #(
  parameter WIDTH   = 32,
  parameter MAX_DIG = 12
)(
  input                   clk,
  input                   rst,
  input                   start,       // 1-cycle pulse
  input                   neg,         // 1 = print a leading '-'
  input      [WIDTH-1:0]  magnitude,   // absolute scaled integer
  input      [3:0]        scale,       // fractional digits (0..9)

  output reg              busy,
  output reg              done,        // 1-cycle pulse when ready
  output reg  [5:0]       len,         // total symbols
  output reg  [5*MAX_DIG-1:0] bus      // MS-first codes
);

localparam S_IDLE=3'd0, S_DIV=3'd1, S_PACK_SIGN=3'd2,
           S_PACK_PRED=3'd3, S_PACK_DOT=3'd4, S_PACK_ZEROS=3'd5,
           S_PACK_POST=3'd6, S_PACK_LEAD_ZERO=3'd7;
           
  reg [2:0] state;

  // collect digits LS..MS
  reg [3:0] tmp [0:MAX_DIG-1];
  reg [3:0] cnt;
  reg [WIDTH-1:0] n, q, t;

  // cached params
  reg       neg_l;
  reg [3:0] scale_l;
  reg [3:0] digits_total;

  // pack cursors/counters
  reg [5:0] out_idx;
  reg [3:0] ms_idx, ls_idx;
  reg [3:0] pre_cnt, post_cnt, zero_cnt;

  // sign control: ALWAYS follow neg_l
  reg sign_en;

  function [5:0] calc_len; input negi; input [3:0] digits; input [3:0] sc;
    reg [5:0] base, add_sign, add_dot, add_lead_zero;
    begin
      base     = (digits==0) ? 6'd1 : {2'b00, digits};
      add_sign = negi ? 6'd1 : 6'd0;
      add_dot  = (sc!=0) ? 6'd1 : 6'd0;
      // Add leading zero when we have a decimal and digits <= scale (e.g., 0.2, 0.02)
      add_lead_zero = ((sc!=0) && (digits <= sc)) ? 6'd1 : 6'd0;
      calc_len = base + add_sign + add_dot + add_lead_zero + ((sc > digits) ? (sc - digits) : 6'd0);
    end
  endfunction

  task put_sym; input [4:0] code;
    begin
      if (out_idx < MAX_DIG[5:0]) begin
        bus[5*out_idx +: 5] <= code;
        out_idx <= out_idx + 6'd1;
      end
    end
  endtask

  function [4:0] dcode; input [3:0] d; begin dcode = {1'b0, d}; end endfunction

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state   <= S_IDLE;
      busy    <= 1'b0;
      done    <= 1'b0;
      len     <= 6'd0;
      bus     <= {5*MAX_DIG{1'b0}};
      cnt     <= 4'd0;
      n       <= {WIDTH{1'b0}};
      out_idx <= 6'd0;
      ms_idx  <= 4'd0; ls_idx<=4'd0;
      pre_cnt <= 4'd0; post_cnt<=4'd0; zero_cnt<=4'd0;
      neg_l   <= 1'b0; scale_l<=4'd0; digits_total<=4'd0;
      sign_en <= 1'b0;

    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start && !busy) begin
            busy    <= 1'b1;
            state   <= S_DIV;
            cnt     <= 4'd0;
            n       <= magnitude;
            neg_l   <= neg;
            scale_l <= scale;

            // key: emit '-' whenever neg==1 (independent of magnitude)
            sign_en <= neg;
          end
        end

        S_DIV: begin
          if (n == 0) begin
            if (cnt == 0) begin
              tmp[0] <= 4'd0;
              cnt    <= 4'd1;
            end
            bus          <= {5*MAX_DIG{1'b0}};
            out_idx      <= 6'd0;
            digits_total <= cnt;

            len <= calc_len(sign_en, cnt, scale_l);
            state <= S_PACK_SIGN;
          end else begin
            q = n / 10;
            t = n - q*10;
            if (cnt < MAX_DIG[3:0]) begin
              tmp[cnt] <= t[3:0];
              cnt      <= cnt + 4'd1;
            end
            n <= q;
          end
        end
        
        S_PACK_SIGN : begin
         if (neg_l) put_sym(5'd11);
         
         if (scale_l == 0) begin
         pre_cnt <= digits_total;
         ms_idx  <= (digits_total - 1);
         state   <= S_PACK_PRED;
         
         end else if (digits_total > scale_l) begin
         pre_cnt <= (digits_total - scale_l);
         ms_idx  <= (digits_total - 1);
         state   <= S_PACK_PRED;
          end else begin
          // Don't emit leading zero yet - do it next cycle
          state    <= S_PACK_LEAD_ZERO;  // NEW
          pre_cnt  <= 4'd0;
          zero_cnt <= (scale_l - digits_total);
          post_cnt <= digits_total;
          ls_idx   <= (digits_total==0) ? 4'd0 : (digits_total - 1);
         end
         end
        S_PACK_LEAD_ZERO: begin
        put_sym(dcode(4'd0));  // leading zero before dot: "-0.xxx"
       state <= S_PACK_DOT;
        end

        S_PACK_PRED: begin
          if (pre_cnt != 0) begin
            put_sym( dcode( tmp[ms_idx] ) );
            ms_idx  <= ms_idx - 4'd1;
            pre_cnt <= pre_cnt - 4'd1;
          end else begin
            if (scale_l != 0) begin
              post_cnt <= scale_l;
              ls_idx   <= (scale_l - 1);
              state    <= S_PACK_DOT;
            end else begin
              state    <= S_IDLE;
              busy     <= 1'b0;
              done     <= 1'b1;
            end
          end
        end

        S_PACK_DOT: begin
          put_sym(5'd15); // '.'
          if (digits_total > scale_l) begin
            state <= S_PACK_POST;
          end else begin
            state <= (zero_cnt != 0) ? S_PACK_ZEROS : S_PACK_POST;
          end
        end

        S_PACK_ZEROS: begin
          if (zero_cnt != 0) begin
            put_sym(dcode(4'd0));
            zero_cnt <= zero_cnt - 4'd1;
          end else begin
            state <= S_PACK_POST;
          end
        end

        S_PACK_POST: begin
          if (post_cnt != 0) begin
            put_sym( dcode( tmp[ls_idx] ) );
            if (ls_idx != 0) ls_idx <= ls_idx - 4'd1;
            post_cnt <= post_cnt - 4'd1;
          end else begin
            state <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b1;
          end
        end
      endcase
    end
  end
endmodule
