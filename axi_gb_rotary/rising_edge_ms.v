`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2018 05:14:37 PM
// Design Name: 
// Module Name: rising_edge_ms
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


module rising_edge_ms(
    input wire raw_sig,
    input wire clk_50M,
    input wire arstn,
    output wire rising_edge
    );
    
    reg [16:0] clk_counter;
    wire clk_max = (clk_counter == 17'd99999);

    reg active;
    reg redge;
    reg abuf;
    assign rising_edge = redge;

    // clock counter    
    always @( posedge clk_50M ) begin
        if ( arstn == 1'b0 )
            clk_counter <= 17'b0;
        else if (active) begin
            if (clk_max) begin
                clk_counter <= 1'b0;
            end
            else
                clk_counter <= clk_counter + 17'b1;
        end 
    end
    
    // activate
    always @( posedge clk_50M ) begin
        if ( arstn == 1'b0 )
            active <= 1'b0;
        else if ( ~active & raw_sig )
            active <= 1'b1;
        else if ( active & clk_max )
            active <= 1'b0;
    end
    
    always @ ( posedge clk_50M ) begin
        if ( arstn == 1'b0 ) begin
            abuf <= 0;
        end else
            abuf <= active;
    end
    
    // rising edge
    always @( posedge clk_50M ) begin
        if ( arstn == 1'b0 ) begin
            redge <= 0;
            
        end else if ( active & ~abuf )
            redge <= 1;
        else
            redge <= 0;
    end
endmodule
