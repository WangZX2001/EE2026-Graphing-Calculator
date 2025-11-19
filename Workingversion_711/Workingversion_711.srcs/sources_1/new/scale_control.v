`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.11.2025 22:19:06
// Design Name: 
// Module Name: scale_control
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


// ======================= scale_control (edge-triggered, graph_mode-gated) =======================
module scale_control(
    input        clk,                 // use your 1 kHz (or similar) slow clock
    input        rst,                      // active-high reset (e.g., btnC | state reset)
    input        graph_mode,               // only allow scaling in graph mode
    input        btnU, btnD, btnL, btnR,   // raw buttons (already synced to clk_1khz, or slow enough)
    output reg [4:0] X_SCALE = 5'd2,       // defaults: X=2, Y=0 (same as your snippet)
    output reg [4:0] Y_SCALE = 5'd0
);

  // previous button states for rising-edge detection
  reg prevU = 1'b0, prevD = 1'b0, prevL = 1'b0, prevR = 1'b0;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      // reset to defaults and clear edge history
      X_SCALE <= 5'd2;
      Y_SCALE <= 5'd0;
      prevU   <= 1'b0;
      prevD   <= 1'b0;
      prevL   <= 1'b0;
      prevR   <= 1'b0;
    end else begin
      // only react to edges in graph mode
      if (graph_mode) begin
        // HORIZ (X): L = zoom out (coarser, scale+), R = zoom in (finer, scale-)
        if (btnL && !prevL && X_SCALE < 5'd4) X_SCALE <= X_SCALE + 5'd1;
        if (btnR && !prevR && X_SCALE > 5'd0) X_SCALE <= X_SCALE - 5'd1;

        // VERT (Y): U = zoom out (coarser, scale+), D = zoom in (finer, scale-)
        if (btnU && !prevU && Y_SCALE < 5'd4) Y_SCALE <= Y_SCALE + 5'd1;
        if (btnD && !prevD && Y_SCALE > 5'd0) Y_SCALE <= Y_SCALE - 5'd1;
      end

      // update edge history
      prevU <= btnU;
      prevD <= btnD;
      prevL <= btnL;
      prevR <= btnR;
    end
  end

endmodule
