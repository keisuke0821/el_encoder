module encoder_read(
    input wire clk,
    input wire [1:0] in,
    output reg [1:0] out);

   // register, wire
    reg [1:0] 	in_reg1;
    reg [1:0] 	in_reg2;
    wire [1:0] 	in_num1;
    wire [1:0] 	in_num2;

    assign in_num1[1:0] = {in_reg1[1], (in_reg1[1]^in_reg1[0])};
    assign in_num2[1:0] = {in_reg2[1], (in_reg2[1]^in_reg2[0])};

    always @(posedge clk) begin
        in_reg1[1:0] <= in[1:0];
        in_reg2[1:0] <= in_reg1[1:0];
    end

    always @(posedge clk) begin
        case (in_num1[1:0] - in_num2[1:0])
            2'd1: out[1:0] <= 2'b01;
            2'd3: out[1:0] <= 2'b10;
            default: out[1:0] <= 2'b00;
        endcase
    end
endmodule
