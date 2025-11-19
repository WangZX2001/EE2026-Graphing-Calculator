`timescale 1ns/1ps
// ===============================================
//  cordic16_deg.v  (Rotation mode, degrees input)
//  - z scale: 2^14 (ANG_SCALE = 14), x/y: Q16.16
//  - Start x = (1/K) * 2^16 ? 39797 so outputs are unity sin/cos
//  - Zero-angle short-circuit for exact tan(0)=0, etc.
// ===============================================
module cordic16_deg #(
  parameter ANG_SCALE = 14,   // z uses 2^14
  parameter XY_FRAC   = 16    // x,y are Q16.16
)(
  input                    clk,
  input                    rst,
  input                    start,           // 1-cycle
  input  signed [12:0]     deg_in,          // must be in [-90..90]
  output reg               busy,
  output reg               done,            // 1-cycle
  output reg signed [31:0] sin_q16,         // Q16.16
  output reg signed [31:0] cos_q16          // Q16.16
);

  //  deg -> rad scaled by 2^14: floor((pi/180) * 2^14) = 286
  localparam integer DEG2Z   = 286;

  //  Start at 1/K so gain is canceled: round( (1/K) * 2^16 ) ? 39797
  localparam integer X0_INIT = 39797;

  // atan(2^-i) (radians) * 2^14, i=0..14 (15 used)
  function [15:0] atan_lut;
    input [3:0] i;
    begin
      case (i)
        4'd0:  atan_lut = 16'd12868;
        4'd1:  atan_lut = 16'd7596;
        4'd2:  atan_lut = 16'd4014;
        4'd3:  atan_lut = 16'd2037;
        4'd4:  atan_lut = 16'd1024;
        4'd5:  atan_lut = 16'd512;
        4'd6:  atan_lut = 16'd256;
        4'd7:  atan_lut = 16'd128;
        4'd8:  atan_lut = 16'd64;
        4'd9:  atan_lut = 16'd32;
        4'd10: atan_lut = 16'd16;
        4'd11: atan_lut = 16'd8;
        4'd12: atan_lut = 16'd4;
        4'd13: atan_lut = 16'd2;
        4'd14: atan_lut = 16'd1;
        default: atan_lut = 16'd0;
      endcase
    end
  endfunction

  // zero-angle short-circuit threshold
  localparam signed [15:0] Z_EPS = 16'sd2;  // ~0.0069°
  wire signed [31:0] z_tmp = $signed(deg_in) * DEG2Z;

  // FSM
  localparam [1:0] S_IDLE = 2'd0, S_ITER = 2'd1, S_OUT = 2'd2;

  reg [1:0]          st;
  reg signed [31:0]  x, y;      // Q16.16
  reg signed [15:0]  z;         // angle * 2^14
  reg [4:0]          i;         // 0..15

  // temporaries
  reg signed [31:0]  x_next, y_next;
  reg signed [15:0]  z_next;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st <= S_IDLE; busy <= 1'b0; done <= 1'b0;
      x <= 32'sd0; y <= 32'sd0; z <= 16'sd0; i <= 5'd0;
      sin_q16 <= 32'sd0; cos_q16 <= 32'sd0;
    end else begin
      done <= 1'b0; // pulse

      case (st)
        S_IDLE: begin
          if (start) begin
            // exact zero/small angle short-circuit
            if ((z_tmp <= Z_EPS) && (z_tmp >= -Z_EPS)) begin
              busy    <= 1'b0;
              done    <= 1'b1;
              cos_q16 <= 32'sd65536; // 1.0000
              sin_q16 <= 32'sd0;
              st      <= S_IDLE;
            end else begin
              busy <= 1'b1;
              x    <= X0_INIT;     // (1/K) * 2^16
              y    <= 32'sd0;
              z    <= z_tmp[15:0];
              i    <= 5'd0;
              st   <= S_ITER;
            end
          end
        end

        S_ITER: begin
          if (!z[15]) begin
            x_next = x - (y >>> i);
            y_next = y + (x >>> i);
            z_next = z - $signed(atan_lut(i[3:0]));
          end else begin
            x_next = x + (y >>> i);
            y_next = y - (x >>> i);
            z_next = z + $signed(atan_lut(i[3:0]));
          end

          x <= x_next;
          y <= y_next;
          z <= z_next;

          if (i == 5'd15) begin
            st <= S_OUT;
          end else begin
            i  <= i + 5'd1;
          end
        end

        S_OUT: begin
          cos_q16 <= x;
          sin_q16 <= y;
          busy    <= 1'b0;
          done    <= 1'b1;
          st      <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
