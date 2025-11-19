`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.11.2025 21:15:12
// Design Name: 
// Module Name: Graph_Plot
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


//almost runnable
//module Graph_Plot(
//    input [12:0] pixel_index, 
//    input signed [31:0] a, b, c, d,   // 32-bit coefficients
//    input [6:0] x_origin, y_origin,
//    input [3:0] X_SCALE, Y_SCALE,     // scaling for X and Y axes
//    output reg [15:0] pixel_data
//);

//    // Screen coordinates
//    integer x_pixel, y_pixel;

//    // Math coordinates
//    reg signed [31:0] x_math;
//    reg signed [63:0] y_math, prev_y_math;
//    integer y_pos, prev_y_pos;
//    integer dy;
//    reg valid_point, valid_prev;

//    // ---------------- Polynomial function ----------------
//    function signed [63:0] poly;
//        input signed [31:0] a, b, c, d;
//        input signed [31:0] x;
//        reg signed [63:0] term_a, term_b, term_c;
//    begin
//        term_a = a * x * x * x;
//        term_b = b * x * x;
//        term_c = c * x;
//        poly   = term_a + term_b + term_c + d;
//    end
//    endfunction

//    // ---------------- Main plotting ----------------
//    always @(*) begin
//        // Map pixel index to screen coordinates
//        x_pixel = pixel_index % 96;
//        y_pixel = pixel_index / 96;

//        // Convert screen X to math X, apply X scaling
//        x_math = (x_pixel - $signed(x_origin)) >>> X_SCALE;

//        // Compute polynomial at current and previous X
//        y_math      = poly(a, b, c, d, x_math) >>> Y_SCALE;
//        prev_y_math = poly(a, b, c, d, x_math - 1) >>> Y_SCALE;

//        // Convert math Y to screen Y positions (unclamped)
//        y_pos      = $signed(y_origin) - y_math;
//        prev_y_pos = $signed(y_origin) - prev_y_math;

//        // Default background
//        pixel_data = 16'h0000;

//        // Draw axes
//        if (x_pixel == x_origin || y_pixel == y_origin)
//            pixel_data = 16'hFFFF;

//        // Draw axis arrowheads
//        if ((x_pixel == 94 && y_pixel == y_origin) ||
//            (x_pixel == 95 && (y_pixel == y_origin - 1 || y_pixel == y_origin + 1)) ||
//            (y_pixel == 1 && x_pixel == x_origin) ||
//            (y_pixel == 0 && (x_pixel == x_origin - 1 || x_pixel == x_origin + 1)))
//            pixel_data = 16'hFFFF;

//        // Draw graph line segment if partially visible
//        valid_point = (y_pos >= 0 && y_pos <= 63);
//        valid_prev  = (prev_y_pos >= 0 && prev_y_pos <= 63);

//        if ((valid_point || valid_prev)) begin
//            begin
//                if ((y_pixel >= prev_y_pos && y_pixel <= y_pos) ||
//                   (y_pixel >= y_pos && y_pixel <= prev_y_pos))
//                   pixel_data = 16'hF800;  // red
//            end
//        end
//    end
//endmodule


//works perfectly(but line is not consistent have gaps
//module Graph_Plot(
//    input  [12:0]         pixel_index, 
//    input  signed [31:0]  a, b, c, d,   // 32-bit coefficients
//    input  [6:0]          x_origin, y_origin,
//    input  [3:0]          X_SCALE, Y_SCALE, // scaling for X and Y axes
//    output reg [15:0]     pixel_data
//);
//    // ---------------- Screen coordinates ----------------
//    integer x_pixel, y_pixel;

//    // ---------------- Fixed-point config ----------------
//    localparam integer FRAC = 8;                      // Q*.8 for x
//    localparam integer Q025 = (1 << (FRAC-2));        // +0.25 in Q*.8
//    // We'll sample at (x + 0.25) and (x + 0.75) ? left/right sub-pixels per column

//    // ---------------- Horner in fixed-point (Q0 output) ----------------
//    function signed [63:0] poly_q; // ((((a*x)+b)*x+c)*x+d), with >>FRAC after each mul
//        input signed [31:0] a, b, c, d;
//        input signed [63:0] xq; // Q*.FRAC
//        reg   signed [63:0] t;
//    begin
//        t = ( $signed(a) * xq ) >>> FRAC; // Q0
//        t = t + $signed(b);
//        t = ( t * xq ) >>> FRAC;          // Q0
//        t = t + $signed(c);
//        t = ( t * xq ) >>> FRAC;          // Q0
//        poly_q = t + $signed(d);          // Q0
//    end
//    endfunction

//    // Sub-sample math-x in fixed-point
//    reg signed [63:0] xq_L, xq_R;     // Q*.FRAC
//    reg signed [63:0] yL_q0, yR_q0;   // Q0 (after Horner)
//    integer yL, yR;                   // screen-space Y
//    integer ymin, ymax;

//    // ---------------- Main plotting ----------------
//    always @(*) begin
//        // Map pixel index to screen coordinates (96x64)
//        x_pixel = pixel_index % 96;
//        y_pixel = pixel_index / 96;

//        // Default background
//        pixel_data = 16'h0000;

//        // Axes (draw first; curve can overwrite if desired)
//        if (x_pixel == x_origin || y_pixel == y_origin)
//            pixel_data = 16'hFFFF;

//        // Axis arrowheads
//        if ((x_pixel == 94 && y_pixel == y_origin) ||
//            (x_pixel == 95 && (y_pixel == y_origin - 1 || y_pixel == y_origin + 1)) ||
//            (y_pixel == 1  && x_pixel == x_origin) ||
//            (y_pixel == 0  && (x_pixel == x_origin - 1 || x_pixel == x_origin + 1)))
//            pixel_data = 16'hFFFF;

//        // --------- 2-tap supersampling within the SAME column ---------
//        // Build fixed-point x for ~0.25 and ~0.75 positions, then apply X_SCALE.
//        // Left sub-sample near x_pixel + 0.25
//        xq_L = ( ( $signed(x_pixel)   - $signed(x_origin) ) <<< FRAC ) + Q025;
//        xq_L = xq_L >>> X_SCALE;

//        // Right sub-sample near x_pixel + 0.75  == (x_pixel+1 - 0.25)
//        xq_R = ( ( $signed(x_pixel+1) - $signed(x_origin) ) <<< FRAC ) - Q025;
//        xq_R = xq_R >>> X_SCALE;

//        // Evaluate cubic and scale Y
//        yL_q0 = poly_q(a,b,c,d,xq_L) >>> Y_SCALE;    // still Q0
//        yR_q0 = poly_q(a,b,c,d,xq_R) >>> Y_SCALE;

//        // Convert math Y -> screen Y (origin at y_origin, screen grows downward)
//        yL = $signed(y_origin) - yL_q0;
//        yR = $signed(y_origin) - yR_q0;

//        // Compute tiny vertical span for this column and clamp to screen
//        ymin = (yL < yR) ? yL : yR;
//        ymax = (yL < yR) ? yR : yL;
//        if (ymin < 0)  ymin = 0;
//        if (ymax > 63) ymax = 63;

//        // Draw the column's thin segment (or single pixel if yL == yR)
//        if (y_pixel >= ymin && y_pixel <= ymax)
//            pixel_data = 16'hF800;  // red
//    end
//endmodule


//add intercept + x
module Graph_Plot(
    input  [12:0]         pixel_index, 
    input  signed [31:0]  a, b, c, d,   // 32-bit coefficients
    input  [6:0]          x_origin, y_origin,
    input  [3:0]          X_SCALE, Y_SCALE, // scaling for X and Y axes
    output reg [15:0]     pixel_data
);
    // ---------------- Screen coordinates ----------------
    integer x_pixel, y_pixel;

    // ---------------- Fixed-point config ----------------
    localparam integer FRAC = 8;                      // Q*.8 for x
    localparam integer Q025 = (1 << (FRAC-2));        // +0.25 in Q*.8
    localparam integer EPS0 = 1;                      // tolerance for zero detection

    // ---------------- Intercept "x" size (radius in pixels) ----------------
    // 1 -> 3x3 "x"; 2 -> 5x5 "x"
    localparam integer MARK_HALF_XINT = 1;
    localparam integer MARK_HALF_YINT = 1;

    // ---------------- Colors ----------------
    localparam [15:0] COL_BG     = 16'h0000; // black
    localparam [15:0] COL_AXIS   = 16'hFFFF; // white
    localparam [15:0] COL_CURVE  = 16'hF800; // red
    localparam [15:0] COL_XINT   = 16'h07E0; // green
    localparam [15:0] COL_YINT   = 16'hFFE0; // yellow

    // ---------------- Horner polynomial evaluation ----------------
    function signed [63:0] poly_q;
        input signed [31:0] a, b, c, d;
        input signed [63:0] xq; // Q*.FRAC
        reg   signed [63:0] t;
    begin
        t = ( $signed(a) * xq ) >>> FRAC;
        t = t + $signed(b);
        t = ( t * xq ) >>> FRAC;
        t = t + $signed(c);
        t = ( t * xq ) >>> FRAC;
        poly_q = t + $signed(d);
    end
    endfunction

    // ---------------- Sub-sample variables ----------------
    reg signed [63:0] xq_L, xq_R;
    reg signed [63:0] yL_q0, yR_q0;
    integer yL, yR;
    integer ymin, ymax;

    // ---------------- X-intercept detection ----------------
    reg signed [63:0] xq_prev;
    reg signed [63:0] y_prev_q0;
    reg x_intercept_here;
    integer x_int_col;  // column where x-intercept occurs

    // ---------------- Y-intercept computation ----------------
    reg  signed [63:0] y0_q0;
    integer y0;

    // temp for drawing "x" shape
    integer dx, dy, adx, ady;
    integer cx2, cy2, dx2, dy2, adx3, ady3;
    integer cx, cy, ddx, ddy, adx2, ady2;

    // ---------------- Main plotting ----------------
    always @(*) begin
        // Map pixel index to screen coordinates (96x64)
        x_pixel = pixel_index % 96;
        y_pixel = pixel_index / 96;

        // Default background
        pixel_data = COL_BG;

        // Axes
        if (x_pixel == x_origin || y_pixel == y_origin)
            pixel_data = COL_AXIS;

        // Axis arrowheads
        if ((x_pixel == 94 && y_pixel == y_origin) ||
            (x_pixel == 95 && (y_pixel == y_origin - 1 || y_pixel == y_origin + 1)) ||
            (y_pixel == 1  && x_pixel == x_origin) ||
            (y_pixel == 0  && (x_pixel == x_origin - 1 || x_pixel == x_origin + 1)))
            pixel_data = COL_AXIS;

        // -------- Supersampling for smoother curve --------
        xq_L = ( ( $signed(x_pixel)   - $signed(x_origin) ) <<< FRAC ) + Q025;
        xq_L = xq_L >>> X_SCALE;

        xq_R = ( ( $signed(x_pixel+1) - $signed(x_origin) ) <<< FRAC ) - Q025;
        xq_R = xq_R >>> X_SCALE;

        // Evaluate polynomial
        yL_q0 = poly_q(a,b,c,d,xq_L) >>> Y_SCALE;
        yR_q0 = poly_q(a,b,c,d,xq_R) >>> Y_SCALE;

        // Convert math Y -> screen Y
        yL = $signed(y_origin) - yL_q0;
        yR = $signed(y_origin) - yR_q0;

        // Clamp
        ymin = (yL < yR) ? yL : yR;
        ymax = (yL < yR) ? yR : yL;
        if (ymin < 0)  ymin = 0;
        if (ymax > 63) ymax = 63;

        // Draw red curve
        if (y_pixel >= ymin && y_pixel <= ymax)
            pixel_data = COL_CURVE;

        // -------- X-intercept detection (where curve crosses y=0) --------
        xq_prev   = ( ( $signed(x_pixel-1) - $signed(x_origin) ) <<< FRAC ) >>> X_SCALE;
        y_prev_q0 = poly_q(a,b,c,d,xq_prev) >>> Y_SCALE;
        
        x_intercept_here = 0;
        if ((y_prev_q0 > EPS0 && yL_q0 < -EPS0) || (y_prev_q0 < -EPS0 && yL_q0 > EPS0)) begin
            x_intercept_here = 1;
        end else if ((yL_q0 > EPS0 && yR_q0 < -EPS0) || (yL_q0 < -EPS0 && yR_q0 > EPS0)) begin
            if (!((y_prev_q0 > EPS0 && yL_q0 > EPS0) || (y_prev_q0 < -EPS0 && yL_q0 < -EPS0))) begin
                x_intercept_here = 1;
            end
        end else if ((yL_q0 >= -EPS0 && yL_q0 <= EPS0) && 
                     !((y_prev_q0 >= -EPS0 && y_prev_q0 <= EPS0))) begin
            x_intercept_here = 1;
        end
        
         //Draw green vertical tick at x-intercept (3 pixels tall)
        if (x_intercept_here) begin
            if ((y_pixel >= (y_origin - MARK_HALF_XINT)) && (y_pixel <= (y_origin + MARK_HALF_XINT)))
                pixel_data = COL_XINT;
        end

        // -------- Y-intercept marker (where curve crosses x=0) --------
        y0_q0 = $signed(d) >>> Y_SCALE;      // f(0) = d, then scale
        y0    = $signed(y_origin) - y0_q0;

        // Draw small yellow "x" centered at (x_origin, y0)
        begin
            cx2 = x_origin;
            cy2 = y0;
            dx2 = x_pixel - cx2;
            dy2 = y_pixel - cy2;
            adx3 = (dx2 < 0) ? -dx2 : dx2;
            ady3 = (dy2 < 0) ? -dy2 : dy2;
            if ((adx3 == ady3) && (adx3 <= MARK_HALF_YINT))
                pixel_data = COL_YINT;
        end
    end
endmodule
