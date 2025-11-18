module l2_cache_core
#(
    // Core / interface widths (can change numbers only)
    parameter ADDR_W                 = 32,            // width of addresses (cpu side)
    parameter CORE_DATA_W            = 32,            // cpu-side data width (inport_data_wr_i)
    parameter CORE_STRB_W            = (CORE_DATA_W/8), // inport_wr width (bytes per core word)

    // Cache geometry
    parameter L2_CACHE_LINE_SIZE     = 32,            // bytes per cache line
    parameter L2_CACHE_LINE_SIZE_W   = $clog2(L2_CACHE_LINE_SIZE),
    parameter L2_CACHE_LINE_ADDR_W   = 11,            // number of line address bits (number of lines = 2^this)
    parameter L2_CACHE_NUM_LINES     = 2048,
    parameter L2_CACHE_NUM_WAYS      = 2,             // number of ways

    // Tag fields
    parameter L2_CACHE_TAG_ADDR_BITS = 16             // tag address bits stored
)
(
    // Inputs
    input                             clk_i,
    input                             rst_i,
    input                             flush_i,
    input  [ADDR_W-1:0]               inport_addr_i,
    input  [CORE_DATA_W-1:0]          inport_data_wr_i,
    input                             inport_rd_i,
    input  [CORE_STRB_W-1:0]          inport_wr_i,
    input                             outport_accept_i,
    input                             outport_ack_i,
    input                             outport_error_i,
    input  [(L2_CACHE_LINE_SIZE*8)-1:0] outport_read_data_i,

    // Outputs
    output [CORE_DATA_W-1:0]          inport_data_rd_o,
    output                            inport_accept_o,
    output                            inport_ack_o,
    output                            inport_error_o,
    output                            outport_wr_o,
    output                            outport_rd_o,
    output [ADDR_W-1:0]               outport_addr_o,
    output [(L2_CACHE_LINE_SIZE*8)-1:0] outport_write_data_o
);

//-----------------------------------------------------------------
// Derived params / localparams (do not change logic, only computed)
//-----------------------------------------------------------------
localparam L2_CACHE_TAG_REQ_LINE_L = L2_CACHE_LINE_SIZE_W;
localparam L2_CACHE_TAG_REQ_LINE_H = L2_CACHE_LINE_ADDR_W + L2_CACHE_LINE_SIZE_W - 1;
localparam L2_CACHE_TAG_REQ_LINE_W = L2_CACHE_LINE_ADDR_W;
`define L2_CACHE_TAG_REQ_RNG L2_CACHE_TAG_REQ_LINE_H:L2_CACHE_TAG_REQ_LINE_L

`define L2_CACHE_TAG_ADDR_RNG (L2_CACHE_TAG_ADDR_BITS-1):0
localparam L2_CACHE_TAG_DIRTY_BIT = L2_CACHE_TAG_ADDR_BITS + 0;
localparam L2_CACHE_TAG_VALID_BIT = L2_CACHE_TAG_ADDR_BITS + 1;
localparam L2_CACHE_TAG_DATA_W   = L2_CACHE_TAG_ADDR_BITS + 2;

// Tag compare bits
localparam L2_CACHE_TAG_CMP_ADDR_L = L2_CACHE_TAG_REQ_LINE_H + 1;
localparam L2_CACHE_TAG_CMP_ADDR_H = ADDR_W - 1;
localparam L2_CACHE_TAG_CMP_ADDR_W = L2_CACHE_TAG_CMP_ADDR_H - L2_CACHE_TAG_CMP_ADDR_L + 1;
`define L2_CACHE_TAG_CMP_ADDR_RNG L2_CACHE_TAG_CMP_ADDR_H:L2_CACHE_TAG_CMP_ADDR_L

// Other derived
localparam STATE_W = 4;
localparam EVICT_ADDR_W = ADDR_W - L2_CACHE_LINE_SIZE_W;

// Byte offset bits (number of low address bits used inside a core data word)
localparam BYTE_OFFSET_BITS = $clog2(CORE_STRB_W); // e.g. CORE_STRB_W=4 -> 2 bits

// Number of words in a cache line (cache-line / core-word)
localparam CACHE_LINE_WORDS = (L2_CACHE_LINE_SIZE / (CORE_DATA_W/8));
localparam WORD_OFFSET_BITS = $clog2(CACHE_LINE_WORDS);
// address width used by data RAM indexing
localparam CACHE_DATA_ADDR_W = L2_CACHE_LINE_ADDR_W + L2_CACHE_LINE_SIZE_W - BYTE_OFFSET_BITS;

// data ram write-mask width (each word has CORE_STRB_W strobes)
localparam DATA_WR_MASK_W = CACHE_LINE_WORDS * CORE_STRB_W;

//-----------------------------------------------------------------
// States
//-----------------------------------------------------------------
enum logic [3:0] {
    STATE_RESET,
    STATE_FLUSH_ADDR,
    STATE_FLUSH,
    STATE_LOOKUP,
    STATE_READ,
    STATE_WRITE,
    STATE_REFILL,
    STATE_EVICT,
    STATE_EVICT_WAIT
} state_q, next_state_r;

//-----------------------------------------------------------------
// Request buffer
//-----------------------------------------------------------------
reg [ADDR_W-1:0]      inport_addr_m_q;
reg [CORE_DATA_W-1:0] inport_data_m_q;
reg [CORE_STRB_W-1:0] inport_wr_m_q;
reg                   inport_rd_m_q;


wire tag_hit_any_m_w;
wire [(L2_CACHE_LINE_SIZE*8)-1:0] data1_data_out_m_w;
wire [(L2_CACHE_LINE_SIZE*8)-1:0] data1_data_in_m_w;
wire [(L2_CACHE_LINE_SIZE*8)-1:0] data0_data_out_m_w;
wire [(L2_CACHE_LINE_SIZE*8)-1:0] data0_data_in_m_w;
wire                           tag1_hit_m_w;
wire                           tag0_hit_m_w;
reg [L2_CACHE_TAG_REQ_LINE_W-1:0] flush_addr_q;

always @ (posedge clk_i )
if (rst_i)
begin
    inport_addr_m_q      <= {ADDR_W{1'b0}};
    inport_data_m_q      <= {CORE_DATA_W{1'b0}};
    inport_wr_m_q        <= {CORE_STRB_W{1'b0}};
    inport_rd_m_q        <= 1'b0;
end
else if (inport_accept_o)
begin
    inport_addr_m_q      <= inport_addr_i;
    inport_data_m_q      <= inport_data_wr_i;
    inport_wr_m_q        <= inport_wr_i;
    inport_rd_m_q        <= inport_rd_i;
end
else if (inport_ack_o)
begin
    inport_addr_m_q      <= {ADDR_W{1'b0}};
    inport_data_m_q      <= {CORE_DATA_W{1'b0}};
    inport_wr_m_q        <= {CORE_STRB_W{1'b0}};
    inport_rd_m_q        <= 1'b0;
end

reg inport_accept_r;

always @ *
begin
    inport_accept_r = 1'b0;

    if (state_q == STATE_LOOKUP)
    begin
        // Previous access missed - do not accept new requests
        if ((inport_rd_m_q || (inport_wr_m_q != '0)) && !tag_hit_any_m_w)
            inport_accept_r = 1'b0;
        // Write followed by read - detect writes to the same line, or addresses which alias in tag lookups
        else if ((|inport_wr_m_q) && inport_rd_i && inport_addr_i[ADDR_W-1:BYTE_OFFSET_BITS] == inport_addr_m_q[ADDR_W-1:BYTE_OFFSET_BITS])
            inport_accept_r = 1'b0;
        else
            inport_accept_r = 1'b1;
    end
end

assign inport_accept_o = inport_accept_r;

// Tag comparison address
wire [L2_CACHE_TAG_CMP_ADDR_W-1:0] req_addr_tag_cmp_m_w = inport_addr_m_q[`L2_CACHE_TAG_CMP_ADDR_RNG];

//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------
localparam REPLACE_W = (L2_CACHE_NUM_WAYS > 1) ? $clog2(L2_CACHE_NUM_WAYS) : 1;
reg [REPLACE_W-1:0] replace_way_q;

wire           pmem_wr_w;
wire           pmem_rd_w;
wire  [  7:0]  pmem_len_w;
wire  [ADDR_W-1:0]  pmem_addr_w;
wire  [(L2_CACHE_LINE_SIZE*8)-1:0]  pmem_write_data_w;
wire           pmem_accept_w;
wire           pmem_ack_w;
wire           pmem_error_w;
wire  [(L2_CACHE_LINE_SIZE*8)-1:0]  pmem_read_data_w;

wire           evict_way_w;
wire           tag_dirty_any_m_w;
wire           tag_hit_and_dirty_m_w;

reg            flushing_q;

//-----------------------------------------------------------------
// TAG RAMS
//-----------------------------------------------------------------
reg [L2_CACHE_TAG_REQ_LINE_W-1:0] tag_addr_x_r;
reg [L2_CACHE_TAG_REQ_LINE_W-1:0] tag_addr_m_r;

// Tag RAM address
always @ *
begin
    // Read Port
    tag_addr_x_r = inport_addr_i[`L2_CACHE_TAG_REQ_RNG];

    // Lookup
    if (state_q == STATE_LOOKUP && next_state_r == STATE_LOOKUP)
        tag_addr_x_r = inport_addr_i[`L2_CACHE_TAG_REQ_RNG];
    // Cache flush
    else if (flushing_q)
        tag_addr_x_r = flush_addr_q;
    else
        tag_addr_x_r = inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG];

    // Write Port
    tag_addr_m_r = flush_addr_q;

    // Cache flush
    if (flushing_q || state_q == STATE_RESET)
        tag_addr_m_r = flush_addr_q;
    // Line refill / write
    else
        tag_addr_m_r = inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG];
end

// Tag RAM write data
reg [L2_CACHE_TAG_DATA_W-1:0] tag_data_in_m_r;
always @ *
begin
    tag_data_in_m_r = {(L2_CACHE_TAG_DATA_W){1'b0}};

    // Cache flush
    if (state_q == STATE_FLUSH || state_q == STATE_RESET || flushing_q)
        tag_data_in_m_r = {(L2_CACHE_TAG_DATA_W){1'b0}};
    // Line refill
    else if (state_q == STATE_REFILL)
    begin
        tag_data_in_m_r[L2_CACHE_TAG_VALID_BIT] = 1'b1;
        tag_data_in_m_r[L2_CACHE_TAG_DIRTY_BIT] = 1'b0;
        tag_data_in_m_r[`L2_CACHE_TAG_ADDR_RNG] = inport_addr_m_q[`L2_CACHE_TAG_CMP_ADDR_RNG];
    end
    // Evict completion
    else if (state_q == STATE_EVICT_WAIT)
    begin
        tag_data_in_m_r[L2_CACHE_TAG_VALID_BIT] = 1'b1;
        tag_data_in_m_r[L2_CACHE_TAG_DIRTY_BIT] = 1'b0;
        tag_data_in_m_r[`L2_CACHE_TAG_ADDR_RNG] = inport_addr_m_q[`L2_CACHE_TAG_CMP_ADDR_RNG];
    end
    // Write - mark entry as dirty
    else if (state_q == STATE_WRITE || (state_q == STATE_LOOKUP && (|inport_wr_m_q)))
    begin
        tag_data_in_m_r[L2_CACHE_TAG_VALID_BIT] = 1'b1;
        tag_data_in_m_r[L2_CACHE_TAG_DIRTY_BIT] = 1'b1;
        tag_data_in_m_r[`L2_CACHE_TAG_ADDR_RNG] = inport_addr_m_q[`L2_CACHE_TAG_CMP_ADDR_RNG];
    end
end

// Tag RAM write enable (way 0)
reg tag0_write_m_r;
always @ *
begin
    tag0_write_m_r = 1'b0;

    // Cache flush (reset)
    if (state_q == STATE_RESET)
        tag0_write_m_r = 1'b1;
    // Cache flush
    else if (state_q == STATE_FLUSH)
        tag0_write_m_r = !tag_dirty_any_m_w;
    // Write - hit, mark as dirty
    else if (state_q == STATE_LOOKUP && (|inport_wr_m_q))
        tag0_write_m_r = tag0_hit_m_w;
    // Write - write after refill
    else if (state_q == STATE_WRITE)
        tag0_write_m_r = (replace_way_q == 0);
    // Write - mark entry as dirty
    else if (state_q == STATE_EVICT_WAIT && pmem_ack_w)
        tag0_write_m_r = (replace_way_q == 0);
    // Line refill
    else if (state_q == STATE_REFILL)
        tag0_write_m_r = pmem_ack_w && (replace_way_q == 0);
end

wire [L2_CACHE_TAG_DATA_W-1:0] tag0_data_out_m_w;

l2_cache_tag_ram
u_tag0
(
  .clk0_i(clk_i),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),

  // Read
  .addr0_i(tag_addr_x_r),
  .data0_o(tag0_data_out_m_w),

  // Write
  .addr1_i(tag_addr_m_r),
  .data1_i(tag_data_in_m_r),
  .wr1_i(tag0_write_m_r)
);

wire                              tag0_valid_m_w     = tag0_data_out_m_w[L2_CACHE_TAG_VALID_BIT];
wire                              tag0_dirty_m_w     = tag0_data_out_m_w[L2_CACHE_TAG_DIRTY_BIT];
wire [L2_CACHE_TAG_ADDR_BITS-1:0] tag0_addr_bits_m_w = tag0_data_out_m_w[`L2_CACHE_TAG_ADDR_RNG];

// Tag hit?
assign                           tag0_hit_m_w = tag0_valid_m_w ? (tag0_addr_bits_m_w == req_addr_tag_cmp_m_w) : 1'b0;

// Tag RAM write enable (way 1)
reg tag1_write_m_r;
always @ *
begin
    tag1_write_m_r = 1'b0;

    // Cache flush (reset)
    if (state_q == STATE_RESET)
        tag1_write_m_r = 1'b1;
    // Cache flush
    else if (state_q == STATE_FLUSH)
        tag1_write_m_r = !tag_dirty_any_m_w;
    // Write - hit, mark as dirty
    else if (state_q == STATE_LOOKUP && (|inport_wr_m_q))
        tag1_write_m_r = tag1_hit_m_w;
    // Write - write after refill
    else if (state_q == STATE_WRITE)
        tag1_write_m_r = (replace_way_q == 1);
    // Write - mark entry as dirty
    else if (state_q == STATE_EVICT_WAIT && pmem_ack_w)
        tag1_write_m_r = (replace_way_q == 1);
    // Line refill
    else if (state_q == STATE_REFILL)
        tag1_write_m_r = pmem_ack_w && (replace_way_q == 1);
end

wire [L2_CACHE_TAG_DATA_W-1:0] tag1_data_out_m_w;

l2_cache_tag_ram
u_tag1
(
  .clk0_i(clk_i),
  .rst0_i(rst_i),
  .clk1_i(clk_i),
  .rst1_i(rst_i),

  // Read
  .addr0_i(tag_addr_x_r),
  .data0_o(tag1_data_out_m_w),

  // Write
  .addr1_i(tag_addr_m_r),
  .data1_i(tag_data_in_m_r),
  .wr1_i(tag1_write_m_r)
);

wire                              tag1_valid_m_w     = tag1_data_out_m_w[L2_CACHE_TAG_VALID_BIT];
wire                              tag1_dirty_m_w     = tag1_data_out_m_w[L2_CACHE_TAG_DIRTY_BIT];
wire [L2_CACHE_TAG_ADDR_BITS-1:0] tag1_addr_bits_m_w = tag1_data_out_m_w[`L2_CACHE_TAG_ADDR_RNG];

// Tag hit?
assign                           tag1_hit_m_w = tag1_valid_m_w ? (tag1_addr_bits_m_w == req_addr_tag_cmp_m_w) : 1'b0;


assign tag_hit_any_m_w = 1'b0
                   | tag0_hit_m_w
                   | tag1_hit_m_w
                    ;

assign tag_hit_and_dirty_m_w = 1'b0
                   | (tag0_hit_m_w & tag0_dirty_m_w)
                   | (tag1_hit_m_w & tag1_dirty_m_w)
                    ;

assign tag_dirty_any_m_w = 1'b0
                   | (tag0_valid_m_w & tag0_dirty_m_w)
                   | (tag1_valid_m_w & tag1_dirty_m_w)
                    ;

reg         evict_way_r;
reg [(L2_CACHE_LINE_SIZE*8)-1:0] evict_data_r;
reg [EVICT_ADDR_W-1:0] evict_addr_r;
always @ *
begin
    evict_way_r  = 1'b0;
    evict_addr_r = flushing_q ? {tag0_addr_bits_m_w, flush_addr_q} :
                                {tag0_addr_bits_m_w, inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG]};
    evict_data_r = data0_data_out_m_w;

    case (replace_way_q)
        1'd0:
        begin
            evict_way_r  = tag0_valid_m_w && tag0_dirty_m_w;
            evict_addr_r = flushing_q ? {tag0_addr_bits_m_w, flush_addr_q} :
                                        {tag0_addr_bits_m_w, inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG]};
            evict_data_r = data0_data_out_m_w;
        end
        1'd1:
        begin
            evict_way_r  = tag1_valid_m_w && tag1_dirty_m_w;
            evict_addr_r = flushing_q ? {tag1_addr_bits_m_w, flush_addr_q} :
                                        {tag1_addr_bits_m_w, inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG]};
            evict_data_r = data1_data_out_m_w;
        end
    endcase
end
assign                  evict_way_w  = (flushing_q || !tag_hit_any_m_w) && evict_way_r;
wire [EVICT_ADDR_W-1:0] evict_addr_w = evict_addr_r;
wire [(L2_CACHE_LINE_SIZE*8)-1:0] evict_data_w = evict_data_r;

//-----------------------------------------------------------------
// DATA RAMS
//-----------------------------------------------------------------
// Data addressing
reg [CACHE_DATA_ADDR_W-1:0] data_addr_x_r;
reg [CACHE_DATA_ADDR_W-1:0] data_addr_m_r;
reg [CACHE_DATA_ADDR_W-1:0] data_write_addr_q;

// Data RAM refill write address
always @ (posedge clk_i )
if (rst_i)
    data_write_addr_q <= {(CACHE_DATA_ADDR_W){1'b0}};
else if (state_q != STATE_REFILL && next_state_r == STATE_REFILL)
    data_write_addr_q <= pmem_addr_w[CACHE_DATA_ADDR_W+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
else if (state_q != STATE_EVICT && next_state_r == STATE_EVICT)
    data_write_addr_q <= data_addr_m_r + 1;
else if (state_q == STATE_REFILL && pmem_ack_w)
    data_write_addr_q <= data_write_addr_q + 1;
else if (state_q == STATE_EVICT && pmem_accept_w)
    data_write_addr_q <= data_write_addr_q + 1;

// Data RAM address
always @ *
begin
    data_addr_x_r = inport_addr_i[CACHE_DATA_ADDR_W+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
    data_addr_m_r = inport_addr_m_q[CACHE_DATA_ADDR_W+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];

    // Line refill / evict
    if (state_q == STATE_REFILL || state_q == STATE_EVICT)
    begin
        data_addr_x_r = data_write_addr_q;
        data_addr_m_r = data_addr_x_r;
    end
    else if (state_q == STATE_FLUSH || state_q == STATE_RESET)
    begin
        data_addr_x_r = {flush_addr_q, {(L2_CACHE_LINE_SIZE_W-BYTE_OFFSET_BITS){1'b0}}};
        data_addr_m_r = data_addr_x_r;
    end
    else if (state_q != STATE_EVICT && next_state_r == STATE_EVICT)
    begin
        data_addr_x_r = {inport_addr_m_q[`L2_CACHE_TAG_REQ_RNG], {(L2_CACHE_LINE_SIZE_W-BYTE_OFFSET_BITS){1'b0}}};
        data_addr_m_r = data_addr_x_r;
    end
    // Lookup post refill
    else if (state_q == STATE_READ)
    begin
        data_addr_x_r = inport_addr_m_q[CACHE_DATA_ADDR_W+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
    end
    // Possible line update on write
    else
        data_addr_m_r = inport_addr_m_q[CACHE_DATA_ADDR_W+BYTE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
end


// Data RAM write enable (way 0)
reg [DATA_WR_MASK_W-1:0] data0_write_m_r;
integer word_index;
always @ *
begin
    data0_write_m_r = '0;

    if (state_q == STATE_REFILL)
        data0_write_m_r = (pmem_ack_w && replace_way_q == 0) ? '1 : '0;
    else if (state_q == STATE_WRITE || state_q == STATE_LOOKUP)
    begin
        word_index = inport_addr_m_q[L2_CACHE_LINE_SIZE_W-1:BYTE_OFFSET_BITS];
        data0_write_m_r[ word_index*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag0_hit_m_w}};
    end
end

assign data0_data_in_m_w = (state_q == STATE_REFILL) ? pmem_read_data_w : {CACHE_LINE_WORDS{inport_data_m_q}};

genvar gi;
generate
    for (gi = 0; gi < CACHE_LINE_WORDS; gi = gi + 1) begin : gen_data0
        l2_cache_data_ram #(
            .ADDR_W(L2_CACHE_LINE_ADDR_W),
            .DATA_W(CORE_DATA_W)
        )
        u_data0
        (
          .clk0_i(clk_i),
          .rst0_i(rst_i),
          .clk1_i(clk_i),
          .rst1_i(rst_i),

          // Read
          .addr0_i(data_addr_x_r[CACHE_DATA_ADDR_W-1:WORD_OFFSET_BITS]), // kept same addressing approach
          .data0_i({CORE_DATA_W{1'b0}}),
          .wr0_i({CORE_STRB_W{1'b0}}),
          .data0_o(data0_data_out_m_w[gi*CORE_DATA_W+:CORE_DATA_W]),

          // Write
          .addr1_i(data_addr_m_r[CACHE_DATA_ADDR_W-1:WORD_OFFSET_BITS]),
          .data1_i(data0_data_in_m_w[gi*CORE_DATA_W+:CORE_DATA_W]),
          .wr1_i(data0_write_m_r[gi*CORE_STRB_W+:CORE_STRB_W]),
          .data1_o()
        );
    end
endgenerate

// Data RAM write enable (way 1)
reg [DATA_WR_MASK_W-1:0] data1_write_m_r;
always @ *
begin
    data1_write_m_r = {DATA_WR_MASK_W{1'b0}};

    if (state_q == STATE_REFILL)
        data1_write_m_r = (pmem_ack_w && replace_way_q == 1) ? {DATA_WR_MASK_W{1'b1}} : {DATA_WR_MASK_W{1'b0}};
    else if (state_q == STATE_WRITE || state_q == STATE_LOOKUP)
    begin
        case (inport_addr_m_q[L2_CACHE_LINE_SIZE_W-1:BYTE_OFFSET_BITS])
        3'd0: data1_write_m_r[ 0*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd1: data1_write_m_r[ 1*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd2: data1_write_m_r[ 2*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd3: data1_write_m_r[ 3*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd4: data1_write_m_r[ 4*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd5: data1_write_m_r[ 5*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd6: data1_write_m_r[ 6*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        3'd7: data1_write_m_r[ 7*CORE_STRB_W+:CORE_STRB_W ] = inport_wr_m_q & {CORE_STRB_W{tag1_hit_m_w}};
        default: ;
        endcase
    end
end

assign data1_data_in_m_w = (state_q == STATE_REFILL) ? pmem_read_data_w : {CACHE_LINE_WORDS{inport_data_m_q}};

generate
    for (gi = 0; gi < CACHE_LINE_WORDS; gi = gi + 1) begin : gen_data1
        l2_cache_data_ram #(
            .ADDR_W(L2_CACHE_LINE_ADDR_W),
            .DATA_W(CORE_DATA_W)
        )
        u_data1
        (
          .clk0_i(clk_i),
          .rst0_i(rst_i),
          .clk1_i(clk_i),
          .rst1_i(rst_i),

          // Read
          .addr0_i(data_addr_x_r[CACHE_DATA_ADDR_W-1:WORD_OFFSET_BITS]),
          .data0_i({CORE_DATA_W{1'b0}}),
          .wr0_i({CORE_STRB_W{1'b0}}),
          .data0_o(data1_data_out_m_w[gi*CORE_DATA_W+:CORE_DATA_W]),

          // Write
          .addr1_i(data_addr_m_r[CACHE_DATA_ADDR_W-1:WORD_OFFSET_BITS]),
          .data1_i(data1_data_in_m_w[gi*CORE_DATA_W+:CORE_DATA_W]),
          .wr1_i(data1_write_m_r[gi*CORE_STRB_W+:CORE_STRB_W]),
          .data1_o()
        );
    end
endgenerate

//-----------------------------------------------------------------
// Flush counter
//-----------------------------------------------------------------


always @ (posedge clk_i )
if (rst_i)
    flush_addr_q <= {(L2_CACHE_TAG_REQ_LINE_W){1'b0}};
else if ((state_q == STATE_RESET) || (state_q == STATE_FLUSH && next_state_r == STATE_FLUSH_ADDR))
    flush_addr_q <= flush_addr_q + 1;
else if (state_q == STATE_LOOKUP)
    flush_addr_q <= {(L2_CACHE_TAG_REQ_LINE_W){1'b0}};

always @ (posedge clk_i )
if (rst_i)
    flushing_q <= 1'b0;
else if (state_q == STATE_LOOKUP && next_state_r == STATE_FLUSH_ADDR)
    flushing_q <= 1'b1;
else if (state_q == STATE_FLUSH && next_state_r == STATE_LOOKUP)
    flushing_q <= 1'b0;

reg flush_last_q;
always @ (posedge clk_i )
if (rst_i)
    flush_last_q <= 1'b0;
else if (state_q == STATE_LOOKUP)
    flush_last_q <= 1'b0;
else if (flush_addr_q == {(L2_CACHE_TAG_REQ_LINE_W){1'b1}})
    flush_last_q <= 1'b1;

//-----------------------------------------------------------------
// Replacement Policy
//----------------------------------------------------------------- 
// Using random replacement policy - this way we cycle through the ways
// when needing to replace a line.
always @ (posedge clk_i )
if (rst_i)
    replace_way_q <= 0;
else if (state_q == STATE_WRITE || state_q == STATE_READ)
    replace_way_q <= replace_way_q + 1;
else if (flushing_q && tag_dirty_any_m_w && !evict_way_w && state_q != STATE_FLUSH_ADDR)
    replace_way_q <= replace_way_q + 1;
else if (state_q == STATE_EVICT_WAIT && next_state_r == STATE_FLUSH_ADDR)
    replace_way_q <= 0;
else if (state_q == STATE_FLUSH && next_state_r == STATE_LOOKUP)
    replace_way_q <= 0;
else if (state_q == STATE_LOOKUP && next_state_r == STATE_FLUSH_ADDR)
    replace_way_q <= 0;

//-----------------------------------------------------------------
// Output Result
//-----------------------------------------------------------------
localparam int DATA_SEL_W = (CACHE_LINE_WORDS > 1) ? $clog2(CACHE_LINE_WORDS) : 1;
logic [DATA_SEL_W-1:0] data_sel_q;

always_ff @(posedge clk_i) begin
    if (rst_i)
        data_sel_q <= '0;
    else
        data_sel_q <= data_addr_x_r[0 +: DATA_SEL_W];
end


// Data output mux
reg [CORE_DATA_W-1:0]  data_r;
reg [(L2_CACHE_LINE_SIZE*8)-1:0] data_wide_r;
always @ *
begin
    data_r      = {CORE_DATA_W{1'b0}};
    data_wide_r = data0_data_out_m_w;

    case (1'b1)
    tag0_hit_m_w: data_wide_r = data0_data_out_m_w;
    tag1_hit_m_w: data_wide_r = data1_data_out_m_w;
    endcase

    data_r = data_wide_r[ data_sel_q*CORE_DATA_W +: CORE_DATA_W ];

end

assign inport_data_rd_o  = data_r;

//-----------------------------------------------------------------
// Next State Logic
//-----------------------------------------------------------------
always @ *
begin
    next_state_r = state_q;

    case (state_q)
    //-----------------------------------------
    // STATE_RESET
    //-----------------------------------------
    STATE_RESET :
    begin
        // Final line checked
        if (flush_last_q)
            next_state_r = STATE_LOOKUP;
    end
    //-----------------------------------------
    // STATE_FLUSH_ADDR
    //-----------------------------------------
    STATE_FLUSH_ADDR : next_state_r = STATE_FLUSH;
    //-----------------------------------------
    // STATE_FLUSH
    //-----------------------------------------
    STATE_FLUSH :
    begin
        // Dirty line detected - evict unless initial cache reset cycle
        if (tag_dirty_any_m_w)
        begin
            // Evict dirty line - else wait for dirty way to be selected
            if (evict_way_w)
                next_state_r = STATE_EVICT;
        end
        // Final line checked, nothing dirty
        else if (flush_last_q)
            next_state_r = STATE_LOOKUP;
        else
            next_state_r = STATE_FLUSH_ADDR;
    end
    //-----------------------------------------
    // STATE_LOOKUP
    //-----------------------------------------
    STATE_LOOKUP :
    begin
        // Previous access missed in the cache
        if ((inport_rd_m_q || (inport_wr_m_q != '0)) && !tag_hit_any_m_w)
        begin
            // Evict dirty line first
            if (evict_way_w)
                next_state_r = STATE_EVICT;
            // Allocate line and fill
            else
                next_state_r = STATE_REFILL;
        end
        // Flush whole cache
        else if (flush_i)
            next_state_r = STATE_FLUSH_ADDR;
    end
    //-----------------------------------------
    // STATE_REFILL
    //-----------------------------------------
    STATE_REFILL :
    begin
        // End of refill
        if (pmem_ack_w)
        begin
            // Refill reason was write
            if (inport_wr_m_q != '0)
                next_state_r = STATE_WRITE;
            // Refill reason was read
            else
                next_state_r = STATE_READ;
        end
    end
    //-----------------------------------------
    // STATE_WRITE/READ
    //-----------------------------------------
    STATE_WRITE, STATE_READ :
    begin
        next_state_r = STATE_LOOKUP;
    end
    //-----------------------------------------
    // STATE_EVICT
    //-----------------------------------------
    STATE_EVICT :
    begin
        // End of evict, wait for write completion
        if (pmem_accept_w)
            next_state_r = STATE_EVICT_WAIT;
    end
    //-----------------------------------------
    // STATE_EVICT_WAIT
    //-----------------------------------------
    STATE_EVICT_WAIT :
    begin
        // Evict due to flush
        if (pmem_ack_w && flushing_q)
            next_state_r = STATE_FLUSH_ADDR;
        // Write ack, start re-fill now
        else if (pmem_ack_w)
            next_state_r = STATE_REFILL;
    end
    default:
        ;
   endcase
end

// Update state
always @ (posedge clk_i )
if (rst_i)
    state_q   <= STATE_RESET;
else
    state_q   <= next_state_r;

reg inport_ack_r;

always @ *
begin
    inport_ack_r = 1'b0;

    if (state_q == STATE_LOOKUP)
    begin
        // Normal hit - read or write
        if ((inport_rd_m_q || (inport_wr_m_q != '0)) && tag_hit_any_m_w)
            inport_ack_r = 1'b1;
    end
end

assign inport_ack_o = inport_ack_r;

//-----------------------------------------------------------------
// Bus Request
//-----------------------------------------------------------------
reg pmem_rd_q;
reg pmem_wr0_q;

always @ (posedge clk_i )
if (rst_i)
    pmem_rd_q   <= 1'b0;
else if (pmem_rd_w)
    pmem_rd_q   <= ~pmem_accept_w;

always @ (posedge clk_i )
if (rst_i)
    pmem_wr0_q   <= 1'b0;
else if (state_q != STATE_EVICT && next_state_r == STATE_EVICT)
    pmem_wr0_q   <= 1'b1;
else if (pmem_accept_w)
    pmem_wr0_q   <= 1'b0;

//-----------------------------------------------------------------
// Skid buffer for write data
//-----------------------------------------------------------------
reg         pmem_wr_q;
reg [(L2_CACHE_LINE_SIZE*8)-1:0] pmem_write_data_q;

always @ (posedge clk_i )
if (rst_i)
    pmem_wr_q <= 1'b0;
else if (pmem_wr_w && !pmem_accept_w)
    pmem_wr_q <= pmem_wr_w;
else if (pmem_accept_w)
    pmem_wr_q <= 1'b0;

always @ (posedge clk_i )
if (rst_i)
    pmem_write_data_q <= '0;
else if (!pmem_accept_w)
    pmem_write_data_q <= pmem_write_data_w;

//-----------------------------------------------------------------
// AXI Error Handling
//-----------------------------------------------------------------
reg error_q;
always @ (posedge clk_i )
if (rst_i)
    error_q   <= 1'b0;
else if (pmem_ack_w && pmem_error_w)
    error_q   <= 1'b1;
else if (inport_ack_o)
    error_q   <= 1'b0;

assign inport_error_o = error_q;

//-----------------------------------------------------------------
// Outport
//-----------------------------------------------------------------
wire refill_request_w   = (state_q != STATE_REFILL && next_state_r == STATE_REFILL);
wire evict_request_w    = (state_q == STATE_EVICT) && evict_way_w;

// AXI Read channel
assign pmem_rd_w         = (refill_request_w || pmem_rd_q);
assign pmem_wr_w         = (evict_request_w || pmem_wr_q) ? 1'b1 : 1'b0;
assign pmem_addr_w       = pmem_rd_w ? {inport_addr_m_q[ADDR_W-1:L2_CACHE_LINE_SIZE_W], {(L2_CACHE_LINE_SIZE_W){1'b0}}} :
                           {evict_addr_w, {(L2_CACHE_LINE_SIZE_W){1'b0}}};

assign pmem_len_w        = (refill_request_w || pmem_rd_q || (state_q == STATE_EVICT && pmem_wr0_q)) ? (CACHE_LINE_WORDS - 1) : '0;
assign pmem_write_data_w = pmem_wr_q ? pmem_write_data_q : evict_data_w;

assign outport_wr_o         = pmem_wr_w;
assign outport_rd_o         = pmem_rd_w;
assign outport_addr_o       = pmem_addr_w;
assign outport_write_data_o = pmem_write_data_w;

assign pmem_accept_w        = outport_accept_i;
assign pmem_ack_w           = outport_ack_i;
assign pmem_error_w         = outport_error_i;
assign pmem_read_data_w     = outport_read_data_i;

endmodule
