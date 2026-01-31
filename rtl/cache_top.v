//==============================================================================
// File: cache_top.v
// Description: Top-level module for Cache Memory System
//              Selects between Direct-Mapped and 2-Way Set-Associative cache
//              Connects cache to main memory
//==============================================================================

`include "cache_pkg.v"

// Direct-Mapped Cache Only implementation

module cache_top (
    input  wire                         clk,
    input  wire                         rst,
    
    //--------------------------------------------------------------------------
    // CPU Interface
    //--------------------------------------------------------------------------
    input  wire                         cpu_req,
    input  wire                         cpu_rw,
    input  wire [`ADDR_WIDTH-1:0]       cpu_addr,
    input  wire [`DATA_WIDTH-1:0]       cpu_wdata,
    input  wire [3:0]                   cpu_wstrb,
    
    output wire                         cpu_ready,
    output wire                         cpu_resp,
    output wire [`DATA_WIDTH-1:0]       cpu_rdata,
    
    //--------------------------------------------------------------------------
    // Debug Signals (directly exposed for waveform)
    //--------------------------------------------------------------------------
    output wire                         dbg_hit,
    output wire                         dbg_miss,
    output wire [`STATE_WIDTH-1:0]      dbg_state,
    output wire                         dbg_writeback,
    
    // Additional debug for SA cache
    output wire [1:0]                   dbg_valid,
    output wire [1:0]                   dbg_dirty,
    output wire [1:0]                   dbg_tag_match,
    output wire                         dbg_lru,
    output wire                         dbg_selected_way
);

    //--------------------------------------------------------------------------
    // Memory Interface Wires
    //--------------------------------------------------------------------------
    wire                        mem_req;
    wire                        mem_rw;
    wire [`ADDR_WIDTH-1:0]      mem_addr;
    wire [`BLOCK_BITS-1:0]      mem_wdata;
    wire                        mem_ready;
    wire                        mem_resp;
    wire [`BLOCK_BITS-1:0]      mem_rdata;

    //--------------------------------------------------------------------------
    // Cache Instance Selection
    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // Cache Instance Selection
    //--------------------------------------------------------------------------
    // Direct-Mapped Cache
    direct_mapped_cache u_cache (
        .clk            (clk),
        .rst            (rst),
        
        // CPU Interface
        .cpu_req        (cpu_req),
        .cpu_rw         (cpu_rw),
        .cpu_addr       (cpu_addr),
        .cpu_wdata      (cpu_wdata),
        .cpu_wstrb      (cpu_wstrb),
        .cpu_ready      (cpu_ready),
        .cpu_resp       (cpu_resp),
        .cpu_rdata      (cpu_rdata),
        
        // Memory Interface
        .mem_req        (mem_req),
        .mem_rw         (mem_rw),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_ready      (mem_ready),
        .mem_resp       (mem_resp),
        .mem_rdata      (mem_rdata),
        
        // Debug
        .dbg_hit        (dbg_hit),
        .dbg_miss       (dbg_miss),
        .dbg_state      (dbg_state),
        .dbg_valid      (dbg_valid_dm),
        .dbg_dirty      (dbg_dirty_dm),
        .dbg_tag_match  (dbg_tag_match_dm),
        .dbg_writeback  (dbg_writeback)
    );
    
    // Map DM debug to 2-bit outputs (replicate for compatibility if needed, or simplify output)
    // Simplified for Direct Mapped Only
    assign dbg_valid       = {1'b0, dbg_valid_dm};
    assign dbg_dirty       = {1'b0, dbg_dirty_dm};
    assign dbg_tag_match   = {1'b0, dbg_tag_match_dm};
    assign dbg_lru         = 1'b0;  
    assign dbg_selected_way = 1'b0;

    //--------------------------------------------------------------------------
    // Main Memory Instance
    //--------------------------------------------------------------------------
    main_memory u_mem (
        .clk            (clk),
        .rst            (rst),
        
        .mem_req        (mem_req),
        .mem_rw         (mem_rw),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        
        .mem_ready      (mem_ready),
        .mem_resp       (mem_resp),
        .mem_rdata      (mem_rdata)
    );

endmodule
