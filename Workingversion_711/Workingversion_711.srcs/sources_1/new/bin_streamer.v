// sequential_radix_streamer.v
// Sequential, area-efficient streamer: converts decimal fixed-point (magnitude,scale)
// into glyph bus for base = bin/oct/hex (one digit produced per cycle).
`timescale 1ns/1ps
module sequential_radix_streamer #(
  parameter WIDTH    = 32,
  parameter MAX_RES  = 12,
  parameter FRAC_DIGS = 8
)(
  input  wire                 clk,
  input  wire                 rst,
  input  wire                 start,      // 1-cycle pulse: start conversion
  input  wire                 enable,     // module active when enable==1
  input  wire                 neg,        // sign
  input  wire [WIDTH-1:0]     magnitude,  // value * 10^scale
  input  wire [3:0]           scale,      // decimal places
  input  wire [1:0]           mode,       // 0 = unused/decimal, 1=bin,2=oct,3=hex
  output reg                  busy,
  output reg                  done,       // pulses 1-cycle when bus/len ready
  output reg [5*MAX_RES-1:0]  bus,
  output reg [5:0]            len
);

  // internal states
  localparam S_IDLE    = 3'd0;
  localparam S_DIV_INT = 3'd1; // run seq_div to compute integer_part = magnitude / pow10, rem = %
  localparam S_INT_DIG = 3'd2; // extract integer digits (one per cycle)
  localparam S_FRAC    = 3'd3; // compute fractional digits (one per cycle using divider)
  localparam S_FRAC_WAIT= 3'd4;
  localparam S_BUILD   = 3'd5;
  localparam S_DONE    = 3'd6;

  reg [2:0] state;

  // instantiate seq_udiv_64 for integer-part extraction and fractional digit division
  // We'll reuse the same divider instance for both tasks sequentially.
  reg div_start;
  wire div_busy, div_done;
  reg [63:0] div_dividend;
  reg [31:0] div_divisor;
  wire [63:0] div_quot;
  wire [31:0] div_rem;

  // Use your seq_udiv_64 module with WN=64, WD=32, WQ=64
  seq_udiv_64 #(.WN(64), .WD(32), .WQ(64)) u_div (
    .clk(clk), .rst(rst), .start(div_start),
    .dividend(div_dividend), .divisor(div_divisor),
    .busy(div_busy), .done(div_done), .quotient(div_quot), .remainder(div_rem)
  );

  // pow10 table (for scale 0..9)
  function [31:0] p10;
    input [3:0] s;
    begin
      case (s)
        4'd0: p10=32'd1; 4'd1: p10=32'd10; 4'd2: p10=32'd100; 4'd3: p10=32'd1000;
        4'd4: p10=32'd10000; 4'd5: p10=32'd100000; 4'd6: p10=32'd1000000;
        4'd7: p10=32'd10000000; 4'd8: p10=32'd100000000; 4'd9: p10=32'd1000000000;
        default: p10=32'd1;
      endcase
    end
  endfunction

  // local regs
  reg [WIDTH-1:0] mag_l;
  reg [31:0] pow10_l;
  reg [31:0] int_part32; // result quotient fits 32-bit
  reg [31:0] rem32;
  reg [5:0] int_collected; // number of integer digits collected (LSB-first)
  reg [3:0] int_digits [0:MAX_RES-1]; // LSB-first
  reg [5:0] int_use; // how many integer digits to use
  reg [5:0] frac_collected;
  reg [3:0] frac_digits [0:FRAC_DIGS-1];
  reg [5:0] slots_allowed;
  reg [1:0] mode_l;
  reg neg_l;
  reg frac_div_launched;
  
  reg [31:0] digit32;

  // digit extraction helpers
  reg [31:0] working_int; // will be shifted/divided as we extract digits
//  reg [5:0]  extract_cnt;
//  reg [31:0] tmp32;

  // fractional division temp
  // to compute next frac digit: digit = floor(rem * base / pow10)
  // we'll set div_dividend = rem * base (<= pow10*base) -> fits 64 bits
//  reg [63:0] frac_dividend;

  integer i;
  integer base;
  integer mask;
  integer spare;
  integer max_frac;
  integer pos;
  integer k;
  integer idx;
  integer spare_after_int;
//  integer int_use_local;
//  integer max_frac_show;
//  integer seq_idx;
//  integer after_int_idx;
//  integer total_len;
//  integer after_int;   // offset into dot+frac area
//  integer int_idx;     // index into int_digits (LSB-first storage)

  
  // helper to map numeric value to glyph code
  function [4:0] glyph_map;
    input [3:0] v;
    input [1:0] mode_local; // decide if hex mapping required
    begin
      if (mode_local == 2'd3) begin
        // hex: 10..15 -> A..F glyphs (5'd24..5'd29)
        if (v < 4'd10) glyph_map = v;
        else case (v)
          4'd10: glyph_map = 5'd24;
          4'd11: glyph_map = 5'd25;
          4'd12: glyph_map = 5'd26;
          4'd13: glyph_map = 5'd27;
          4'd14: glyph_map = 5'd28;
          4'd15: glyph_map = 5'd29;
          default: glyph_map = 5'd0;
        endcase
      end else begin
        // binary/octal: digits are 0..(base-1) but we map 0..9 to glyphs 0..9
        glyph_map = v;
      end
    end
  endfunction

  // main FSM: sequential and conservative
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      busy  <= 1'b0;
      done  <= 1'b0;
      bus   <= {5*MAX_RES{1'b0}};
      len   <= 6'd0;
      div_start <= 1'b0;
      mag_l <= {WIDTH{1'b0}};
      pow10_l <= 32'd1;
      int_part32 <= 32'd0;
      rem32 <= 32'd0;
      int_collected <= 6'd0;
      frac_collected <= 6'd0;
      frac_div_launched <= 1'b0;
      slots_allowed <= MAX_RES;
      mode_l <= 2'd0; neg_l <= 1'b0;
      for (i=0;i<MAX_RES;i=i+1) int_digits[i] <= 4'd0;
      for (i=0;i<FRAC_DIGS;i=i+1) frac_digits[i] <= 4'd0;
    end else begin
      done <= 1'b0;
      div_start <= 1'b0; // default
      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (enable && start) begin
            busy <= 1'b1;
            mag_l <= magnitude;
            pow10_l <= p10(scale);
            mode_l <= mode;
            neg_l <= neg;
            // prepare: start divider to compute integer part = mag / pow10
            // we use seq_udiv_64 with dividend width 64; feed magnitude as low 32 into 64 input
            div_dividend <= {32'd0, magnitude};
            div_divisor  <= p10(scale);
            div_start <= 1'b1;
            state <= S_DIV_INT;
          end
        end

        S_DIV_INT: begin
          // wait for divider to finish for integer part
          if (div_done) begin
            // quotient in div_quot (64-bit) -> fits into 32 bits for our inputs
            int_part32 <= div_quot[31:0];
            rem32      <= div_rem; // remainder < pow10
            // prepare integer digit extraction
            int_collected <= 6'd0;
            for (i=0;i<MAX_RES;i=i+1) int_digits[i] <= 4'd0;
            // slots allowed = MAX_RES - (neg?1:0)
            slots_allowed <= MAX_RES - (neg ? 1 : 0);
            // setup working_int
            working_int <= div_quot[31:0];
            state <= S_INT_DIG;
          end
        end

        S_INT_DIG: begin
          // Extract integer digits one per cycle.
          // For power-of-two bases (bin/oct/hex) we use shifts & masks
          if (mode_l == 2'd1) begin base = 2; mask = 1; end
          else if (mode_l == 2'd2) begin base = 8; mask = 7; end
          else begin base = 16; mask = 15; end

          if (working_int != 0 && int_collected < slots_allowed) begin
            // extract one digit (LSB-first)
            if (base == 2) begin
              int_digits[int_collected] <= working_int[0];
              working_int <= working_int >> 1;
            end else if (base == 8) begin
              int_digits[int_collected] <= working_int[2:0];
              working_int <= working_int >> 3;
            end else begin // 16
              int_digits[int_collected] <= working_int[3:0];
              working_int <= working_int >> 4;
            end
            int_collected <= int_collected + 1;
          end else begin
            // if working_int == 0 and no digits collected yet, ensure at least one zero digit
            if (int_collected == 0) begin
              int_digits[0] <= 4'd0;
              int_collected <= 6'd1;
            end
            // decide how many integer digits to use (we show LSB chunk)
            if (int_collected > slots_allowed) int_use <= slots_allowed;
            else int_use <= int_collected;

            // if remainder exists and we have spare slots for '.' and digits -> generate fractional digits
            if (rem32 != 0) begin
              // compute spare slots after integer and optional '.' (we need 1 slot for '.' plus digits)
              if (slots_allowed > int_use) begin
                frac_collected <= 6'd0;
                state <= S_FRAC;
                // no immediate divider start; we will start per fraction digit
              end else begin
                // no room for fraction -> build out
                state <= S_BUILD;
              end
            end else begin
              // no fractional part -> go build final
              state <= S_BUILD;
            end
          end
        end

        // ---------------- FRAC: request and wait for division to produce one fractional digit ----------------
        S_FRAC: begin

          // determine base
          if (mode_l == 2'd1) base = 2;
          else if (mode_l == 2'd2) base = 8;
          else base = 16;

          // compute spare slots after integer digits (slots_allowed and int_use are precomputed)
          spare = slots_allowed - int_use;
          if (spare > 0) max_frac = spare - 1; else max_frac = 0;
          if (max_frac > FRAC_DIGS) max_frac = FRAC_DIGS;

          // if we already generated enough fractional digits, go build
          if (frac_collected >= max_frac) begin
            state <= S_BUILD;
            frac_div_launched <= 1'b0;
            div_start <= 1'b0;
          end else begin
            // if we haven't launched a div for the current digit and divider is free, launch it
            if (!frac_div_launched && !div_busy) begin
              // form 64-bit dividend = rem32 * base
              // rem32 < pow10_l, base <= 16 => product fits comfortably in 64 bits
              div_dividend <= {32'd0, rem32} * base;
              div_divisor  <= pow10_l;
              div_start    <= 1'b1;           // start divider this cycle
              frac_div_launched <= 1'b1;     // remember we launched and must wait
              state <= S_FRAC_WAIT;          // wait next cycle(s) for done
            end else begin
              // either divider is busy (wait) or we've launched and are waiting - stay here
              div_start <= 1'b0;
            end
          end
        end

        // ---------------- FRAC_WAIT: wait for divider to finish and accept the digit ----------------
        S_FRAC_WAIT: begin
          div_start <= 1'b0; // ensure start is low while waiting
          if (div_done) begin
            // quotient = digit (fits 32-bit), remainder = new rem
            digit32 = div_quot[31:0];
            // store only lower 4 bits (digit < base <=16)
            frac_digits[frac_collected] <= digit32[3:0];
            rem32 <= div_rem;               // next remainder
            frac_collected <= frac_collected + 1;
            frac_div_launched <= 1'b0;
            // go back to S_FRAC to either start another fractional digit or move on
            state <= S_FRAC;
          end
        end


        S_BUILD: begin
          // Build MS-first bus in registers (one cycle): sign, integer MS..LS (from LSB-first array),
          // optional '.' and fractional digits
          // clear bus first
          for (i=0;i<MAX_RES;i=i+1) bus[5*i +: 5] <= 5'd0;

          pos = 0;
          if (neg_l) begin
            bus[5*pos +: 5] <= 5'd11; // '-'
            pos = pos + 1;
          end

          // integer digits: we stored LSB-first in int_digits[0..int_use-1]
          for (k = 0; k < int_use && pos < MAX_RES; k = k + 1) begin
            idx = int_use - 1 - k; // MS-first order from LSB-first array
            bus[5*pos +: 5] <= glyph_map(int_digits[idx], mode_l);
            pos = pos + 1;
//                  if (pos >= MAX_RES) break;
          end

          // fractional: only if frac_collected>0 and there is room for '.' and digits
          spare_after_int = MAX_RES - pos;
          if (frac_collected > 0 && spare_after_int >= 1 + frac_collected) begin
            // dot
            bus[5*pos +: 5] <= 5'd15; pos = pos + 1;
            for (k=0; k<frac_collected && pos < MAX_RES; k = k + 1) begin
              bus[5*pos +: 5] <= glyph_map(frac_digits[k], mode_l);
              pos = pos + 1;
//                  if (pos >= MAX_RES) break;
            end
          end

          len <= pos;
          state <= S_DONE;
        end


        S_DONE: begin
          done <= 1'b1;
          busy <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase

      // Catch div_done at top-level to service both S_DIV_INT and S_FRAC:
      // (we used simple local checks inside states to proceed when div_done asserted)
    end
  end
endmodule
