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
module l2_cache_outport
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter AXI_ID        = 0,
     parameter ADDR_W        = 32,
     parameter LINE_BYTES    = 32,                         // 32 bytes per cache line
     parameter LINE_DATA_W   = (LINE_BYTES*8),             // 256 bits
     parameter STRB_W        = (LINE_DATA_W/8),            // 32
     parameter AWLEN_W       = 8,
     parameter AWBURST_W     = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
    input                          clk_i,
    input                          rst_i,

    output logic                   inport_accept_o,
    output logic                   inport_ack_o,
    output logic                   inport_error_o,
    output logic [LINE_DATA_W-1:0] inport_read_data_o,
    input                          inport_wr_i,
    input                          inport_rd_i,
    input  [ADDR_W-1:0]            inport_addr_i,
    input  [LINE_DATA_W-1:0]       inport_write_data_i,

    input                          outport_awready_i,
    input                          outport_wready_i,
    input                          outport_bvalid_i,
    input  [ 1:0]                  outport_bresp_i,
    input  [ 3:0]                  outport_bid_i,
    input                          outport_arready_i,
    input                          outport_rvalid_i,
    input  [LINE_DATA_W-1:0]       outport_rdata_i,
    input  [ 1:0]                  outport_rresp_i,
    input  [ 3:0]                  outport_rid_i,
    input                          outport_rlast_i,

    // Outputs,
    output logic                   outport_awvalid_o,
    output logic [ADDR_W-1:0]      outport_awaddr_o,
    output logic [ 3:0]            outport_awid_o,
    output logic [AWLEN_W-1:0]     outport_awlen_o,
    output logic [AWBURST_W-1:0]   outport_awburst_o,
    output logic                   outport_wvalid_o,
    output logic [LINE_DATA_W-1:0] outport_wdata_o,
    output logic [STRB_W-1:0]      outport_wstrb_o,
    output logic                   outport_wlast_o,
    output logic                   outport_bready_o,
    output logic                   outport_arvalid_o,
    output logic [ADDR_W-1:0]      outport_araddr_o,
    output logic [ 3:0]            outport_arid_o,
    output logic [AWLEN_W-1:0]     outport_arlen_o,
    output logic [AWBURST_W-1:0]   outport_arburst_o,
    output logic                   outport_rready_o
);

//-----------------------------------------------------------------
// Request FIFO
//-----------------------------------------------------------------
localparam REQ_WIDTH = 1 + LINE_DATA_W + ADDR_W; // [ rd_flag (1), data, addr ]
wire         req_valid_w;
wire [ADDR_W-1:0]  request_addr_w;
wire [LINE_DATA_W-1:0] request_data_w;
wire         request_rd_w;
wire         req_accept_w;

l2_cache_outport_fifo2
#(
    .WIDTH(REQ_WIDTH),
    .DEPTH(2),
    .ADDR_W(1)
)
u_req
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    
    .push_i(inport_wr_i | inport_rd_i),
    .data_in_i({inport_rd_i, inport_write_data_i, inport_addr_i}),
    .accept_o(inport_accept_o),

    .valid_o(req_valid_w),
    .data_out_o({request_rd_w, request_data_w, request_addr_w}),
    .pop_i(req_accept_w)
);

//-----------------------------------------------------------------
// Write Request Output
//-----------------------------------------------------------------
logic        awvalid_q;
logic        wvalid_q;

logic wr_cmd_accepted_w;
logic wr_data_accepted_w;

assign wr_cmd_accepted_w  = (outport_awvalid_o && outport_awready_i) || awvalid_q;
assign wr_data_accepted_w = (outport_wvalid_o  && outport_wready_i)  || wvalid_q;

logic        write_pending_q;
logic [ADDR_W-1:0] write_addr_q;

// latch write addr when request accepted (write)
always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
        write_addr_q <= {ADDR_W{1'b0}};
    else if (req_valid_w && !request_rd_w && req_accept_w)
        write_addr_q <= request_addr_w;
end

// pending flag
always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
        write_pending_q <= 1'b0;
    else if (req_valid_w && !request_rd_w && req_accept_w)
        write_pending_q <= 1'b1;
    else if (outport_bvalid_i && outport_bready_o)
        write_pending_q <= 1'b0;
end

// awvalid skid
always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
        awvalid_q <= 1'b0;
    else if (outport_awvalid_o && outport_awready_i && !wr_data_accepted_w)
        awvalid_q <= 1'b1;
    else if (wr_data_accepted_w)
        awvalid_q <= 1'b0;
end

// wvalid skid
always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
        wvalid_q <= 1'b0;
    else if (outport_wvalid_o && outport_wready_i && !wr_cmd_accepted_w)
        wvalid_q <= 1'b1;
    else if (wr_cmd_accepted_w)
        wvalid_q <= 1'b0;
end

assign outport_awvalid_o = req_valid_w & ~awvalid_q & ~request_rd_w & ~write_pending_q;
assign outport_awaddr_o  = request_addr_w;
assign outport_awid_o    = AXI_ID;
assign outport_awlen_o   = {AWLEN_W{1'b0}};  // 32-bytes (single beat)
assign outport_awburst_o = 2'b01; // INCR
assign outport_wvalid_o  = req_valid_w & ~wvalid_q & ~request_rd_w & ~write_pending_q;
assign outport_wdata_o   = request_data_w;
assign outport_wstrb_o   = {STRB_W{1'b1}};
assign outport_wlast_o   = 1'b1;  // single-beat (32-bytes)

//-----------------------------------------------------------------
// Read Request Output
//-----------------------------------------------------------------
// Stop reads from reading uncommitted write data (writes maybe overtaken in the fabric)
logic read_block_w;
assign read_block_w = write_pending_q && (write_addr_q == request_addr_w);

assign outport_arvalid_o = req_valid_w & request_rd_w & ~read_block_w;
assign outport_araddr_o  = request_addr_w;
assign outport_arid_o    = AXI_ID;
assign outport_arlen_o   = {AWLEN_W{1'b0}};  // Max single-beat
assign outport_arburst_o = 2'b01; // INCR

//-----------------------------------------------------------------
// Request Pop
//-----------------------------------------------------------------
assign req_accept_w      = request_rd_w ? (outport_arready_i & ~read_block_w) :
                           (((outport_awready_i | awvalid_q) & (outport_wready_i | wvalid_q)) & ~write_pending_q);

//--------------------------------------------------------------------
// Response
//--------------------------------------------------------------------
// assign outport_rready_o   = 1'b1;
// assign outport_bready_o   = 1'b1;

// Posted writes
logic early_wr_ack_q;

always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
        early_wr_ack_q <= 1'b0;
    else
        early_wr_ack_q <= inport_wr_i & inport_accept_o;
end

assign inport_ack_o       = outport_rvalid_i | early_wr_ack_q;
assign inport_error_o     = outport_rvalid_i ? (|outport_rresp_i) : 1'b0;
assign inport_read_data_o = outport_rdata_i;

//-----------------------------------------------------------------
// Simple tie-offs (bready/rready already assigned)
//-----------------------------------------------------------------
assign outport_bready_o = 1'b1;
assign outport_rready_o = 1'b1;

endmodule


//-----------------------------------------------------------------
// FIFO (parameterized)
//-----------------------------------------------------------------
module l2_cache_outport_fifo2
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 8,
    parameter DEPTH   = 4,
    parameter ADDR_W  = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
    input                     clk_i,
    input                     rst_i,
    input  [WIDTH-1:0]        data_in_i,
    input                     push_i,
    input                     pop_i,

    // Outputs,
    output logic [WIDTH-1:0]  data_out_o,
    output logic              accept_o,
    output logic              valid_o
);

//-----------------------------------------------------------------
// Local Params
//-----------------------------------------------------------------
localparam COUNT_W = ADDR_W + 1;

//-----------------------------------------------------------------
// Registers
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
        count   <= {COUNT_W{1'b0}};
        rd_ptr  <= {ADDR_W{1'b0}};
        wr_ptr  <= {ADDR_W{1'b0}};
    end
    else begin
        // Push
        if (push_i & accept_o) begin
            ram[wr_ptr] <= data_in_i;
            wr_ptr      <= wr_ptr + 1;
        end

        // Pop
        if (pop_i & valid_o)
            rd_ptr      <= rd_ptr + 1;

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
    accept_o   = (count != DEPTH);
    valid_o    = (count != 0);
    data_out_o = ram[rd_ptr];
end

endmodule


