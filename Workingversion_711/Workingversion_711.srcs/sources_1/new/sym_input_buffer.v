`timescale 1ns/1ps
// Appends each accepted symbol (MS-first left-to-right) for the top strip.
module sym_input_buffer #(
  parameter MAX_LEN = 32
)(
  input                    basys_clock,
  input                    rst,
  input                    sym_pulse,
  input             [4:0]  sym_code,
  input                    delete_pulse,
  output reg        [5:0]  len,
  output                   full,
  output                   empty,
  output reg [5*MAX_LEN-1:0] buffer_bus
);
  assign full  = (len == MAX_LEN[5:0]);
  assign empty = (len == 6'd0);

  always @(posedge basys_clock or posedge rst) begin
    if (rst) begin
      len <= 6'd0;
      buffer_bus <= {5*MAX_LEN{1'b0}};
    end else if (delete_pulse && !empty) begin
      // Delete last character - clear the slot at current last position
      buffer_bus[5*len-5 +: 5] <= 5'd0; // clear at index (len-1)
      len <= len - 1'b1;
    end else if (sym_pulse && !full) begin
      // Normal append
      buffer_bus[5*len +: 5] <= sym_code; // place at next slot
      len <= len + 1'b1;
    end
  end
endmodule
