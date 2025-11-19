`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.10.2025 09:53:00
// Design Name: 
// Module Name: Clock_divider
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


//clock divider
module clock_divider (input basys_clock, input [31:0] m, output reg desired_CLOCK = 0);  

    reg [31:0] COUNT = 0;
   
    always @ (posedge basys_clock) 
    begin          
    COUNT <= (COUNT == m ) ? 0 : COUNT +1;  
    desired_CLOCK <= ( COUNT == 0 ) ? ~desired_CLOCK : desired_CLOCK;

    end
     
endmodule
