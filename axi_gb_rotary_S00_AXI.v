`timescale 1 ns / 1 ps

module axi_gb_rotary_S00_AXI
    (
        input wire sync_trg,
        input wire [31:0] rot_pos,
        input wire [31:0] time_stamp,
        input wire [15:0] clk_counter,
        output wire interrupt,
        output wire z_en,

        input wire  S_AXI_ACLK,
        input wire  S_AXI_ARESETN,
        input wire [3 : 0] S_AXI_AWADDR,
        input wire [2 : 0] S_AXI_AWPROT,
        input wire  S_AXI_AWVALID,
        output wire  S_AXI_AWREADY,
        input wire [31 : 0] S_AXI_WDATA,
        input wire [3 : 0] S_AXI_WSTRB,
        input wire  S_AXI_WVALID,
        output wire  S_AXI_WREADY,
        output wire [1 : 0] S_AXI_BRESP,
        output wire  S_AXI_BVALID,
        input wire  S_AXI_BREADY,
        input wire [3 : 0] S_AXI_ARADDR,
        input wire [2 : 0] S_AXI_ARPROT,
        input wire  S_AXI_ARVALID,
        output wire  S_AXI_ARREADY,
        output wire [31 : 0] S_AXI_RDATA,
        output wire [1 : 0] S_AXI_RRESP,
        output wire  S_AXI_RVALID,
        input wire  S_AXI_RREADY
    );

    // AXI4LITE signals
    reg [3 : 0]     axi_awaddr;
    reg             axi_awready;
    reg             axi_wready;
    reg [1 : 0]     axi_bresp;
    reg             axi_bvalid;
    reg [3 : 0]     axi_araddr;
    reg             axi_arready;
    reg [31 : 0]    axi_rdata;
    reg [1 : 0]     axi_rresp;
    reg             axi_rvalid;

    localparam integer ADDR_LSB = 2;
    localparam integer OPT_MEM_ADDR_BITS = 1;

    reg [31:0]  slv_reg0;
    reg [31:0]  slv_reg1;
    reg [31:0]  slv_reg2;
    reg [31:0]  slv_reg3;
    wire        slv_reg_rden;
    wire        slv_reg_wren;
    reg [31:0]  reg_data_out;
    integer     byte_index;
    reg         aw_en;
    
    reg sync_detected;
    reg intr_reset;
    reg z_en_reg;
    
    assign interrupt = sync_detected;

    // I/O Connections assignments

    assign S_AXI_AWREADY	= axi_awready;
    assign S_AXI_WREADY	= axi_wready;
    assign S_AXI_BRESP	= axi_bresp;
    assign S_AXI_BVALID	= axi_bvalid;
    assign S_AXI_ARREADY	= axi_arready;
    assign S_AXI_RDATA	= axi_rdata;
    assign S_AXI_RRESP	= axi_rresp;
    assign S_AXI_RVALID	= axi_rvalid;

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_awaddr <= 0;
        end else begin    
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awaddr <= S_AXI_AWADDR;
            end
        end 
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_wready <= 1'b0;
        end else begin    
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en ) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end 
    end       

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            slv_reg1 <= 0;
            intr_reset <= 1'b0;
            z_en_reg <= 1'b1;
        end else begin
            if (slv_reg_wren) begin
                case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
                2'h1:
                    if ( S_AXI_WSTRB[0] == 1) begin // 7 to 0
                        // 0: interrupt status. Put 0 to reset
                        if ( S_AXI_WDATA[0] == 1'b0 )
                            intr_reset <= 1'b1;
                        else
                            intr_reset <= 1'b0;
                        z_en_reg <= S_AXI_WDATA[1];
                    end
                default : begin
                    ;
                end
                endcase
            end else begin
                intr_reset <= 1'b0;
                z_en_reg <= z_en_reg;
            end
        end
    end

    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
        begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end
        else
        begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
            begin
                // indicates a valid write response is available
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0; // 'OKAY' response 
            end                   // work error responses in future
            else
            begin
                if (S_AXI_BREADY && axi_bvalid)
                begin
                    axi_bvalid <= 1'b0; 
                end
            end
        end
    end   

    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_rvalid <= 0;
            axi_rresp  <= 0;
        end else begin    
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0; // 'OKAY' response
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
    always @(*)
    begin
        // Address decoding for reading registers
        case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
        2'h0   : reg_data_out <= slv_reg0;
        2'h1   : reg_data_out <= {30'b0, z_en_reg, sync_detected};
        2'h2   : reg_data_out <= slv_reg2;
        2'h3   : reg_data_out <= slv_reg3;
        default : reg_data_out <= 0;
        endcase
    end

    // Output register or memory read data
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
        begin
            axi_rdata  <= 0;
        end 
        else
        begin    
            if (slv_reg_rden)
            begin
                axi_rdata <= reg_data_out;     // register read data
            end   
        end
    end    
    
    always @( posedge S_AXI_ACLK )
    begin
        slv_reg0 <= rot_pos;
    end

    always @( posedge S_AXI_ACLK ) begin
        if ( sync_trg ) begin
            sync_detected <= 1'b1;
            slv_reg2 <= time_stamp;
            slv_reg3 <= clk_counter;
            
        end 
        else if ( intr_reset )
            sync_detected <= 1'b0;
    end

    assign z_en = z_en_reg;

endmodule
