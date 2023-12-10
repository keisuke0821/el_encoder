`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: kuhep
// Engineer: jsuzuki
// 
// Create Date: 2019/08/23 17:15:03
// Design Name: sync_splitter
// Module Name: sync_splitter
// Project Name: el_encoder
// Target Devices: zybo-z7-20
// Tool Versions: Vivado2018.3
// Description: Split synchronization signal
// 
// Dependencies: Standalone
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sync_splitter #(
    parameter N_DEAD    = 50000, // 1ms for 50MHz clock
    parameter N_DEAD_CW = 16     // log2(50000) < 16
    )(
    input   sync_in,
    input   clk,
    input   rstn,
    output  sync_out,
    output  uart);

    reg                 dead;
    reg                 dead_buf;
    reg [N_DEAD_CW-1:0] dead_cnt;
    
    reg [N_DEAD_CW-1:0] uart_cnt;

    // dead & dead_cnt
    always @(posedge clk) begin
        if (~rstn) begin // reset
            dead <= 1'b0;
            dead_cnt <= 1'b0;
        end else begin
            if (dead == 1'b0) begin
                if (sync_in == 1'b0) begin // enable at falling edge
                    dead <= 1'b1;
                end
            end else if (dead == 1'b1) begin 
                if (dead_cnt < N_DEAD) begin // counter
                    dead_cnt <= dead_cnt + 1'b1;
                end else begin // reset at dead_cnt == N_DEAD
                    dead_cnt <= 1'b0;
                    dead <= 1'b0;
                end
            end
        end
    end
    
    // sync_out
    always @(posedge clk) begin
        if (~rstn) begin
            dead_buf <= 1'b0;
        end else begin
            dead_buf <= dead;
        end
    end    
    assign sync_out = (dead == 1'b1) & (dead_buf == 1'b0);

    // uart
    assign uart = sync_in;

endmodule
