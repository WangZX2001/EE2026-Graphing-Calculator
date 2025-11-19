// ======================= seq_udiv_64.v =======================
`timescale 1ns/1ps
module seq_udiv_64 #(
    parameter WN = 64,  // Dividend width
    parameter WD = 32,  // Divisor width
    parameter WQ = 64   // Quotient width (normally WN; extra bits allowed)
)(
    input                   clk, rst, start,
    input      [WN-1:0]     dividend,
    input      [WD-1:0]     divisor,
    output                  busy, done,
    output reg [WQ-1:0]     quotient,
    output     [WD-1:0]     remainder
);
    localparam CNTW = $clog2(WQ+1);

    reg                 busy_r, done_r;
    reg [CNTW-1:0]      cnt;               // counts remaining quotient bits
    reg [WN-1:0]        divd_reg;          // shifts left to feed MSBs into remainder
    reg [WD:0]          rem;               // WD+1 bits for subtract/compare
    reg [WD-1:0]        divs_reg;          // latched divisor

    assign busy = busy_r;
    assign done = done_r;
    assign remainder = rem[WD-1:0];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_r   <= 1'b0;
            done_r   <= 1'b0;
            cnt      <= {CNTW{1'b0}};
            divd_reg <= {WN{1'b0}};
            divs_reg <= {WD{1'b0}};
            rem      <= {(WD+1){1'b0}};
            quotient <= {WQ{1'b0}};
        end else begin
            done_r <= 1'b0;

            if (start && !busy_r) begin
                busy_r   <= 1'b1;
                cnt      <= WQ[CNTW-1:0];        // emit WQ bits
                divd_reg <= dividend;
                divs_reg <= divisor;
                rem      <= {(WD+1){1'b0}};      // remainder <- 0
                quotient <= {WQ{1'b0}};
            end else if (busy_r) begin
                if (cnt != 0) begin
                    // bring next dividend MSB into remainder
                    rem      <= {rem[WD-1:0], divd_reg[WN-1]};
                    divd_reg <= {divd_reg[WN-2:0], 1'b0};

                    // try subtract
                    if ({rem[WD-1:0], divd_reg[WN-1]} >= {1'b0, divs_reg}) begin
                        rem      <= { {rem[WD-1:0], divd_reg[WN-1]} - {1'b0, divs_reg} };
                        quotient <= {quotient[WQ-2:0], 1'b1};
                    end else begin
                        quotient <= {quotient[WQ-2:0], 1'b0};
                    end

                    cnt <= cnt - 1'b1;
                end else begin
                    busy_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end
        end
    end
endmodule