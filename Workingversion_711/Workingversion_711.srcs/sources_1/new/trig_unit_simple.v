`timescale 1ns/1ps
// =====================================================
//  trig_unit_simple.v  (FINAL with robust sign emit)
//  - Clean quadrant reduction (cos flips in Q2/Q3)
//  - Sin/Cos to 4 d.p. with half-up rounding
//  - Tan via seq_udiv_64: (|sin|*1e4 + |cos|/2)/|cos|
//  - On emit: sign derived from final magnitude to avoid missed '-'
// =====================================================
module trig_unit_simple #(
  parameter integer WIDTH       = 32,
  parameter integer DEC_PLACES  = 4,   // prints 4 d.p.
  parameter integer TAN_EPS     = 64   // ~0.001 in Q16.16 (unity ? 65536)
)(
  input                   clk,
  input                   rst,
  input                   sym_pulse,
  input       [4:0]       sym_code,

  output reg  [WIDTH-1:0] res_mag,
  output reg              res_neg,
  output reg  [15:0]      res_low16,
  output reg              res_valid,
  output reg              overflow,
  output reg              div_by_zero,

  output      [3:0]       res_scale,
  output                  res_is_decimal
);

  assign res_scale      = 4;
  assign res_is_decimal = 1'b1;

  // ---------- decode ----------
  wire is_digit = (sym_code <= 5'd9);
  wire is_minus = (sym_code == 5'd11);
  wire is_equal = (sym_code == 5'd14);
  wire is_sin   = (sym_code == 5'd19);
  wire is_cos   = (sym_code == 5'd20);
  wire is_tan   = (sym_code == 5'd21);

  // ---------- parser ----------
  reg [1:0]  operation;      // 1=sin, 2=cos, 3=tan
  reg        has_operation;
  reg        angle_negative;
  reg [11:0] angle_value;    // 0..999

  wire signed [12:0] angle_deg =
    angle_negative ? -$signed({1'b0, angle_value}) : $signed({1'b0, angle_value});

  // normalize to (-180, 180]
  wire signed [12:0] angle_norm =
    (angle_deg >  13'sd180)  ? (angle_deg - 13'sd360) :
    (angle_deg <= -13'sd180) ? (angle_deg + 13'sd360) : angle_deg;

  // quadrant reduce to [-90, 90]; track cos flip only
  reg  signed [12:0] cordic_angle;
  reg                cos_flip;

  always @* begin
    cordic_angle = angle_norm;
    cos_flip     = 1'b0;

    if (angle_norm >= 13'sd0 && angle_norm <= 13'sd90) begin
      cordic_angle = angle_norm;                 // Q1
    end else if (angle_norm > 13'sd90 && angle_norm <= 13'sd180) begin
      cordic_angle = 13'sd180 - angle_norm;      // Q2 (cos neg)
      cos_flip     = 1'b1;
    end else if (angle_norm >= -13'sd90 && angle_norm < 13'sd0) begin
      cordic_angle = angle_norm;                 // Q4
    end else begin
      cordic_angle = -(13'sd180 + angle_norm);   // Q3 (cos neg)
      cos_flip     = 1'b1;
    end
  end

  // latch calc trigger & op
  reg        calc_trig;
  reg [1:0]  op_latched;
  reg        cos_flip_latched;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      operation         <= 2'd0;
      has_operation     <= 1'b0;
      angle_negative    <= 1'b0;
      angle_value       <= 12'd0;
      calc_trig         <= 1'b0;
      op_latched        <= 2'd0;
      cos_flip_latched  <= 1'b0;
    end else begin
      calc_trig <= 1'b0;

      if (sym_pulse) begin
        if (!has_operation && (is_sin || is_cos || is_tan)) begin
          operation      <= is_sin ? 2'd1 : (is_cos ? 2'd2 : 2'd3);
          has_operation  <= 1'b1;
          angle_negative <= 1'b0;
          angle_value    <= 12'd0;
        end else if (has_operation && angle_value == 12'd0 && is_minus) begin
          angle_negative <= 1'b1;
        end else if (has_operation && is_digit) begin
          if (angle_value < 12'd100)
            angle_value <= (angle_value * 10) + sym_code[3:0];
        end else if (has_operation && is_equal) begin
          calc_trig        <= 1'b1;
          op_latched       <= operation;
          cos_flip_latched <= cos_flip;
        end
      end
    end
  end

  // ---------- CORDIC ----------
  wire               cordic_busy, cordic_done;
  wire signed [31:0] cordic_sin, cordic_cos;
  reg                cordic_start;

  always @(posedge clk or posedge rst) begin
    if (rst) cordic_start <= 1'b0;
    else     cordic_start <= calc_trig;
  end

  // Q16.16 outputs
  cordic16_deg u_cordic (
    .clk     (clk),
    .rst     (rst),
    .start   (cordic_start),
    .deg_in  (cordic_angle),
    .busy    (cordic_busy),
    .done    (cordic_done),
    .sin_q16 (cordic_sin),
    .cos_q16 (cordic_cos)
  );

  // signs & magnitudes from CORDIC
  wire        sin_neg_c  = cordic_sin[31];
  wire        cos_neg_c  = cordic_cos[31];
  wire [31:0] sin_mag_q  = sin_neg_c ? (~cordic_sin + 1) : cordic_sin;
  wire [31:0] cos_mag_q  = cos_neg_c ? (~cordic_cos + 1) : cordic_cos;

  // final signs (pre-emit logic)
  wire sin_sign_logic = sin_neg_c;                      // sin on [-90..90]
  wire cos_sign_logic = cos_neg_c ^ cos_flip_latched;   // cos flipped in Q2/Q3
  wire tan_sign_logic = sin_sign_logic ^ cos_sign_logic;

  // 4 dp half-up for sin/cos
  wire [48:0] sin_mul = sin_mag_q * 17'd10000;
  wire [48:0] cos_mul = cos_mag_q * 17'd10000;
  wire [31:0] sin_dec = (sin_mul + 49'd32768) >> 16;
  wire [31:0] cos_dec = (cos_mul + 49'd32768) >> 16;

  // ---------- TAN via existing divider ----------
  wire [63:0] tan_num = (sin_mag_q * 64'd10000) + (cos_mag_q >> 1); // half-up
  reg         t_start;
  wire        t_busy, t_done;
  wire [63:0] t_quot;
  wire [31:0] t_rem;

  seq_udiv_64 #(.WN(64), .WD(32), .WQ(64)) tan_div (
    .clk       (clk),
    .rst       (rst),
    .start     (t_start),
    .dividend  (tan_num),
    .divisor   (cos_mag_q),
    .busy      (t_busy),
    .done      (t_done),
    .quotient  (t_quot),
    .remainder (t_rem)
  );

  // ---------------- Main FSM ----------------
  localparam ST_IDLE = 2'd0, ST_DIV = 2'd1, ST_OUT = 2'd2;

  reg [1:0] state;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= ST_IDLE;
      res_valid   <= 1'b0;
      res_mag     <= 32'd0;
      res_neg     <= 1'b0;
      res_low16   <= 16'd0;
      overflow    <= 1'b0;
      div_by_zero <= 1'b0;
      t_start     <= 1'b0;
    end else begin
      res_valid <= 1'b0;
      t_start   <= 1'b0;   // default

      case (state)
        // ---------------- IDLE ----------------
        ST_IDLE: begin
          if (cordic_done) begin
            overflow    <= 1'b0;
            div_by_zero <= 1'b0;

            case (op_latched)
              2'd1: begin // SIN
                // compute final sign from magnitude (avoid "-0")
                res_mag   <= sin_dec;
                res_neg   <= (sin_dec != 32'd0) ? sin_sign_logic : 1'b0;
                res_low16 <= sin_dec[15:0];
                res_valid <= 1'b1;
                state     <= ST_OUT;
              end

              2'd2: begin // COS
                res_mag   <= cos_dec;
                res_neg   <= (cos_dec != 32'd0) ? cos_sign_logic : 1'b0;
                res_low16 <= cos_dec[15:0];
                res_valid <= 1'b1;
                state     <= ST_OUT;
              end

              default: begin // TAN
                if (cos_mag_q < TAN_EPS) begin
                  // near-vertical
                  div_by_zero <= 1'b1;
                  overflow    <= 1'b1;
                  res_neg     <= 1'b0;
                  res_mag     <= 32'hFFFF_FFFF;
                  res_low16   <= 16'hFFFF;
                  res_valid   <= 1'b1;
                  state       <= ST_OUT;
                end else 
                begin
                  t_start <= 1'b1;       // kick divider
                  state   <= ST_DIV;
                end
              end
            endcase
          end
        end

        // ---------------- DIV (wait divider) ----------------
        ST_DIV: begin
          if (t_done) begin
            // magnitude done (already ×10^4)
            res_mag   <= t_quot[31:0];
            res_neg   <= (t_quot[31:0] != 32'd0) ? tan_sign_logic : 1'b0;
            res_low16 <= t_quot[15:0];
            res_valid <= 1'b1;
            overflow  <= |t_quot[63:32];  // coarse saturation flag
            state     <= ST_OUT;
          end
        end

        // ---------------- OUT ----------------
        ST_OUT: begin
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
