`timescale 1 ns / 1 ps

module axi_gb_rotary #(
    parameter ID = 0 )(
        // Rotary encoder interfaces
        input wire              rot_a,  //A相のinput
        input wire              rot_b,  //B相のinput
        input wire              rot_z,  //Z相のinput

        // Synchronization
        input wire              ex_sync, //同期信号

        // 1kSPS streaming AXIS interface
        output wire [31:0]      m_axis_tdata,
        output reg              m_axis_tlast,
        input wire              m_axis_tready,
        output reg              m_axis_tvalid,

        input wire              dev_clk, // Should be 50 MHz
        output wire             interrupt,

        // Ports of Axi Slave Bus Interface S00_AXI
        input wire              s_axi_aclk,
        input wire              s_axi_aresetn,

        input wire [3 : 0]      s_axi_awaddr,
        input wire [2 : 0]      s_axi_awprot,
        input wire              s_axi_awvalid,
        output wire             s_axi_awready,

        input wire [31 : 0]     s_axi_wdata,
        input wire [3 : 0]      s_axi_wstrb,
        input wire              s_axi_wvalid,
        output wire             s_axi_wready,

        output wire [1 : 0]     s_axi_bresp,
        output wire             s_axi_bvalid,
        input wire              s_axi_bready,
        input wire  [3 : 0]     s_axi_araddr,
        input wire  [2 : 0]     s_axi_arprot,
        input wire              s_axi_arvalid,
        output wire             s_axi_arready,
        output wire [31 : 0]    s_axi_rdata,
        output wire [1 : 0]     s_axi_rresp,
        output wire             s_axi_rvalid,
        input wire              s_axi_rready
    );

    wire sync_trg;
    wire z_en;
    wire [31:0] rot_pos;
    reg [15:0] clk_counter; // increment @ 50MHz
    reg [31:0] time_stamp; // increment @ 1kHz


    // Instantiation of Axi Bus Interface S00_AXI
    axi_gb_rotary_S00_AXI axi_gb_rotary_S00_AXI_inst (
        .sync_trg(sync_trg),
        .rot_pos(rot_pos),
        .time_stamp(time_stamp),
        .clk_counter(clk_counter),
        .interrupt(interrupt),
        .z_en(z_en),

        .S_AXI_ACLK(s_axi_aclk),
        .S_AXI_ARESETN(s_axi_aresetn),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWPROT(s_axi_awprot),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),
        .S_AXI_BVALID(s_axi_bvalid),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_ARADDR(s_axi_araddr),
        .S_AXI_ARPROT(s_axi_arprot),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA(s_axi_rdata),
        .S_AXI_RRESP(s_axi_rresp),
        .S_AXI_RVALID(s_axi_rvalid),
        .S_AXI_RREADY(s_axi_rready)
    );

    // Add user logic here

    pos_status pos_st(
        .clk(dev_clk),
        .arstn(s_axi_aresetn),
        .rot_in({rot_z & z_en, rot_a, rot_b}),
        .mon_out(rot_pos)
    );

    // chattering clearing
    rising_edge_ms rems(
        .raw_sig(ex_sync),
        .clk_50M(dev_clk),
        .arstn(s_axi_aresetn),
        .rising_edge(sync_trg)
    );

    ////////////////////////////////////////////////////////// AXI-4 Stream
    wire clk_max = (clk_counter == 16'd49999);
    reg [31:0] data_buf;
    reg [1:0] step;
    assign m_axis_tdata = data_buf;

    // 1kHz source
    always @( posedge dev_clk )
    begin
        if ( s_axi_aresetn == 1'b0 ) begin
            clk_counter <= 16'b0;
            time_stamp <= 32'b0;
        end
        else if ( clk_max ) begin
            clk_counter <= 16'b0;
            time_stamp <= time_stamp + 32'b1;
        end
        else
            clk_counter <= clk_counter + 1'b1;
    end

    // Stream
    always @ ( posedge dev_clk ) begin
        if ( s_axi_aresetn == 1'b0 )
            step <= 2'b00;

        case(step)
            2'b00: begin
                if( clk_max ) begin
                    step <= 2'b01;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= 1'b0;
                    data_buf <= time_stamp;
                end
                else
                    step <= step;
            end
            2'b01: begin
                step <= 2'b10;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= 1'b1;
                data_buf <= rot_pos;
            end
            2'b10: begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                data_buf <= 32'h0;
                step <= 2'b00;
            end
        endcase
    end

endmodule
