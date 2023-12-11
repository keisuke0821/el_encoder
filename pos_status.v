module pos_status(input wire clk, 
                  input wire arstn, 
                  input wire [2:0] rot_in, 
                  output reg [31:0] mon_out);

   
    reg  [2:0]  rot;
    wire [1:0]  move;
   
    // read buffer
    always @(posedge clk) begin
        rot[2:0] <= rot_in[2:0];
    end

    // movement
    encoder_read encoder_read_inst(
        .clk(clk), 
        .in(rot[1:0]), 
        .out(move)
    );

    always @(posedge clk) begin
        if(~arstn) begin
            mon_out[31:0] <= 32'd0;
        end
        else begin
            if(rot[2]) begin
                mon_out[31:0] <= 32'd0;
            end
            else if(move[0]) begin
                mon_out[31:0] <= mon_out[31:0] - 32'd1;
            end
            else if(move[1]) begin
                mon_out[31:0] <= mon_out[31:0] + 32'd1;
            end
        end
    end
endmodule
