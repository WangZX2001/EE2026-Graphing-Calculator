// ======================= seven_seg (synced graph_mode) =======================
`timescale 1ns / 1ps
// mode 0 = DEC, 1 = BIN, 2 = OCT, 3 = HEX
module seven_seg(
  input  basys_clock,
  input  [1:0] mode,
  input  rst,
  output reg [3:0] an,
  output reg [6:0] seg,
  output reg       dp
);
  // 1 kHz scan clock
  wire _1khz;
  clock_divider u_1khz (.basys_clock(basys_clock), .m(32'd49_999), .desired_CLOCK(_1khz));


  // -------- Scan logic (3 digits only) --------
  reg [1:0] counter;
  always @(posedge _1khz or posedge rst) begin
    if (rst) counter <= 2'd0;
    else     counter <= (counter == 2'd2) ? 2'd0 : counter + 2'd1;
  end

  // 7-seg codes (active-low common-anode assumed, same as your originals)
  localparam b = 7'b000_0011,
             c = 7'b100_0110,
             d = 7'b010_0001,
             e = 7'b000_0110,
             h = 7'b000_1011,
             i = 7'b111_1001,
             n = 7'b010_1011,
             o = 7'b010_0011,
             t = 7'b000_0111,
             x = 7'b000_1001;

  reg [6:0] first_display, second_display, third_display;

  // dp control (keep OFF)
  always @(posedge _1khz or posedge rst) begin
    if (rst) dp <= 1'b1;           // OFF for common anode
    else     dp <= 1'b1;
  end

  // Glyph selection
  always @(posedge _1khz or posedge rst) begin
    if (rst) begin
      first_display  <= 7'b111_1111;
      second_display <= 7'b111_1111;
      third_display  <= 7'b111_1111;
    end else begin
      case (mode)
        2'd1: begin // BIN
          first_display  <= b; second_display <= i; third_display  <= n;
        end
        2'd2: begin // OCT
          first_display  <= o; second_display <= c; third_display  <= t;
        end
        2'd3: begin // HEX
          first_display  <= h; second_display <= e; third_display  <= x;
        end
        default: begin // DEC
          first_display  <= d; second_display <= e; third_display  <= c;
        end
      endcase
    end
  end

  // Mux the digits (active-low anodes)
  always @(posedge _1khz or posedge rst) begin
    if (rst) begin
      an  <= 4'b1111;
      seg <= 7'b111_1111;
    end else begin
      case (counter)
        2'd0: begin an <= 4'b0111; seg <= first_display;  end
        2'd1: begin an <= 4'b1011; seg <= second_display; end
        2'd2: begin an <= 4'b1101; seg <= third_display;  end
        default: begin an <= 4'b1111; seg <= 7'b111_1111; end
      endcase
    end
  end
endmodule
