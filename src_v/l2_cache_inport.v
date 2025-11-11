//-----------------------------------------------------------------
// Copyright (c) 2021, admin@ultra-embedded.com
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions 
// are met:
//   - Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//   - Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer 
//     in the documentation and/or other materials provided with the 
//     distribution.
//   - Neither the name of the author nor the names of its contributors 
//     may be used to endorse or promote products derived from this 
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR 
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE 
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
// THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF 
// SUCH DAMAGE.
//-----------------------------------------------------------------
module l2_cache_inport #(
    // interface params (change numbers only)
    parameter ADDR_W      = 32,
    parameter DATA_W      = 32,
    parameter STRB_W      = DATA_W/8,
    parameter ID_W        = 4,
    parameter AWLEN_W     = 8,
    parameter AWBURST_W   = 2,
    parameter RSP_W       = 2,
    parameter RETIME_RESP = 0
)
(
    // Inputs
    input                     clk_i,
    input                     rst_i,
    input                     axi_awvalid_i,
    input  [ADDR_W-1:0]       axi_awaddr_i,
    input  [ID_W-1:0]         axi_awid_i,
    input  [AWLEN_W-1:0]      axi_awlen_i,
    input  [AWBURST_W-1:0]    axi_awburst_i,
    input                     axi_wvalid_i,
    input  [DATA_W-1:0]       axi_wdata_i,
    input  [STRB_W-1:0]       axi_wstrb_i,
    input                     axi_wlast_i,
    input                     axi_bready_i,
    input                     axi_arvalid_i,
    input  [ADDR_W-1:0]       axi_araddr_i,
    input  [ID_W-1:0]         axi_arid_i,
    input  [AWLEN_W-1:0]      axi_arlen_i,
    input  [AWBURST_W-1:0]    axi_arburst_i,
    input                     axi_rready_i,
    input                     outport_accept_i,
    input                     outport_ack_i,
    input                     outport_error_i,
    input  [DATA_W-1:0]       outport_read_data_i,

    // Outputs,
    output                    axi_awready_o,
    output                    axi_wready_o,
    output                    axi_bvalid_o,
    output [RSP_W-1:0]        axi_bresp_o,
    output [ID_W-1:0]         axi_bid_o,
    output                    axi_arready_o,
    output                    axi_rvalid_o,
    output [DATA_W-1:0]       axi_rdata_o,
    output [RSP_W-1:0]        axi_rresp_o,
    output [ID_W-1:0]         axi_rid_o,
    output                    axi_rlast_o,
    output [STRB_W-1:0]       outport_wr_o,
    output                    outport_rd_o,
    output [ADDR_W-1:0]       outport_addr_o,
    output [DATA_W-1:0]       outport_write_data_o
);

//----------------------------------------------------------------------
// internal widths derived
//----------------------------------------------------------------------
// request FIFO width: is_write(1) + last(1) + id(ID_W)
localparam REQ_W = 1 + 1 + ID_W;
localparam REQ_DEPTH = 4;
localparam REQ_ADDR_W = $clog2(REQ_DEPTH);

//-----------------------------------------------------------------
// Wires / regs (declare at top per SV rule)
//-----------------------------------------------------------------
logic               output_busy_w;

// Write channel wires
logic               wr_valid_w;
logic               wr_accept_w;
logic [ADDR_W-1:0]  wr_addr_w;
logic [ID_W-1:0]    wr_id_w;
logic [DATA_W-1:0]  wr_data_w;
logic [STRB_W-1:0]  wr_strb_w;
logic               wr_last_w;

// Read channel wires
logic               rd_valid_w;
logic               rd_accept_w;
logic [ADDR_W-1:0]  rd_addr_w;
logic [ID_W-1:0]    rd_id_w;
logic               rd_last_w;

// Request / response tracking
logic               req_fifo_accept_w;
logic               wr_enable_w;
logic               rd_enable_w;

logic [REQ_W-1:0]   req_in_r;
logic               req_out_valid_w;
logic [REQ_W-1:0]   req_out_w;
logic               resp_accept_w;

logic               resp_is_write_w;
logic               resp_is_read_w;
logic               resp_is_last_w;
logic [ID_W-1:0]    resp_id_w;

// Response buffering (retime path)
logic               resp_valid_w;

// Read skid / buffering (direct path)
logic               bvalid_q;
logic               rvalid_q;
logic               rbuf_valid_q;
logic [DATA_W-1:0]  rbuf_data_q;
logic               rbuf_last_q;

//-----------------------------------------------------------------
// AXI input parser module (parameterized)
//-----------------------------------------------------------------
l2_cache_axi_input
#(
    .DATA_W(DATA_W),
    .STRB_W(STRB_W),
    .ID_W(ID_W),
    .RW_ARB(1)
)
u_input
(
    .clk_i(clk_i),
    .rst_i(rst_i),

    // AXI
    .axi_awvalid_i(axi_awvalid_i),
    .axi_awaddr_i(axi_awaddr_i),
    .axi_awid_i(axi_awid_i),
    .axi_awlen_i(axi_awlen_i),
    .axi_awburst_i(axi_awburst_i),
    .axi_wvalid_i(axi_wvalid_i),
    .axi_wdata_i(axi_wdata_i),
    .axi_wstrb_i(axi_wstrb_i),
    .axi_wlast_i(axi_wlast_i),
    .axi_arvalid_i(axi_arvalid_i),
    .axi_araddr_i(axi_araddr_i),
    .axi_arid_i(axi_arid_i),
    .axi_arlen_i(axi_arlen_i),
    .axi_arburst_i(axi_arburst_i),
    .axi_awready_o(axi_awready_o),
    .axi_wready_o(axi_wready_o),
    .axi_arready_o(axi_arready_o),

    // Write
    .wr_valid_o(wr_valid_w),
    .wr_accept_i(wr_accept_w),
    .wr_addr_o(wr_addr_w),
    .wr_id_o(wr_id_w),
    .wr_data_o(wr_data_w),
    .wr_strb_o(wr_strb_w),
    .wr_last_o(wr_last_w),

    // Read
    .rd_valid_o(rd_valid_w),
    .rd_accept_i(rd_accept_w),
    .rd_addr_o(rd_addr_w),
    .rd_id_o(rd_id_w),
    .rd_last_o(rd_last_w)
);

//-----------------------------------------------------------------
// Request arbitration / shaping
//-----------------------------------------------------------------
always_comb begin
    wr_enable_w = wr_valid_w & req_fifo_accept_w & ~output_busy_w;
    rd_enable_w = rd_valid_w & req_fifo_accept_w & ~output_busy_w;
end

assign outport_addr_o       = wr_enable_w ? wr_addr_w : rd_addr_w;
assign outport_write_data_o = wr_data_w;
assign outport_rd_o         = rd_enable_w;
assign outport_wr_o         = wr_enable_w ? wr_strb_w : {STRB_W{1'b0}};

assign rd_accept_w          = rd_enable_w & outport_accept_i & req_fifo_accept_w & ~output_busy_w;
assign wr_accept_w          = wr_enable_w & outport_accept_i & req_fifo_accept_w & ~output_busy_w;

//-----------------------------------------------------------------
// Request tracking
//-----------------------------------------------------------------
always_comb begin
    // default
    req_in_r = {REQ_W{1'b0}};

    // Read
    if (outport_rd_o)
        req_in_r = {1'b1, rd_last_w, rd_id_w}; // {is_read, last, id}  (note original used first bit 1 for read)
    // Write
    else
        req_in_r = {1'b0, wr_last_w, wr_id_w}; // {is_read=0, last, id}
end

l2_cache_inport_fifo2
#( .WIDTH(REQ_W) )
u_requests
(
    .clk_i(clk_i),
    .rst_i(rst_i),

    // Input
    .data_in_i(req_in_r),
    .push_i((outport_rd_o || (outport_wr_o != {STRB_W{1'b0}})) && outport_accept_i),
    .accept_o(req_fifo_accept_w),

    // Output
    .pop_i(resp_accept_w),
    .data_out_o(req_out_w),
    .valid_o(req_out_valid_w)
);

// decode response fields
always_comb begin
    resp_is_write_w = req_out_valid_w ? ~req_out_w[REQ_W-1] : 1'b0; // top bit used for is_read in our packing
    resp_is_read_w  = req_out_valid_w ? req_out_w[REQ_W-1]  : 1'b0;
    resp_is_last_w  = req_out_w[REQ_W-2];
    resp_id_w       = req_out_w[REQ_W-3 -: ID_W];
end

//-----------------------------------------------------------------
// Retimed / direct response path
//-----------------------------------------------------------------
generate
if (RETIME_RESP) begin : gen_retime
    assign output_busy_w = 1'b0;

    //-------------------------------------------------------------
    // Response buffering (simple FIFO of DATA_W)
    //-------------------------------------------------------------
    l2_cache_inport_fifo2
    #( .WIDTH(DATA_W) )
    u_response
    (
        .clk_i(clk_i),
        .rst_i(rst_i),

        // Input
        .data_in_i(outport_read_data_i),
        .push_i(outport_ack_i),
        .accept_o(),

        // Output
        .pop_i(resp_accept_w),
        .data_out_o(axi_rdata_o),
        .valid_o(resp_valid_w)
    );

    //-------------------------------------------------------------
    // Response signals
    //-------------------------------------------------------------
    assign axi_bvalid_o  = resp_valid_w & resp_is_write_w & resp_is_last_w;
    assign axi_bresp_o   = {RSP_W{1'b0}};
    assign axi_bid_o     = resp_id_w;

    assign axi_rvalid_o  = resp_valid_w & resp_is_read_w;
    assign axi_rresp_o   = {RSP_W{1'b0}};
    assign axi_rid_o     = resp_id_w;
    assign axi_rlast_o   = resp_is_last_w;

    assign resp_accept_w = (axi_rvalid_o & axi_rready_i) |
                           (axi_bvalid_o & axi_bready_i) |
                           (resp_valid_w & resp_is_write_w & !resp_is_last_w);

end else begin : gen_direct
    // direct (zero-latency) response path - preserve original logic

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            bvalid_q <= 1'b0;
        else if (axi_bvalid_o && ~axi_bready_i)
            bvalid_q <= 1'b1;
        else if (axi_bready_i)
            bvalid_q <= 1'b0;
    end

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            rvalid_q <= 1'b0;
        else if (axi_rvalid_o && ~axi_rready_i)
            rvalid_q <= 1'b1;
        else if (axi_rready_i)
            rvalid_q <= 1'b0;
    end

    assign axi_bvalid_o = bvalid_q | (resp_is_write_w & resp_is_last_w & outport_ack_i);
    assign axi_bid_o    = resp_id_w;
    assign axi_bresp_o  = {RSP_W{1'b0}};

    assign axi_rvalid_o = rvalid_q | (resp_is_read_w & outport_ack_i);
    assign axi_rid_o    = resp_id_w;
    assign axi_rresp_o  = {RSP_W{1'b0}};

    assign output_busy_w = (axi_bvalid_o & ~axi_bready_i) | (axi_rvalid_o & ~axi_rready_i);

    //-------------------------------------------------------------
    // Read resp skid buffer
    //-------------------------------------------------------------
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            rbuf_valid_q <= 1'b0;
            rbuf_data_q  <= {DATA_W{1'b0}};
            rbuf_last_q  <= 1'b0;
        end
        else if (axi_rvalid_o && !axi_rready_i) begin
            rbuf_valid_q <= 1'b1;
            rbuf_data_q  <= axi_rdata_o;
            rbuf_last_q  <= axi_rlast_o;
        end
        else begin
            rbuf_valid_q <= 1'b0;
            rbuf_last_q  <= 1'b0;
        end
    end

    assign axi_rdata_o   = rbuf_valid_q ? rbuf_data_q : outport_read_data_i;
    assign axi_rlast_o   = resp_is_last_w;

    assign resp_accept_w = (axi_rvalid_o & axi_rready_i) |
                           (axi_bvalid_o & axi_bready_i) |
                           (outport_ack_i & resp_is_write_w & !resp_is_last_w);
end
endgenerate

endmodule


//-----------------------------------------------------------------
// FIFO (parameterized)
//-----------------------------------------------------------------
module l2_cache_inport_fifo2
#(
    parameter WIDTH   = 8,
    parameter DEPTH   = 4,
    parameter ADDR_W  = 2
)
(
    // Inputs
    input                       clk_i,
    input                       rst_i,
    input  [WIDTH-1:0]          data_in_i,
    input                       push_i,
    input                       pop_i,

    // Outputs
    output logic [WIDTH-1:0]    data_out_o,
    output logic                accept_o,
    output logic                valid_o
);

//-----------------------------------------------------------------
// Local Params
//-----------------------------------------------------------------
localparam COUNT_W = ADDR_W + 1;

//-----------------------------------------------------------------
// Storage / pointers (declared at top)
//-----------------------------------------------------------------
logic [WIDTH-1:0]         ram [DEPTH-1:0];
logic [ADDR_W-1:0]        rd_ptr;
logic [ADDR_W-1:0]        wr_ptr;
logic [COUNT_W-1:0]       count;

//-----------------------------------------------------------------
// Sequential
//-----------------------------------------------------------------
always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        count  <= {COUNT_W{1'b0}};
        rd_ptr <= {ADDR_W{1'b0}};
        wr_ptr <= {ADDR_W{1'b0}};
    end
    else begin
        // Push
        if (push_i & accept_o) begin
            ram[wr_ptr] <= data_in_i;
            wr_ptr      <= wr_ptr + 1;
        end

        // Pop
        if (pop_i & valid_o)
            rd_ptr <= rd_ptr + 1;

        // Count up
        if ((push_i & accept_o) & ~(pop_i & valid_o))
            count <= count + 1;
        // Count down
        else if (~(push_i & accept_o) & (pop_i & valid_o))
            count <= count - 1;
    end
end

//-------------------------------------------------------------------
// Combinatorial
//-------------------------------------------------------------------
always_comb begin
    accept_o = (count != DEPTH);
    valid_o  = (count != 0);
    data_out_o = ram[rd_ptr];
end

endmodule

