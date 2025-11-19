`timescale 1ns/1ps

module keypad_ui(
    input         clk,           // use basys_clock (100 MHz) for logic
    input         rst,           // btnC
    
    // OLED pixel streaming
    input  [12:0] pixel_index,   // from Oled_Display
    output [15:0] pixel_color,   // to Oled_Display
    
    // Mouse
    input         mouse_l,       // left click
    input         mouse_r,       // right click (for cursor toggle)
    input  [11:0] mouse_x,       // 0..95
    input  [11:0] mouse_y,       // 0..63
    
    input         pad_b,         // Toggle Pad_B
    input         frame_begin,   // frame tick for animations
    
    // Delete button
    input         btnD,          // Delete button input
    
    output reg [15:0] led_out,
    output reg       sym_pulse,
    output reg [4:0] sym_code,
    output wire      delete_pulse // Debounced delete pulse output
);

// ----------------------------
// Geometry helpers
// ----------------------------
wire [6:0] col = pixel_index % 96;
wire [6:0] row = pixel_index / 96;

// PAD A 4x4 grid: each cell is 24(w) x 16(h)
wire [1:0] padA_cell_x = col / 24;
wire [1:0] padA_cell_y = row / 16;
wire [5:0] local_x_a   = col % 24; // 0..23
wire [4:0] local_y_a   = row % 16; // 0..15

// PAD B (2x2 grid): each cell is 48(w) x 32(h)
wire [0:0] padB_cell_x = col / 48;  // 0..1
wire [0:0] padB_cell_y = row / 32;  // 0..1
wire [5:0] local_x_b   = col % 48;  // 0..47
wire [5:0] local_y_b   = row % 32;  // 0..31

// Active indices
wire [1:0] cell_x = pad_b ? {1'b0, padB_cell_x} : padA_cell_x;
wire [1:0] cell_y = pad_b ? {1'b0, padB_cell_y} : padA_cell_y;

// Borders (grid lines)
wire on_v_border_a = (local_x_a == 0) || (local_x_a == 23);
wire on_h_border_a = (local_y_a == 0) || (local_y_a == 15);
wire on_border_a   = on_v_border_a || on_h_border_a;

wire on_v_border_b = (col==0 || col==47 || col==95);
wire on_h_border_b = (row==0 || row==31 || row==63);
wire on_border_b   = on_v_border_b || on_h_border_b;

wire on_border = pad_b ? on_border_b : on_border_a;

// Hover highlight
wire hover_a = ((mouse_x/24) == padA_cell_x) && ((mouse_y/16) == padA_cell_y);
wire [0:0] hover_cx2 = (mouse_x < 48) ? 1'd0 : 1'd1;
wire [0:0] hover_cy2 = (mouse_y < 32) ? 1'd0 : 1'd1;
wire       hover_b_  = (hover_cx2 == padB_cell_x) && (hover_cy2 == padB_cell_y);
wire hover = pad_b ? hover_b_ : hover_a;

// ----------------------------
// Map each cell to a symbol code
// codes: 0..9 digits, 10:'+', 11:'-', 12:'x', 13:'/', 14:'=', 15:'.'
// plus pad-B extras
// ----------------------------
reg [4:0] sym;

always @* begin
    if (!pad_b) begin
        // Pad A (4x4)
        case ({cell_y,cell_x})
            4'b00_00: sym=5'd7;  4'b00_01: sym=5'd8;  4'b00_10: sym=5'd9;  4'b00_11: sym=5'd13; // /
            4'b01_00: sym=5'd4;  4'b01_01: sym=5'd5;  4'b01_10: sym=5'd6;  4'b01_11: sym=5'd12; // x
            4'b10_00: sym=5'd1;  4'b10_01: sym=5'd2;  4'b10_10: sym=5'd3;  4'b10_11: sym=5'd11; // -
            4'b11_00: sym=5'd0;  4'b11_01: sym=5'd15; 4'b11_10: sym=5'd14; 4'b11_11: sym=5'd10; // . = +
            default:  sym=5'd0;
        endcase
    end else begin
        // Pad B (2x2)
        case ({cell_y,cell_x})
            4'b0000: sym = 5'd19; // 'sin' (top-left: y=0, x=0)
            4'b0001: sym = 5'd20; // 'cos' (top-right: y=0, x=1)
            4'b0100: sym = 5'd21; // 'tan' (bottom-left: y=1, x=0)
            4'b0101: sym = 5'd16; // 'Y=' (bottom-right: y=1, x=1)
            default : sym = 5'd0;
        endcase
    end
end// 

// Tiny 5x7 font (scaled 2x)
// ----------------------------
function font_on;
    input [4:0] code;
    input [3:0] fx;    // 0..9
    input [3:0] fy;    // 0..13
    reg   [4:0] colmask [0:6];
    integer y;
    begin
        colmask[0]=0; colmask[1]=0; colmask[2]=0; colmask[3]=0; colmask[4]=0; colmask[5]=0; colmask[6]=0;
        case (code)
            5'd0:  begin colmask[0]=5'b11111; colmask[1]=5'b10001; colmask[2]=5'b10011; colmask[3]=5'b10101; colmask[4]=5'b11001; colmask[5]=5'b10001; colmask[6]=5'b11111; end
            5'd1:  begin colmask[0]=5'b00100; colmask[1]=5'b01100; colmask[2]=5'b00100; colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b01110; end
            5'd2:  begin colmask[0]=5'b11110; colmask[1]=5'b00001; colmask[2]=5'b00001; colmask[3]=5'b11110; colmask[4]=5'b10000; colmask[5]=5'b10000; colmask[6]=5'b11111; end
            5'd3:  begin colmask[0]=5'b11110; colmask[1]=5'b00001; colmask[2]=5'b00001; colmask[3]=5'b01110; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11110; end
            5'd4:  begin colmask[0]=5'b10010; colmask[1]=5'b10010; colmask[2]=5'b10010; colmask[3]=5'b11111; colmask[4]=5'b00010; colmask[5]=5'b00010; colmask[6]=5'b00010; end
            5'd5:  begin colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b10000; colmask[3]=5'b11110; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11110; end
            5'd6:  begin colmask[0]=5'b11111; colmask[1]=5'b10000; colmask[2]=5'b10000; colmask[3]=5'b11111; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b11111; end
            5'd7:  begin colmask[0]=5'b11111; colmask[1]=5'b00001; colmask[2]=5'b00010; colmask[3]=5'b00100; colmask[4]=5'b01000; colmask[5]=5'b01000; colmask[6]=5'b01000; end
            5'd8:  begin colmask[0]=5'b01110; colmask[1]=5'b10001; colmask[2]=5'b10001; colmask[3]=5'b01110; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b01110; end
            5'd9:  begin colmask[0]=5'b11111; colmask[1]=5'b10001; colmask[2]=5'b10001; colmask[3]=5'b11111; colmask[4]=5'b00001; colmask[5]=5'b00001; colmask[6]=5'b11111; end
            5'd10: begin colmask[0]=5'b00000; colmask[1]=5'b00100; colmask[2]=5'b00100; colmask[3]=5'b11111; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b00000; end // +
            5'd11: begin colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b11111; colmask[3]=5'b00000; colmask[4]=5'b00000; colmask[5]=5'b00000; colmask[6]=5'b00000; end // -
            5'd12: begin colmask[0]=5'b10001; colmask[1]=5'b01010; colmask[2]=5'b00100; colmask[3]=5'b00100; colmask[4]=5'b01010; colmask[5]=5'b10001; colmask[6]=5'b00000; end // 'x'
            5'd13: begin colmask[0]=5'b00001; colmask[1]=5'b00010; colmask[2]=5'b00100; colmask[3]=5'b01000; colmask[4]=5'b10000; colmask[5]=5'b00000; colmask[6]=5'b00000; end // '/'
            5'd14: begin colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b11111; colmask[3]=5'b00000; colmask[4]=5'b11111; colmask[5]=5'b00000; colmask[6]=5'b00000; end // '='
            5'd15: begin colmask[0]=5'b00000; colmask[1]=5'b00000; colmask[2]=5'b00000; colmask[3]=5'b00100; colmask[4]=5'b00000; colmask[5]=5'b00000; colmask[6]=5'b00000; end // '.'
            5'd16: begin colmask[0]=5'b10001; colmask[1]=5'b01010; colmask[2]=5'b00100; colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b00000; end // 'y'
            5'd19: begin colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10000; colmask[3]=5'b01100; colmask[4]=5'b00010; colmask[5]=5'b11100; colmask[6]=5'b00000; end // 's'
            5'd20: begin colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10000; colmask[3]=5'b10000; colmask[4]=5'b10000; colmask[5]=5'b01110; colmask[6]=5'b00000; end // 'c'
            5'd21: begin colmask[0]=5'b00100; colmask[1]=5'b00100; colmask[2]=5'b11111; colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b00100; colmask[6]=5'b00000; end // 't'
            5'd24: begin colmask[0]=5'b00100; colmask[1]=5'b00000; colmask[2]=5'b01100; colmask[3]=5'b00100; colmask[4]=5'b00100; colmask[5]=5'b01110; colmask[6]=5'b00000; end // 'i'
            5'd25: begin colmask[0]=5'b00000; colmask[1]=5'b10110; colmask[2]=5'b11001; colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b10001; colmask[6]=5'b00000; end // 'n'
            5'd26: begin colmask[0]=5'b00000; colmask[1]=5'b01110; colmask[2]=5'b10001; colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b01110; colmask[6]=5'b00000; end // 'o'
            5'd27: begin colmask[0]=5'b01110; colmask[1]=5'b00001; colmask[2]=5'b01111; colmask[3]=5'b10001; colmask[4]=5'b10001; colmask[5]=5'b01111; colmask[6]=5'b00000; end // 'a'
            default: ; // blank
        endcase
        
        if (fx < 10 && fy < 14) begin
            y       = fy >> 1;
            font_on = colmask[y][4 - (fx >> 1)];
        end else begin
            font_on = 1'b0;
        end
    end
endfunction

// ---------- PAD-A glyph window (24x16 cell, centered 10x14) ----------
wire [3:0] fx_a    = (local_x_a >= 7  && local_x_a < 17) ? (local_x_a - 7)  : 4'hf;
wire [3:0] fy_a    = (local_y_a >= 1  && local_y_a < 15) ? (local_y_a - 1)  : 4'hf;
wire       glyph_a = (fx_a != 4'hf && fy_a != 4'hf) && font_on(sym, fx_a, fy_a);

// ---------- PAD-B multi-character rendering (48x32 cell) ----------
// For "sin", "cos", "tan" (3 chars): each char is 10px wide, total 30px, centered in 48px
// For "Y=" (2 chars): each char is 10px wide, total 20px, centered in 48px
// Vertical: 14px tall, centered in 32px

reg [4:0] char_code_b; // which character to render
reg [3:0] fx_b_local;  // x within the character (0..9)
wire [3:0] fy_b_local = (local_y_b >= 9 && local_y_b < 23) ? (local_y_b - 9) : 4'hf;

always @* begin
    // Default values
    char_code_b = sym;
    fx_b_local = 4'hf;
    
    case (sym)
        5'd19: begin // "sin" - 3 characters, centered at x: 9..38 (30px wide)
            if (local_x_b >= 9 && local_x_b < 19) begin
                char_code_b = 5'd19; // 's'
                fx_b_local = local_x_b - 9;
            end else if (local_x_b >= 19 && local_x_b < 29) begin
                char_code_b = 5'd24; // 'i'
                fx_b_local = local_x_b - 19;
            end else if (local_x_b >= 29 && local_x_b < 39) begin
                char_code_b = 5'd25; // 'n'
                fx_b_local = local_x_b - 29;
            end
        end
        
        5'd20: begin // "cos" - 3 characters with 1px gap between o and s
            if (local_x_b >= 9 && local_x_b < 19) begin
                char_code_b = 5'd20; // 'c'
                fx_b_local = local_x_b - 9;
            end else if (local_x_b >= 19 && local_x_b < 29) begin
                char_code_b = 5'd26; // 'o'
                fx_b_local = local_x_b - 19;
            end else if (local_x_b >= 30 && local_x_b < 40) begin
                char_code_b = 5'd19; // 's' (shifted +1 for gap)
                fx_b_local = local_x_b - 30;
            end
        end
        
        5'd21: begin // "tan" - 't' shifted left 1px, 'n' shifted right 1px
            if (local_x_b >= 8 && local_x_b < 18) begin
                char_code_b = 5'd21; // 't' (shifted -1)
                fx_b_local = local_x_b - 8;
            end else if (local_x_b >= 18 && local_x_b < 28) begin
                char_code_b = 5'd27; // 'a'
                fx_b_local = local_x_b - 18;
            end else if (local_x_b >= 30 && local_x_b < 40) begin
                char_code_b = 5'd25; // 'n' (shifted +1)
                fx_b_local = local_x_b - 30;
            end
        end
        
        5'd16: begin // "Y=" - 2 characters, centered at x: 14..33 (20px wide)
            if (local_x_b >= 14 && local_x_b < 24) begin
                char_code_b = 5'd16; // 'Y'
                fx_b_local = local_x_b - 14;
            end else if (local_x_b >= 24 && local_x_b < 34) begin
                char_code_b = 5'd14; // '='
                fx_b_local = local_x_b - 24;
            end
        end
        
        default: begin
            fx_b_local = 4'hf;
        end
    endcase
end

wire glyph_b = (fx_b_local != 4'hf && fy_b_local != 4'hf) && font_on(char_code_b, fx_b_local, fy_b_local);

// pick the correct one
wire glyph = pad_b ? glyph_b : glyph_a;

// Colors (RGB565)
localparam BLACK     = 16'b00000_000000_00000;
localparam WHITE     = 16'b11111_111111_11111;
localparam GREY      = 16'b10101_101010_10101;
localparam BLUE      = 16'b00000_000000_11111;
localparam LIGHTBLUE = 16'b01011_111001_11111;
localparam YELLOW    = 16'b11111_111111_00000;
localparam GREEN     = 16'b00000_111111_00000;
localparam RED       = 16'b11111_000000_00000;

// ----------------------------
// Blue highlight (last clicked cell) state
// ----------------------------
reg [1:0] last_padA_x, last_padA_y;
reg [1:0] last_padB_x, last_padB_y;
reg [5:0] blue_hl_cnt; // countdown timer

wire is_clicked_A = (blue_hl_cnt != 0) &&
                   (padA_cell_x == last_padA_x) &&
                   (padA_cell_y == last_padA_y);
wire is_clicked_B = (blue_hl_cnt != 0) &&
                   (padB_cell_x == last_padB_x) &&
                   (padB_cell_y == last_padB_y);
wire is_clicked   = pad_b ? is_clicked_B : is_clicked_A;

// Button fill and visual
wire [15:0] bord = BLUE;

// Base color priority: clicked (light blue) > hover (grey) > white
wire [15:0] base = is_clicked ? LIGHTBLUE :
                  (hover ? GREY : WHITE);

// ---- base UI color (grid + glyph + hover/click) ----
wire [15:0] base_color = on_border ? bord : (glyph ? BLACK : base);

// ================== OVERLAYS: cursor + spark ==================

// Enhanced Cursor toggle state with smooth transition animation
reg [1:0] cursor_mode;           // 0 = arrow, 1 = crosshair, 2 = hand
reg [1:0] next_cursor_mode;      // Target cursor mode
reg [5:0] transition_counter;    // Animation counter for smooth transitions
reg       in_transition;        // Flag indicating we're transitioning
reg       mouse_r_d;

wire mouse_r_click = mouse_r & ~mouse_r_d;

// Transition parameters
localparam [5:0] TRANSITION_DURATION = 6'd30; // ~0.5 seconds at 60fps
localparam [5:0] FLASH_DURATION = 6'd10;      // Flash duration during transition

// Cursor outline only (transparent white)
wire [6:0] mcol = (mouse_x > 95) ? 7'd95 : mouse_x[6:0];
wire [6:0] mrow = (mouse_y > 63) ? 7'd63 : mouse_y[6:0];
wire signed [9:0] ax = $signed({1'b0,col}) - $signed({1'b0,mcol});
wire signed [9:0] ay = $signed({1'b0,row}) - $signed({1'b0,mrow});

// Arrow cursor pattern
function [1:0] cursor_mask_black;
    input [4:0] fx; // 0..20 column from tip
    input [4:0] fy; // 0..20 row from tip
    reg mask, black;
    begin
        mask = 1'b0; black = 1'b0;
        case (fy)
            5'd0:  if (fx < 1)  begin mask=1; black=(fx==0); end
            5'd1:  if (fx < 2)  begin mask=1; black=(fx==0 || fx==1); end
            5'd2:  if (fx < 3)  begin mask=1; black=(fx==0 || fx==2); end
            5'd3:  if (fx < 4)  begin mask=1; black=(fx==0 || fx==3); end
            5'd4:  if (fx < 5)  begin mask=1; black=(fx==0 || fx==4); end
            5'd5:  if (fx < 6)  begin mask=1; black=(fx==0 || fx==5); end
            5'd6:  if (fx < 7)  begin mask=1; black=(fx==0 || fx==6); end
            5'd7:  if (fx < 8)  begin mask=1; black=(fx==0 || fx==7); end
            5'd8:  if (fx < 9)  begin mask=1; black=(fx==0 || fx==8); end
            5'd9:  if (fx < 10) begin mask=1; black=(fx==0 || fx==9); end
            5'd10: if (fx < 11) begin mask=1; black=(fx==0 || fx==10); end
            5'd11: if (fx < 12) begin mask=1; black=(fx==0 || (fx>=7 && fx<=11)); end
            5'd12: if (fx < 8)  begin mask=1; black=(fx==0 || fx==4 || fx==7); end
            5'd13: if (fx < 8)  begin mask=1; black=(fx==0 || fx==3 || fx==4 || fx==7); end
            5'd14: if (fx < 9)  begin mask=1; black=(fx==0 || fx==2 || fx==5 || fx==8); end
            5'd15: if (fx < 9)  begin mask=1; black=(fx==0 || fx==1 || fx==5 || fx==8); end
            5'd16: if (fx < 10) begin mask=1; black=(fx==0 || fx==6 || fx==9); end
            5'd17: if (fx < 10) begin mask=1; black=(fx==6 || fx==9); end
            5'd18: if (fx < 11) begin mask=1; black=(fx==7 || fx==10); end
            5'd19: if (fx < 11) begin mask=1; black=(fx==7 || fx==10); end
            5'd20: if (fx < 11) begin mask=1; black=(fx==8 || fx==9); end
            default: begin mask=1'b0; black=1'b0; end
        endcase
        cursor_mask_black = {mask, black};
    end
endfunction

// finger pointer cursor pattern
function [1:0] cursor_hand_mask;
    input [4:0] fx; // 0..21 column from tip
    input [4:0] fy; // 0..21 row from tip
    reg mask, black;
    begin
        mask = 1'b0; black = 1'b0;
        case (fy)
            5'd0:  if (fx < 6)  begin mask=1; black=(fx==4 || fx==5); end
            5'd1:  if (fx < 7)  begin mask=1; black=(fx==3 || fx==6); end
            5'd2:  if (fx < 7)  begin mask=1; black=(fx==3 || fx==6); end
            5'd3:  if (fx < 7)  begin mask=1; black=(fx==3 || fx==6); end
            5'd4:  if (fx < 7)  begin mask=1; black=(fx==3 || fx==6); end
            5'd5:  if (fx < 9)  begin mask=1; black=(fx==3)|| ((fx>=6) && (fx <= 8)); end
            5'd6:  if (fx < 12) begin mask=1; black=(fx==3)|| (fx==6) ||((fx>=9) && (fx<=11)); end
            5'd7:  if (fx < 14) begin mask=1; black=(fx==3 || fx==6 || fx==9 || fx==12 || fx==13); end
            5'd8:  if (fx < 15) begin mask=1; black=(fx==3 || fx==6 || fx==9 || fx==12 || fx==14); end
            5'd9:  if (fx < 16) begin mask=1; black=((fx>=1) && (fx<=3)) || (fx==6) || (fx==9) || (fx==12) || (fx==15); end
            5'd10: if (fx < 16) begin mask=1; black=(fx==0 || fx==3 || fx==12 || fx==15); end
            5'd11: if (fx < 16) begin mask=1; black=(fx==0 || fx==3 ||fx==15); end
            5'd12: if (fx < 16) begin mask=1; black=(fx==0 || fx==3 ||fx==15); end
            5'd13: if (fx < 16) begin mask=1; black=(fx==1 || fx==15); end
            5'd14: if (fx < 16) begin mask=1; black=(fx==1 || fx==15); end
            5'd15: if (fx < 16) begin mask=1; black=(fx==2 || fx==15); end
            5'd16: if (fx < 15) begin mask=1; black=(fx==2 || fx==14); end
            5'd17: if (fx < 15) begin mask=1; black=(fx==3 || fx==14); end
            5'd18: if (fx < 15) begin mask=1; black=(fx==3 || fx==14); end
            5'd19: if (fx < 14) begin mask=1; black=(fx==4 || fx==13); end
            5'd20: if (fx < 14) begin mask=1; black=(fx==4 || fx==13); end
            5'd21: if (fx < 14) begin mask=1; black=(fx>=4 && fx<=13); end
            default: begin mask=1'b0; black=1'b0; end
        endcase
        cursor_hand_mask = {mask, black};
    end
endfunction

// Crosshair cursor pattern (simple + sign)
function crosshair_mask;
    input signed [9:0] dx;  // offset from cursor center
    input signed [9:0] dy;
    reg is_on;
    begin
        // Vertical line: 7 pixels tall, 1 pixel wide
        // Horizontal line: 7 pixels wide, 1 pixel tall
        is_on = ((dx == 0) && (dy >= -3) && (dy <= 3)) ||  // vertical
                ((dy == 0) && (dx >= -3) && (dx <= 3));     // horizontal
        crosshair_mask = is_on;
    end
endfunction

// Enhanced cursor selection with transition effects
wire in_box_arrow = (ay >= 0) && (ay < 21) && (ax >= 0) && (ax <= 20);
wire in_box_hand  = (ay >= 0) && (ay < 22) && (ax >= 0) && (ax <= 15);

wire [1:0] mb_arrow = in_box_arrow ? cursor_mask_black(ax[4:0], ay[4:0]) : 2'b00;
wire [1:0] mb_hand  = in_box_hand  ? cursor_hand_mask(ax[4:0], ay[4:0])  : 2'b00;

wire on_arrow     = mb_arrow[0];
wire on_crosshair = crosshair_mask(ax, ay);
wire on_hand      = mb_hand[0];

// Transition logic for smooth cursor switching
wire [1:0] display_cursor_mode = in_transition ? 
    ((transition_counter < FLASH_DURATION) ? next_cursor_mode : cursor_mode) : 
    cursor_mode;

// Enhanced cursor rendering with transition effects
wire on_outline = (display_cursor_mode == 2'd0) ? on_arrow :
                 (display_cursor_mode == 2'd1) ? on_crosshair : on_hand;

// Add transition flash effect
wire transition_flash = in_transition && (transition_counter < FLASH_DURATION) && 
                       (transition_counter[2:0] < 3'd4); // Flash pattern

wire has_px = on_outline;
wire [15:0] cursor_px = has_px ? 
    (transition_flash ? YELLOW : BLACK) : 16'h0000;

wire [15:0] with_cursor = has_px ? cursor_px : base_color;

// ---- spark (click animation) ----
reg [11:0] spark_x = 0, spark_y = 0;
reg [5:0]  spark_cnt = 0;

wire signed [8:0] sx = $signed({1'b0,col}) - $signed({1'b0,spark_x[6:0]});
wire signed [8:0] sy = $signed({1'b0,row}) - $signed({1'b0,spark_y[6:0]});

function [8:0] abs9;
    input signed [8:0] v;
    begin abs9 = (v < 0) ? -v : v; end
endfunction

localparam [5:0] SPARK_MAX  = 6'd60;
localparam [2:0] SPARK_STEP = 3'd1;

wire [5:0] life     = (spark_cnt > SPARK_MAX) ? SPARK_MAX[5:0] : spark_cnt;
wire [5:0] age      = SPARK_MAX - life;
wire [5:0] radius6  = (age / SPARK_STEP);
wire [3:0] r        = (radius6 > 6'd8) ? 4'd8 : radius6[3:0];

wire show_north = (age >= 0);
wire show_nw    = (age >= SPARK_MAX/3);
wire show_west  = (age >= (2*SPARK_MAX)/3);

wire ray_n  = ((sx ==  0) && (sy <= 0) && (abs9(sy) <= r));
wire ray_nw = ((sx == -sy) && (sx < 0) && (abs9(sx) <= r));
wire ray_w  = ((sy ==  0) && (sx <= 0) && (abs9(sx) <= r));

wire on_arc = (spark_cnt != 0) &&
             ((ray_n && show_north) || (ray_nw && show_nw) || (ray_w && show_west));

localparam [15:0] SPARK = 16'b11010_010001_00010; // bright red

wire [15:0] final_color = on_arc ? SPARK : with_cursor;

assign pixel_color = final_color;

// ----------------------------
// Button debouncing for delete (btnD) and mouse click
// ----------------------------
reg btnD_sync, btnD_prev;           // Synchronizer and edge detection
reg [19:0] btnD_debounce_cnt;       // Debounce counter (~10ms at 100MHz)
reg btnD_stable;                    // Stable button state after debouncing

wire btnD_press = btnD_stable && !btnD_prev;  // Rising edge of stable button
assign delete_pulse = btnD_press;              // Export debounced delete pulse

// Mouse click debouncing
reg mouse_l_sync, mouse_l_stable, mouse_l_stable_prev;
reg [22:0] mouse_l_debounce_cnt;    // Debounce counter for mouse left click (needs 21 bits for 2M)
reg [22:0] click_cooldown;          // Cooldown timer to prevent rapid re-clicks (needs 23 bits for 5M)

wire mouse_l_press_raw = mouse_l_stable && !mouse_l_stable_prev;  // Rising edge of stable mouse click
wire mouse_l_press = mouse_l_press_raw && (click_cooldown == 0);  // Only allow click if cooldown expired

// ----------------------------
// Enhanced Click detection & state updates with smooth transitions
// ----------------------------
reg mouse_l_d;
wire click = mouse_l_press; // use debounced mouse click

reg [11:0] click_x, click_y;
reg [11:0] x_l, y_l;
reg [1:0]  cx, cy;
reg [4:0]  sym_clicked;

// Current-click temps moved to module scope for tool compatibility
reg [11:0] xi, yi;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        mouse_l_d   <= 1'b0;
        mouse_r_d   <= 1'b0;
        cursor_mode <= 2'd0;
        next_cursor_mode <= 2'd0;
        transition_counter <= 6'd0;
        in_transition <= 1'b0;
        led_out     <= 16'h0000;
        click_x     <= 12'd0;
        click_y     <= 12'd0;
        blue_hl_cnt <= 6'd0;
        last_padA_x <= 2'd0; last_padA_y <= 2'd0;
        last_padB_x <= 2'd0; last_padB_y <= 2'd0;
        spark_x     <= 12'd0;
        spark_y     <= 12'd0;
        spark_cnt   <= 6'd0;
        sym_pulse   <= 1'b0;
        sym_code    <= 5'd0;
        xi <= 12'd0; yi <= 12'd0;
        x_l <= 12'd0; y_l <= 12'd0;
        
        // Button debouncing initialization
        btnD_sync <= 1'b0;
        btnD_prev <= 1'b0;
        btnD_stable <= 1'b0;
        btnD_debounce_cnt <= 20'd0;
        
        // Mouse click debouncing initialization
        mouse_l_sync <= 1'b0;
        mouse_l_stable <= 1'b0;
        mouse_l_stable_prev <= 1'b0;
        mouse_l_debounce_cnt <= 23'd0;
        click_cooldown <= 23'd0;
    end else begin
        mouse_l_d <= mouse_l;          // edge-detect register
        mouse_r_d <= mouse_r;          // edge-detect for right click
        sym_pulse <= 1'b0;             // default

        // Button debouncing logic for delete
        btnD_sync <= btnD;
        btnD_prev <= btnD_stable;

        // Debounce: require button to be stable for ~10ms
        if (btnD_sync == btnD_stable) begin
            btnD_debounce_cnt <= 20'd0;
        end else begin
            if (btnD_debounce_cnt < 20'd1000000) begin  // 10ms at 100MHz
                btnD_debounce_cnt <= btnD_debounce_cnt + 1'b1;
            end else begin
                btnD_stable <= btnD_sync;
                btnD_debounce_cnt <= 20'd0;
            end
        end
        
        // Mouse click debouncing logic
        mouse_l_sync <= mouse_l;
        mouse_l_stable_prev <= mouse_l_stable;
        
        // Debounce: require mouse click to be stable for ~20ms (increased for better reliability)
        if (mouse_l_sync == mouse_l_stable) begin
            mouse_l_debounce_cnt <= 23'd0;
        end else begin
            if (mouse_l_debounce_cnt < 23'd2000000) begin  // 20ms at 100MHz
                mouse_l_debounce_cnt <= mouse_l_debounce_cnt + 1'b1;
            end else begin
                mouse_l_stable <= mouse_l_sync;
                mouse_l_debounce_cnt <= 23'd0;
            end
        end
        
        // Click cooldown timer - prevents rapid re-clicks
        if (click_cooldown > 0) begin
            click_cooldown <= click_cooldown - 1'b1;
        end
        
        // Start cooldown when a click is registered (50ms cooldown at 100MHz)
        if (mouse_l_press) begin
            click_cooldown <= 23'd5000000;  // 50ms cooldown
        end

        // Enhanced cursor mode cycling with smooth transitions
        if (mouse_r_click && !in_transition) begin
            next_cursor_mode <= (cursor_mode == 2'd2) ? 2'd0 : cursor_mode + 2'd1;
            in_transition <= 1'b1;
            transition_counter <= TRANSITION_DURATION;
        end

        // Handle transition animation
        if (in_transition) begin
            if (frame_begin) begin
                if (transition_counter > 0) begin
                    transition_counter <= transition_counter - 1'b1;
                end else begin
                    cursor_mode <= next_cursor_mode;
                    in_transition <= 1'b0;
                end
            end
        end

        // decay animations on frame ticks
        if (frame_begin && spark_cnt   != 0) spark_cnt   <= spark_cnt - 1;
        if (frame_begin && blue_hl_cnt != 0) blue_hl_cnt <= blue_hl_cnt - 1;

        if (click) begin
            // ---- use blocking temps for this cycle's coords ----
            xi = (mouse_x > 95) ? 12'd95 : mouse_x;
            yi = (mouse_y > 63) ? 12'd63 : mouse_y;

            // optional: store for debug with non-blocking
            x_l     <= xi;
            y_l     <= yi;
            click_x <= xi;
            click_y <= yi;

            // spark start
            spark_x   <= xi;
            spark_y   <= yi;
            spark_cnt <= SPARK_MAX;

            if (!pad_b) begin
                // PAD A (4x4) decode using xi/yi (current click)
                cx = (xi < 24) ? 2'd0 : (xi < 48) ? 2'd1 : (xi < 72) ? 2'd2 : 2'd3;
                cy = (yi < 16) ? 2'd0 : (yi < 32) ? 2'd1 : (yi < 48) ? 2'd2 : 2'd3;

                case ({cy, cx})
                    4'b00_00: sym_clicked = 5'd7;
                    4'b00_01: sym_clicked = 5'd8;
                    4'b00_10: sym_clicked = 5'd9;
                    4'b00_11: sym_clicked = 5'd13; // '/'
                    4'b01_00: sym_clicked = 5'd4;
                    4'b01_01: sym_clicked = 5'd5;
                    4'b01_10: sym_clicked = 5'd6;
                    4'b01_11: sym_clicked = 5'd12; // 'x'
                    4'b10_00: sym_clicked = 5'd1;
                    4'b10_01: sym_clicked = 5'd2;
                    4'b10_10: sym_clicked = 5'd3;
                    4'b10_11: sym_clicked = 5'd11; // '-'
                    4'b11_00: sym_clicked = 5'd0;  // '0'
                    4'b11_01: sym_clicked = 5'd15; // '.'
                    4'b11_10: sym_clicked = 5'd14; // '='
                    4'b11_11: sym_clicked = 5'd10; // '+'
                    default : sym_clicked = 5'd0;
                endcase

                // record last clicked A cell (same cycle)
                last_padA_x <= cx;
                last_padA_y <= cy;
            end else begin
                // PAD B (2x2) decode using xi/yi (current click)
                cx = (xi < 48) ? 2'd0 : 2'd1;
                cy = (yi < 32) ? 2'd0 : 2'd1;

                case ({cy,cx})
                    4'b0000: sym_clicked = 5'd19; // 'sin' (top-left: y=0, x=0)
                    4'b0001: sym_clicked = 5'd20; // 'cos' (top-right: y=0, x=1)
                    4'b0100: sym_clicked = 5'd21; // 'tan' (bottom-left: y=1, x=0)
                    4'b0101: sym_clicked = 5'd16; // 'Y=' (bottom-right: y=1, x=1)
                    default : sym_clicked = 5'd0;
                endcase

                // record last clicked B cell (same cycle)
                last_padB_x <= cx;
                last_padB_y <= cy;
            end

            // restart blue highlight (no lag)
            blue_hl_cnt <= 6'd63;

            // emit one-cycle symbol pulse now
            sym_code  <= sym_clicked;
            sym_pulse <= 1'b1;
        end
    end
end

endmodule