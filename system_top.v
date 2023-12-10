`timescale 1 ps / 1 ps

module system_top(
    inout [14:0]DDR_addr,
    inout [2:0]DDR_ba,
    inout DDR_cas_n,
    inout DDR_ck_n,
    inout DDR_ck_p,
    inout DDR_cke,
    inout DDR_cs_n,
    inout [3:0]DDR_dm,
    inout [31:0]DDR_dq,
    inout [3:0]DDR_dqs_n,
    inout [3:0]DDR_dqs_p,
    inout DDR_odt,
    inout DDR_ras_n,
    inout DDR_reset_n,
    inout DDR_we_n,
    inout FIXED_IO_ddr_vrn,
    inout FIXED_IO_ddr_vrp,
    inout [53:0]FIXED_IO_mio,
    inout FIXED_IO_ps_clk,
    inout FIXED_IO_ps_porb,
    inout FIXED_IO_ps_srstb,
    
    input rot_a,
    input rot_b,
    input rot_z,
    input ex_sync, 
    output fanout_0,
    output fanout_1,
    output [7:0] fanout_jb);

    assign fanout_0 = ex_sync;
    assign fanout_1 = ex_sync;
    
    assign fanout_jb = {8{ex_sync}};

    wire sync_out;
    wire uart;
    wire f_clk;
    wire f_rstn;

    reg [7:0] chat_cnt;

    sync_splitter i_sync_splitter
        (.sync_in(ex_sync),
         .clk(f_clk),
         .rstn(f_rstn),
         .sync_out(sync_out),
         .uart(uart));

    localparam CHAT_NUM = 20;

    wire z_red = (chat_cnt >= CHAT_NUM);

    // chattering reduction for the z-pulse
    always @(posedge f_clk) begin
        if (~f_rstn) begin
            chat_cnt <= 8'b0;
        end
        else begin
            if (rot_z & (chat_cnt < CHAT_NUM))
                chat_cnt <= chat_cnt + 1;
            else if (~rot_z)
                chat_cnt <= 8'b0;
            else
                chat_cnt <= chat_cnt;
        end
    end

    system_wrapper i_system_wrapper
        (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

        .f_clk(f_clk),
        .f_rstn(f_rstn),
        
        .rot_a(rot_a),
        .rot_b(rot_b),
        .rot_z(z_red),
        .ex_sync(sync_out),
        .uart(uart));

endmodule