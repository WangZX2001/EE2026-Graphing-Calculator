// ======================= Output_strip.v =======================
`timescale 1ns/1ps
// TWO 16-px bars:
//  � TOP   : input history + blinking caret (scrollable with btnL/btnR when full)
//  � BOTTOM: integer result (MS-first)
module Output_strip #(
    parameter DISP_W     = 96,
    parameter DISP_H     = 64,
    parameter TOP_GAP    = 2,  // spacing for top row
    parameter CELL_W     = 10,
    parameter CELL_H     = 14,
    parameter PAD_L      = 2,
    parameter PAD_T      = 1,
    parameter PAD_B      = 1,
    parameter MAX_LEN    = 32,
    parameter MAX_RES    = 10,
    parameter CARET_W_PX = 2
)(
    input                  clk,
    input                  rst,
    input  [12:0]          pixel_index,

    // TOP row input bus (MS-first)
    input  [5*MAX_LEN-1:0] buffer_bus,
    input  [5:0]           len,

    // BOTTOM row integer digits (MS-first)
    input  [5*MAX_RES-1:0] res_bus,
    input  [5:0]           res_len,

    // caret control
    input                  caret_enable,
    input                  caret_phase,

    // frame tick + buttons
    input                  frame_begin,
    input                  btnL,
    input                  btnR,

    output reg             px_on_text,
    output reg             px_on_bg
);

  // ===============================================================
  // Layout constants
  // ===============================================================
  localparam STRIP_H     = 16;
  localparam YBOT_TOP    = DISP_H - STRIP_H;
  localparam integer VCAP      = (DISP_W - PAD_L) / CELL_W;
  localparam integer VCAP_TOP  = (DISP_W - PAD_L) / (CELL_W + TOP_GAP);
  localparam integer PITCH_TOP = CELL_W + TOP_GAP;

  // pixel to x,y
  wire [6:0] x = pixel_index % DISP_W;
  wire [6:0] y = pixel_index / DISP_W;

  wire in_top = (y < STRIP_H);
  wire in_bot = (y >= YBOT_TOP);
  integer i;

  // ===============================================================
  // Font function
  // ===============================================================
  function font_on;
    input [4:0] code;
    input [3:0] fx, fy;
    reg [4:0] colmask [0:6];
    integer yy;
    begin
      // default blank
      colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b00000;
      colmask[3]=5'b00000; colmask[4]=5'b00000; colmask[5]=5'b00000; colmask[6]=5'b00000;

      case (code)
        // 0..9
        5'd0: begin
          colmask[0]=5'b11111; colmask[1]=5'b10001; colmask[2]=5'b10011;
          colmask[3]=5'b10101; colmask[4]=5'b11001; colmask[5]=5'b10001; colmask[6]=5'b11111;
        end
        5'd1: begin
          colmask[0]=5'b00100; colmask[1]=5'b01100; colmask[2]=5'b00100;
          colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b01110;
        end
        5'd2: begin
          colmask[0]=5'b11110; colmask[1]=5'b00001; colmask[2]=5'b00001;
          colmask[3]=5'b11110; colmask[4]=5'b10000; colmask[5]=5'b10000; colmask[6]=5'b11111;
        end
        5'd3: begin
          colmask[0]=5'b11110; colmask[1]=5'b00001; colmask[2]=5'b00001;
          colmask[3]=5'b01110; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11110;
        end
        5'd4: begin
          colmask[0]=5'b10010; colmask[1]=5'b10010; colmask[2]=5'b10010;
          colmask[3]=5'b11111; colmask[4]=5'b00010; colmask[5]=5'b00010; colmask[6]=5'b00010;
        end
        5'd5: begin
          colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b10000;
          colmask[3]=5'b11110; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11110;
        end
        5'd6: begin
          colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b10000;
          colmask[3]=5'b11111; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b11111;
        end
        5'd7: begin
          colmask[0]=5'b11111; colmask[1]=5'b00001; colmask[2]=5'b00010;
          colmask[3]=5'b00100; colmask[4]=5'b01000; colmask[5]=5'b01000; colmask[6]=5'b01000;
        end
        5'd8: begin
          colmask[0]=5'b01110; colmask[1]=5'b10001; colmask[2]=5'b10001;
          colmask[3]=5'b01110; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b01110;
        end
        5'd9: begin
          colmask[0]=5'b11111; colmask[1]=5'b10001; colmask[2]=5'b10001;
          colmask[3]=5'b11111; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11111;
        end

        // math symbols + (10), - (11), x (12), / (13), = (14), . (15)
        5'd10: begin
          colmask[0]=5'b00000; colmask[1]=5'b00100; colmask[2]=5'b00100;
          colmask[3]=5'b11111; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b00000;
        end
        5'd11: begin
          colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b11111;
          colmask[3]=5'b00000; colmask[4]=5'b00000; colmask[5]=5'b00000; colmask[6]=5'b00000;
        end
        5'd12: begin
          colmask[0]=5'b10001; colmask[1]=5'b01010; colmask[2]=5'b00100;
          colmask[3]=5'b00100; colmask[4]=5'b01010; colmask[5]=5'b10001; colmask[6]=5'b00000;
        end
        5'd13: begin
          colmask[0]=5'b00001; colmask[1]=5'b00010; colmask[2]=5'b00100;
          colmask[3]=5'b01000; colmask[4]=5'b10000; colmask[5]=5'b00000; colmask[6]=5'b00000;
        end
        5'd14: begin
          colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b11111;
          colmask[3]=5'b00000; colmask[4]=5'b11111; colmask[5]=5'b00000; colmask[6]=5'b00000;
        end
        5'd15: begin
          colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b00000;
          colmask[3]=5'b00100; colmask[4]=5'b00000; colmask[5]=5'b00000; colmask[6]=5'b00000;
        end

        // misc
        5'd16: begin // 'y'
          colmask[0]=5'b10001; colmask[1]=5'b01010; colmask[2]=5'b00100;
          colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b00000;
        end
        5'd17: begin // 'n' (repurposed from '(')
          colmask[0]=5'b00000; colmask[1]=5'b10110; colmask[2]=5'b11001;
          colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b00000;
        end
        5'd18: begin // 'o' (repurposed from ')')
          colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10001;
          colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b01110; colmask[6]=5'b00000;
        end
        5'd19: begin // 's'
          colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10000;
          colmask[3]=5'b01100; colmask[4]=5'b00010; colmask[5]=5'b11100; colmask[6]=5'b00000;
        end
        5'd20: begin // 'c'
          colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10000;
          colmask[3]=5'b10000; colmask[4]=5'b10000; colmask[5]=5'b01110; colmask[6]=5'b00000;
        end
        5'd21: begin // 't'
          colmask[0]=5'b00100; colmask[1]=5'b11111; colmask[2]=5'b00100;
          colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00011; colmask[6]=5'b00000;
        end
        5'd22: begin // 'a' (repurposed from '^')
          colmask[0]=5'b01110; colmask[1]=5'b00001; colmask[2]=5'b01111;
          colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b01111; colmask[6]=5'b00000;
        end

        // A..F (24..29) and uppercase R (30)
        5'd24: begin // 'A'
          colmask[0]=5'b01110; colmask[1]=5'b10001; colmask[2]=5'b10001;
          colmask[3]=5'b11111; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b00000;
        end
        5'd25: begin // 'B'
          colmask[0]=5'b11110; colmask[1]=5'b10001; colmask[2]=5'b11110;
          colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b11110; colmask[6]=5'b00000;
        end
        5'd26: begin // 'C'
          colmask[0]=5'b01110; colmask[1]=5'b10001; colmask[2]=5'b10000;
          colmask[3]=5'b10000; colmask[4]=5'b10001; colmask[5]=5'b01110; colmask[6]=5'b00000;
        end
        5'd27: begin // 'D'
          colmask[0]=5'b11100; colmask[1]=5'b10010; colmask[2]=5'b10001;
          colmask[3]=5'b10001; colmask[4]=5'b10010; colmask[5]=5'b11100; colmask[6]=5'b00000;
        end
        5'd28: begin // 'E'
          colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b11110;
          colmask[3]=5'b10000; colmask[4]=5'b10000; colmask[5]=5'b11111; colmask[6]=5'b00000;
        end
        5'd29: begin // 'F'
          colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b11110;
          colmask[3]=5'b10000; colmask[4]=5'b10000; colmask[5]=5'b10000; colmask[6]=5'b00000;
        end
        5'd30: begin // 'R'
          colmask[0]=5'b11110; 
          colmask[1]=5'b10001; 
          colmask[2]=5'b10001; 
          colmask[3]=5'b11110; 
          colmask[4]=5'b10100; 
          colmask[5]=5'b10010; 
          colmask[6]=5'b10001; 
        end
        
        // Lowercase letter 'i' for sin/cos/tan expansion
        5'd31: begin // 'i'
          colmask[0]=5'b00100; colmask[1]=5'b00000; colmask[2]=5'b01100;
          colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b01110; colmask[6]=5'b00000;
        end

        default: ;
      endcase

      if (fx < 10 && fy < 14) begin
        yy      = fy >> 1;
        font_on = colmask[yy][4 - (fx >> 1)];
      end else begin
        font_on = 1'b0;
      end
    end
  endfunction

  // ===============================================================
  // Virtual Layout: Width and Glyph ROMs for multi-character tokens
  // ===============================================================
  
  // Width ROM: returns visual width of a token (1 or 3)
  function [1:0] tok_w;
    input [4:0] code;
    begin
      case (code)
        5'd19, 5'd20, 5'd21: tok_w = 2'd3;  // sin/cos/tan are 3-wide
        default:              tok_w = 2'd1;
      endcase
    end
  endfunction
  
  // Glyph ROM: returns single-char code for a token at sub-index
  // Uses codes: 17='n', 18='o', 19='s', 20='c', 21='t', 22='a', 31='i'
  function [4:0] tok_glyph;
    input [4:0] code;
    input [1:0] sub;  // 0..2
    begin
      tok_glyph = code; // default
      case (code)
        5'd19: begin // sin
          if (sub == 2'd0) tok_glyph = 5'd19;      // s
          else if (sub == 2'd1) tok_glyph = 5'd31; // i
          else tok_glyph = 5'd17;                  // n
        end
        5'd20: begin // cos
          if (sub == 2'd0) tok_glyph = 5'd20;      // c
          else if (sub == 2'd1) tok_glyph = 5'd18; // o
          else tok_glyph = 5'd19;                  // s
        end
        5'd21: begin // tan
          if (sub == 2'd0) tok_glyph = 5'd21;      // t
          else if (sub == 2'd1) tok_glyph = 5'd22; // a
          else tok_glyph = 5'd17;                  // n
        end
        default: tok_glyph = code;
      endcase
    end
  endfunction
  
  // Prefix sums: vpref[i] = total visual width of first i tokens
  reg [7:0] vpref [0:MAX_LEN];
  reg [7:0] vis_len;
  integer k;
  
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      for (k=0; k<=MAX_LEN; k=k+1) vpref[k] <= 0;
      vis_len <= 0;
    end else begin
      // Recompute prefix sums whenever buffer changes
      vpref[0] <= 0;
      for (k=0; k<MAX_LEN; k=k+1) begin
        if (k < len)
          vpref[k+1] <= vpref[k] + tok_w(buffer_bus[5*k +: 5]);
        else
          vpref[k+1] <= vpref[k];
      end
      vis_len <= vpref[len];
    end
  end
  
  // Map visual column to buffer index (combinational, no loops)
  // Uses priority encoder approach
  function [5:0] find_buf_i;
    input [7:0] v;
    input [5:0] curr_len;
    integer i;
    reg found;
    begin
      find_buf_i = 0;
      found = 0;
      // Unroll manually for small MAX_LEN, or use if-else chain
      if (!found && curr_len > 0 && v < vpref[1])  begin find_buf_i = 0; found = 1; end
      if (!found && curr_len > 1 && v < vpref[2])  begin find_buf_i = 1; found = 1; end
      if (!found && curr_len > 2 && v < vpref[3])  begin find_buf_i = 2; found = 1; end
      if (!found && curr_len > 3 && v < vpref[4])  begin find_buf_i = 3; found = 1; end
      if (!found && curr_len > 4 && v < vpref[5])  begin find_buf_i = 4; found = 1; end
      if (!found && curr_len > 5 && v < vpref[6])  begin find_buf_i = 5; found = 1; end
      if (!found && curr_len > 6 && v < vpref[7])  begin find_buf_i = 6; found = 1; end
      if (!found && curr_len > 7 && v < vpref[8])  begin find_buf_i = 7; found = 1; end
      if (!found && curr_len > 8 && v < vpref[9])  begin find_buf_i = 8; found = 1; end
      if (!found && curr_len > 9 && v < vpref[10]) begin find_buf_i = 9; found = 1; end
      if (!found && curr_len > 10 && v < vpref[11]) begin find_buf_i = 10; found = 1; end
      if (!found && curr_len > 11 && v < vpref[12]) begin find_buf_i = 11; found = 1; end
      if (!found && curr_len > 12 && v < vpref[13]) begin find_buf_i = 12; found = 1; end
      if (!found && curr_len > 13 && v < vpref[14]) begin find_buf_i = 13; found = 1; end
      if (!found && curr_len > 14 && v < vpref[15]) begin find_buf_i = 14; found = 1; end
      if (!found && curr_len > 15 && v < vpref[16]) begin find_buf_i = 15; found = 1; end
      if (!found && curr_len > 16 && v < vpref[17]) begin find_buf_i = 16; found = 1; end
      if (!found && curr_len > 17 && v < vpref[18]) begin find_buf_i = 17; found = 1; end
      if (!found && curr_len > 18 && v < vpref[19]) begin find_buf_i = 18; found = 1; end
      if (!found && curr_len > 19 && v < vpref[20]) begin find_buf_i = 19; found = 1; end
      if (!found && curr_len > 20 && v < vpref[21]) begin find_buf_i = 20; found = 1; end
      if (!found && curr_len > 21 && v < vpref[22]) begin find_buf_i = 21; found = 1; end
      if (!found && curr_len > 22 && v < vpref[23]) begin find_buf_i = 22; found = 1; end
      if (!found && curr_len > 23 && v < vpref[24]) begin find_buf_i = 23; found = 1; end
      if (!found && curr_len > 24 && v < vpref[25]) begin find_buf_i = 24; found = 1; end
      if (!found && curr_len > 25 && v < vpref[26]) begin find_buf_i = 25; found = 1; end
      if (!found && curr_len > 26 && v < vpref[27]) begin find_buf_i = 26; found = 1; end
      if (!found && curr_len > 27 && v < vpref[28]) begin find_buf_i = 27; found = 1; end
      if (!found && curr_len > 28 && v < vpref[29]) begin find_buf_i = 28; found = 1; end
      if (!found && curr_len > 29 && v < vpref[30]) begin find_buf_i = 29; found = 1; end
      if (!found && curr_len > 30 && v < vpref[31]) begin find_buf_i = 30; found = 1; end
      if (!found && curr_len > 31 && v < vpref[32]) begin find_buf_i = 31; found = 1; end
    end
  endfunction
  
  // Map visual column to sub-glyph index within token
  function [1:0] find_sub;
    input [7:0] v;
    input [5:0] i;
    begin
      find_sub = v - vpref[i];
    end
  endfunction

  // ===============================================================
  // Viewport + caret control (now in visual units)
  // ===============================================================
  reg fb_d;
  wire fb_tick = frame_begin & ~fb_d;

  reg [7:0] view_first_v;  // visual start column
  reg [7:0] caret_vis;     // caret in visual columns
  reg       manual;
  reg [5:0] len_prev;

  reg btnL_s, btnR_s, btnL_prev, btnR_prev;
  wire step_left  = fb_tick && btnL_s && ~btnL_prev;
  wire step_right = fb_tick && btnR_s && ~btnR_prev;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      fb_d <= 0;
      btnL_s <= 0; btnR_s <= 0;
      btnL_prev <= 0; btnR_prev <= 0;
      view_first_v <= 0;
      caret_vis <= 0;
      manual <= 0;
      len_prev <= 0;
    end else begin
      fb_d <= frame_begin;
      if (fb_tick) begin
        btnL_prev <= btnL_s; btnR_prev <= btnR_s;
        btnL_s <= btnL; btnR_s <= btnR;

        // Manual caret movement with btnL/btnR
        if (step_left && caret_vis != 0) begin
          caret_vis <= caret_vis - 1;
          manual <= 1;
        end
        if (step_right && caret_vis < vis_len) begin
          caret_vis <= caret_vis + 1;
          manual <= 1;
        end

        // Auto-follow mode: caret at end, view follows
        if (!manual) begin
          view_first_v <= (vis_len > VCAP_TOP) ? (vis_len - VCAP_TOP) : 0;
          caret_vis    <= vis_len;
        end
        
        // Reset manual mode when buffer length changes (new input)
        if (len != len_prev) begin
          manual <= 0;
        end

        if (caret_vis > vis_len) caret_vis <= vis_len;

        // caret visibility in visual units
        if (caret_vis < view_first_v)
          view_first_v <= caret_vis;
        else if (caret_vis >= view_first_v + VCAP_TOP)
          view_first_v <= caret_vis - VCAP_TOP;

        // Clamp to valid range
        if (vis_len > VCAP_TOP && view_first_v > vis_len - VCAP_TOP)
          view_first_v <= vis_len - VCAP_TOP;
        else if (vis_len <= VCAP_TOP)
          view_first_v <= 0;

        len_prev <= len;
      end
    end
  end

  // ===============================================================
  // Visible regions and caret positions (in visual units)
  // ===============================================================
  wire [7:0] vis_top   = (vis_len > VCAP_TOP) ? VCAP_TOP : vis_len;
  wire [7:0] first_top = view_first_v;
  wire [7:0] caret_rel_pre = (caret_vis > first_top) ? (caret_vis - first_top) : 0;
  wire [7:0] caret_rel     = (caret_rel_pre > vis_top) ? vis_top : caret_rel_pre;

  wire [5:0] first_bot = (res_len > VCAP) ? (res_len - VCAP) : 0;
  wire [5:0] vis_bot   = (res_len == 0) ? 0 : ((res_len > VCAP) ? VCAP : res_len);

  // ===============================================================
  // Drawing logic (using virtual layout)
  // ===============================================================
  reg [3:0] fx, fy;
  reg [7:0] idx_vis;  // visual column index
  reg [5:0] idx;
  reg top_text, bot_text, caret_text;
  integer caret_x_left;
  
  // Helper variables for top row rendering
  reg [5:0] buf_i;
  reg [1:0] sub;
  reg [4:0] glyph;

  always @* begin
    px_on_bg   = in_top || in_bot;
    px_on_text = 0;
    top_text = 0; bot_text = 0; caret_text = 0;

    if (in_top && vis_top != 0) begin
      if (x >= PAD_L && x < PAD_L + vis_top*PITCH_TOP &&
          y >= PAD_T && y < PAD_T + CELL_H) begin
        // Compute visual column index
        idx_vis = (x - PAD_L) / PITCH_TOP;
        fx  = x - (PAD_L + idx_vis*PITCH_TOP);
        fy  = y - PAD_T;
        
        // Map visual column to buffer index and sub-glyph
        buf_i = find_buf_i(first_top + idx_vis, len);
        sub   = find_sub(first_top + idx_vis, buf_i);
        glyph = tok_glyph(buffer_bus[5*buf_i +: 5], sub);
        
        if (font_on(glyph, fx, fy))
          top_text = 1;
      end
    end

    // Caret
    if (in_top && caret_enable && caret_phase) begin
      if (y >= PAD_T && y < PAD_T + CELL_H) begin
        caret_x_left = (caret_rel < vis_top)
                       ? (PAD_L + caret_rel*PITCH_TOP)
                       : (PAD_L + vis_top*PITCH_TOP - CARET_W_PX);
        if (x >= caret_x_left && x < caret_x_left + CARET_W_PX)
          caret_text = 1;
      end
    end

    // Bottom row
    if (in_bot && vis_bot != 0) begin
      if (x >= PAD_L && x < PAD_L + vis_bot*CELL_W &&
          y >= (DISP_H - STRIP_H + PAD_B) &&
          y <  (DISP_H - STRIP_H + PAD_B + CELL_H)) begin
        idx = (x - PAD_L) / CELL_W;
        fx  = x - (PAD_L + idx*CELL_W);
        fy  = y - (DISP_H - STRIP_H + PAD_B);
        if (font_on(res_bus[5*(first_bot + idx) +: 5], fx, fy))
          bot_text = 1;
      end
    end

    px_on_text = top_text | bot_text | caret_text;
  end

endmodule
