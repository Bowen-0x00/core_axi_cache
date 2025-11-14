// tb_l2_cache.sv
`timescale 1ns/1ps

`include "axi/assign.svh"
`include "axi/typedef.svh"

module tb #(
  parameter AXI_ID       = 0,
  parameter ADDR_W       = 32,
  parameter CORE_DATA_W  = 256,             // cpu-side data width
  parameter LINE_BYTES   = 64,             // bytes per cache line
  parameter LINE_DATA_W  = (LINE_BYTES*8)  // derived: bits per line
);

  // derived widths
  localparam WSTRB_W = LINE_BYTES;         // write strobe width (bytes)
  localparam CORE_STRB_W   = (CORE_DATA_W/8);

  // ID / USER widths for AXI model (match your DUT outport id width)
  localparam int ID_W   = 4;
  localparam int USER_W = 1;

  // clock / reset
  logic clk;
  logic rst;

  // dbg
  logic dbg_mode_i;

  // inport (CPU side)
  logic                         inport_awvalid_i;
  logic [ADDR_W-1:0]            inport_awaddr_i;
  logic [ 3:0]                  inport_awid_i;
  logic [ 7:0]                  inport_awlen_i;
  logic [ 1:0]                  inport_awburst_i;
  logic [ 2:0]                  inport_awsize_i;
  logic                         inport_wvalid_i;
  logic [CORE_DATA_W-1:0]       inport_wdata_i;
  logic [CORE_STRB_W-1:0]       inport_wstrb_i;
  logic                         inport_wlast_i;
  logic                         inport_bready_i;
  logic                         inport_arvalid_i;
  logic [ADDR_W-1:0]            inport_araddr_i;
  logic [ 3:0]                  inport_arid_i;
  logic [ 7:0]                  inport_arlen_i;
  logic [ 1:0]                  inport_arburst_i;
  logic [ 2:0]                  inport_arsize_i;
  logic                         inport_rready_i;

  // outport responses from memory model into DUT (driven by axi_sim_mem)
  logic                         outport_awready_i;
  logic                         outport_wready_i;
  logic                         outport_bvalid_i;
  logic [1:0]                   outport_bresp_i;
  logic [3:0]                   outport_bid_i;
  logic                         outport_arready_i;
  logic                         outport_rvalid_i;
  logic [LINE_DATA_W-1:0]       outport_rdata_i;
  logic [1:0]                   outport_rresp_i;
  logic [3:0]                   outport_rid_i;
  logic                         outport_rlast_i;

  // Outputs from DUT (observed/driven by DUT)
  logic                         inport_awready_o;
  logic                         inport_wready_o;
  logic                         inport_bvalid_o;
  logic [1:0]                   inport_bresp_o;
  logic [3:0]                   inport_bid_o;
  logic                         inport_arready_o;
  logic                         inport_rvalid_o;
  logic [CORE_DATA_W-1:0]       inport_rdata_o;
  logic [1:0]                   inport_rresp_o;
  logic [3:0]                   inport_rid_o;
  logic                         inport_rlast_o;

  logic                         outport_awvalid_o;
  logic [ADDR_W-1:0]            outport_awaddr_o;
  logic [ 3:0]                  outport_awid_o;
  logic [ 7:0]                  outport_awlen_o;
  logic [ 1:0]                  outport_awburst_o;
  logic                         outport_wvalid_o;
  logic [LINE_DATA_W-1:0]       outport_wdata_o;
  logic [WSTRB_W-1:0]           outport_wstrb_o;
  logic                         outport_wlast_o;
  logic                         outport_bready_o;
  logic                         outport_arvalid_o;
  logic [ADDR_W-1:0]            outport_araddr_o;
  logic [ 3:0]                  outport_arid_o;
  logic [ 7:0]                  outport_arlen_o;
  logic [ 2:0]                  outport_arsize_o;
  logic [ 1:0]                  outport_arburst_o;
  logic                         outport_rready_o;

  // instantiate DUT with parameters forwarded
  l2_cache #(
    .AXI_ID       (AXI_ID),
    .ADDR_W       (ADDR_W),
    .CORE_DATA_W  (CORE_DATA_W),
    .LINE_BYTES   (LINE_BYTES),
    .LINE_DATA_W  (LINE_DATA_W)
  ) dut (
    .clk_i               (clk),
    .rst_i               (rst),
    .dbg_mode_i          (dbg_mode_i),

    // inport (inputs)
    .inport_awvalid_i    (inport_awvalid_i),
    .inport_awaddr_i     (inport_awaddr_i),
    .inport_awid_i       (inport_awid_i),
    .inport_awlen_i      (inport_awlen_i),
    .inport_awburst_i    (inport_awburst_i),
    .inport_awsize_i     (inport_awsize_i),
    .inport_wvalid_i     (inport_wvalid_i),
    .inport_wdata_i      (inport_wdata_i),
    .inport_wstrb_i      (inport_wstrb_i),
    .inport_wlast_i      (inport_wlast_i),
    .inport_bready_i     (inport_bready_i),
    .inport_arvalid_i    (inport_arvalid_i),
    .inport_araddr_i     (inport_araddr_i),
    .inport_arid_i       (inport_arid_i),
    .inport_arlen_i      (inport_arlen_i),
    .inport_arburst_i    (inport_arburst_i),
    .inport_arsize_i     (inport_arsize_i),
    .inport_rready_i     (inport_rready_i),

    // outport inputs (responses from memory model)
    .outport_awready_i   (outport_awready_i),
    .outport_wready_i    (outport_wready_i),
    .outport_bvalid_i    (outport_bvalid_i),
    .outport_bresp_i     (outport_bresp_i),
    .outport_bid_i       (outport_bid_i),
    .outport_arready_i   (outport_arready_i),
    .outport_rvalid_i    (outport_rvalid_i),
    .outport_rdata_i     (outport_rdata_i),
    .outport_rresp_i     (outport_rresp_i),
    .outport_rid_i       (outport_rid_i),
    .outport_rlast_i     (outport_rlast_i),

    // inport outputs (responses to CPU)
    .inport_awready_o    (inport_awready_o),
    .inport_wready_o     (inport_wready_o),
    .inport_bvalid_o     (inport_bvalid_o),
    .inport_bresp_o      (inport_bresp_o),
    .inport_bid_o        (inport_bid_o),
    .inport_arready_o    (inport_arready_o),
    .inport_rvalid_o     (inport_rvalid_o),
    .inport_rdata_o      (inport_rdata_o),
    .inport_rresp_o      (inport_rresp_o),
    .inport_rid_o        (inport_rid_o),
    .inport_rlast_o      (inport_rlast_o),

    // outport outputs (requests to memory)
    .outport_awvalid_o   (outport_awvalid_o),
    .outport_awaddr_o    (outport_awaddr_o),
    .outport_awid_o      (outport_awid_o),
    .outport_awlen_o     (outport_awlen_o),
    .outport_awburst_o   (outport_awburst_o),
    .outport_wvalid_o    (outport_wvalid_o),
    .outport_wdata_o     (outport_wdata_o),
    .outport_wstrb_o     (outport_wstrb_o),
    .outport_wlast_o     (outport_wlast_o),
    .outport_bready_o    (outport_bready_o),
    .outport_arvalid_o   (outport_arvalid_o),
    .outport_araddr_o    (outport_araddr_o),
    .outport_arid_o      (outport_arid_o),
    .outport_arlen_o     (outport_arlen_o),
    .outport_arsize_o    (outport_arsize_o),
    .outport_arburst_o   (outport_arburst_o),
    .outport_rready_o    (outport_rready_o)
  );

  // -------------------------------------------------------------------
  // Clock & reset
  // -------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz -> 10ns period
  end

  initial begin
    rst = 1;
    dbg_mode_i <= '0;

    // clear inputs
    inport_awvalid_i <= '0;
    inport_awaddr_i  <= '0;
    inport_awid_i    <= '0;
    inport_awlen_i   <= '0;
    inport_awburst_i <= '0;
    inport_awsize_i  <= '0;

    inport_wvalid_i  <= '0;
    inport_wdata_i   <= '0;
    inport_wstrb_i   <= '0;
    inport_wlast_i   <= '0;

    inport_bready_i  <= '1;

    inport_arvalid_i <= '0;
    inport_araddr_i  <= '0;
    inport_arid_i    <= '0;
    inport_arlen_i   <= '0;
    inport_arburst_i <= '0;
    inport_arsize_i  <= '0;

    inport_rready_i  <= '1;

    // NOTE: outport_*_i (memory responses) are driven by axi_sim_mem below --
    //       do NOT initialize them here to avoid multiple drivers.

    // wait reset cycles
    repeat (5) @(posedge clk);
    rst = 0;
    repeat (5) @(posedge clk);

    $display("[%0t] TB: start test", $time);

    // example: use sized literals to avoid width mismatch
    axi_inport_write({{(ADDR_W-32){1'b0}}, 32'h0000_1000}, {128'hFFEEDDCCBBAA99887766554433221100}, 4'd0);
    repeat (50) @(posedge clk);
    axi_inport_read({{(ADDR_W-32){1'b0}}, 32'h0000_1000}, 4'd0);

    axi_inport_read({{(ADDR_W-32){1'b0}}, 32'h0000_0000}, 4'd0);
    $display("[%0t] TB: done", $time);
    #100;
    $finish;
  end

  // -------------------------------------------------------------------
  // Simple AXI memory model replaced by axi_sim_mem instantiation
  // -------------------------------------------------------------------
  // typedefs for AXI model
  typedef logic [ADDR_W-1:0]        addr_t;
  typedef logic [LINE_DATA_W-1:0]   data_t;
  typedef logic [ID_W-1:0]          id_t;
  typedef logic [WSTRB_W-1:0]       strb_t;
  typedef logic [USER_W-1:0]        user_t;

  // create struct typedefs
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)

  // single-port arrays (axi_sim_mem expects arrays [NumPorts-1:0])
  axi_req_t  [0:0] axi_req_arr  ;
  axi_resp_t  [0:0] axi_resp_arr  ;

  // build request struct from DUT outport signals
  // (always_comb used to avoid multiple drivers / blocking)
  always_comb begin
    // default-clear whole struct to avoid x-propagation
    axi_req_arr[0] = '0;

    // AW channel
    axi_req_arr[0].aw_valid = outport_awvalid_o;
    axi_req_arr[0].aw.addr  = outport_awaddr_o;
    axi_req_arr[0].aw.id    = outport_awid_o;
    axi_req_arr[0].aw.len   = outport_awlen_o;
    axi_req_arr[0].aw.burst = outport_awburst_o;
    // size can be left 0 or user can extend if needed

    // W channel
    axi_req_arr[0].w_valid = outport_wvalid_o;
    axi_req_arr[0].w.data  = outport_wdata_o;
    axi_req_arr[0].w.strb  = outport_wstrb_o;
    axi_req_arr[0].w.last  = outport_wlast_o;

    // B channel (master side indicates ready)
    axi_req_arr[0].b_ready = outport_bready_o;

    // AR channel
    axi_req_arr[0].ar_valid = outport_arvalid_o;
    axi_req_arr[0].ar.addr  = outport_araddr_o;
    axi_req_arr[0].ar.id    = outport_arid_o;
    axi_req_arr[0].ar.len   = outport_arlen_o;
    axi_req_arr[0].ar.size  = outport_arsize_o;
    axi_req_arr[0].ar.burst = outport_arburst_o;

    // R channel (master side indicates ready)
    axi_req_arr[0].r_ready = outport_rready_o;
  end

  // map axi_sim_mem responses back to DUT outport_*_i signals
  // use continuous assign so only axi_sim_mem drives these signals
  assign outport_awready_i = axi_resp_arr[0].aw_ready;
  assign outport_wready_i  = axi_resp_arr[0].w_ready;
  assign outport_bvalid_i  = axi_resp_arr[0].b_valid;
  assign outport_bresp_i   = axi_resp_arr[0].b.resp;
  assign outport_bid_i     = axi_resp_arr[0].b.id;
  assign outport_arready_i = axi_resp_arr[0].ar_ready;
  assign outport_rvalid_i  = axi_resp_arr[0].r_valid;
  assign outport_rdata_i   = axi_resp_arr[0].r.data;
  assign outport_rresp_i   = axi_resp_arr[0].r.resp;
  assign outport_rid_i     = axi_resp_arr[0].r.id;
  assign outport_rlast_i   = axi_resp_arr[0].r.last;

  // instantiate the axi_sim_mem (single port)
  axi_sim_mem #(
    .AddrWidth  (ADDR_W),
    .DataWidth  (LINE_DATA_W),
    .IdWidth    (ID_W),
    .UserWidth  (USER_W),
    .axi_req_t  (axi_req_t),
    .axi_rsp_t  (axi_resp_t),
    .NumPorts   (1)
  ) i_axi_sim_mem (
    .clk_i             ( clk           ),
    .rst_ni            ( ~rst          ), // axi_sim_mem expects active-low reset
    .axi_req_i         ( axi_req_arr   ),
    .axi_rsp_o         ( axi_resp_arr   ),
    // monitors left unconnected (optional)
    .mon_w_valid_o     ( ),
    .mon_w_addr_o      ( ),
    .mon_w_data_o      ( ),
    .mon_w_id_o        ( ),
    .mon_w_user_o      ( ),
    .mon_w_beat_count_o( ),
    .mon_w_last_o      ( ),
    .mon_r_valid_o     ( ),
    .mon_r_addr_o      ( ),
    .mon_r_data_o      ( ),
    .mon_r_id_o        ( ),
    .mon_r_user_o      ( ),
    .mon_r_beat_count_o( ),
    .mon_r_last_o      ( )
  );

  // -------------------------------------------------------------------
  // TB tasks: drive inport single-beat write and single-beat read
  // (unchanged)
  // -------------------------------------------------------------------
  task automatic axi_inport_write(input logic [ADDR_W-1:0] addr, input logic [CORE_DATA_W-1:0] data, input logic [3:0] id = 4'd0);
    begin
      $display("[%0t] TB: start inport write id=%0d addr=0x%0h data=0x%0h", $time, id, addr, data);

      // AW channel
      inport_awaddr_i <= addr;
      inport_awid_i   <= id;
      inport_awlen_i  <= '0;                    // single beat
      inport_awburst_i<= 2'b01;                 // INCR
      // choose awsize consistent with CORE_DATA_W (log2(bytes))
      unique case (CORE_DATA_W)
        8:  inport_awsize_i <= 3'd0; // 1 byte
        16: inport_awsize_i <= 3'd1; // 2 bytes
        32: inport_awsize_i <= 3'd2; // 4 bytes
        64: inport_awsize_i <= 3'd3; // 8 bytes
        default: inport_awsize_i <= 3'd2; // fallback to 4 bytes
      endcase
      inport_awvalid_i<= 1;
      @(posedge clk);
      wait (inport_awready_o == 1);
      inport_awvalid_i <= 0;

      // W channel (single beat)
      inport_wdata_i <= data;
      // strobe: set all bytes valid for the core data width
      inport_wstrb_i <= {CORE_STRB_W{1'b1}};
      inport_wlast_i <= 1;
      inport_wvalid_i <= 1;
      inport_bready_i <= 1;
      @(posedge clk);
      wait (inport_wready_o == 1);
      inport_wvalid_i <= 0;
      inport_wlast_i  <= 0;

      @(posedge clk);
      wait (inport_bvalid_o == 1);
      $display("[%0t] TB: got B from DUT resp=%0d id=%0d", $time, inport_bresp_o, inport_bid_o);
      @(posedge clk);
      inport_bready_i <= 0;
    end
  endtask

  task automatic axi_inport_read(input logic [ADDR_W-1:0] addr, input logic [3:0] id = 4'd0);
    logic [CORE_DATA_W-1:0] read_data;
    begin
      $display("[%0t] TB: start inport read id=%0d addr=0x%0h", $time, id, addr);

      // AR channel
      inport_araddr_i <= addr;
      inport_arid_i   <= id;
      inport_arlen_i  <= '0;       // single beat
      inport_arburst_i<= 2'b01;
      unique case (CORE_DATA_W)
        8:  inport_arsize_i <= 3'd0;
        16: inport_arsize_i <= 3'd1;
        32: inport_arsize_i <= 3'd2;
        64: inport_arsize_i <= 3'd3;
        default: inport_arsize_i <= 3'd2;
      endcase
      inport_arvalid_i<= 1;
      @(posedge clk);
      wait (inport_arready_o == 1);
      inport_arvalid_i <= 0;

      // R channel: we are ready to accept
      inport_rready_i <= 1;
      @(posedge clk);
      wait (inport_rvalid_o == 1);
      read_data = inport_rdata_o;
      $display("[%0t] TB: got R from DUT data=0x%0h resp=%0d id=%0d", $time, read_data, inport_rresp_o, inport_rid_o);
      inport_rready_i <= 0;
    end
  endtask

  // -------------------------------------------------------------------
  // Timeout & finish
  // -------------------------------------------------------------------
  initial begin
    repeat(10000) @(posedge clk);
    $display("TB: timeout reached");
    $finish;
  end

  initial begin
    $readmemh("../data.hex", i_axi_sim_mem.mem);
    // $readmemh("../data.hex", i_axi_sim_mem.rerr);
    // $readmemh("../data.hex", i_axi_sim_mem.werr);
    
    repeat(10) @(posedge clk);
    $display("====Mem[0]: %X", i_axi_sim_mem.mem[32'd0]);
  end

endmodule
