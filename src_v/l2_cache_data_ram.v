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
module l2_cache_data_ram #(
    parameter ADDR_W = 11,               // address width (default 11 -> 2048 entries)
    parameter DATA_W = 32                // data width (default 32)
)
(
    // Inputs
    input                       clk0_i,
    input                       rst0_i,
    input  [ADDR_W-1:0]         addr0_i,
    input  [DATA_W-1:0]         data0_i,
    input  [(DATA_W/8)-1:0]     wr0_i,
    input                       clk1_i,
    input                       rst1_i,
    input  [ADDR_W-1:0]         addr1_i,
    input  [DATA_W-1:0]         data1_i,
    input  [(DATA_W/8)-1:0]     wr1_i,

    // Outputs,
    output [DATA_W-1:0]         data0_o,
    output [DATA_W-1:0]         data1_o
);

localparam DEPTH = (1 << ADDR_W);
localparam STRB_W = (DATA_W/8);

//-----------------------------------------------------------------
// Dual Port RAM
// Mode: Read First
//-----------------------------------------------------------------
/* verilator lint_off MULTIDRIVEN */
reg [DATA_W-1:0] ram [0:DEPTH-1] /*verilator public*/;
/* verilator lint_on MULTIDRIVEN */

reg [DATA_W-1:0] ram_read0_q;
reg [DATA_W-1:0] ram_read1_q;

// integer for loop index - declared at module scope (SV rule)
int i;

// Synchronous write + read-first semantics on port0
always @ (posedge clk0_i)
begin
    // Note: keep behavior identical to original: write bytes (if strobe) then read
    for (i = 0; i < STRB_W; i = i + 1) begin
        if (wr0_i[i])
            ram[addr0_i][i*8 +: 8] <= data0_i[i*8 +: 8];
    end

    ram_read0_q <= ram[addr0_i];
end

// Synchronous write + read-first semantics on port1
always @ (posedge clk1_i)
begin
    for (i = 0; i < STRB_W; i = i + 1) begin
        if (wr1_i[i])
            ram[addr1_i][i*8 +: 8] <= data1_i[i*8 +: 8];
    end

    ram_read1_q <= ram[addr1_i];
end

assign data0_o = ram_read0_q;
assign data1_o = ram_read1_q;

endmodule
