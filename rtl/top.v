//==============================================================================
// File: top.v
// Description: Top-level module instantiating cache and main memory
//              Exposes CPU-side interface for testbench
//==============================================================================

module top (
    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst,

    //--------------------------------------------------------------------------
    // CPU-side Interface (directly exposed from cache)
    //--------------------------------------------------------------------------
    input  wire        req_valid,      // Request valid
    input  wire        req_rw,         // 0=read, 1=write
    input  wire [7:0]  req_addr,       // Request address
    input  wire [7:0]  req_wdata,      // Write data (byte)
    
    output wire        resp_valid,     // Response valid
    output wire [7:0]  resp_rdata,     // Response read data
    output wire        hit,            // Hit indicator
    output wire        ready,          // Ready to accept request
    output wire [31:0] hit_count,      // Hit counter
    output wire [31:0] miss_count      // Miss counter
);

    //--------------------------------------------------------------------------
    // Internal Wires: Memory Interface between Cache and Main Memory
    //--------------------------------------------------------------------------
    wire        mem_we;
    wire [7:0]  mem_addr;
    wire [7:0]  mem_wdata;
    wire [7:0]  mem_rdata;

    //--------------------------------------------------------------------------
    // Cache Instance
    //--------------------------------------------------------------------------
    cache_direct_mapped u_cache (
        // Clock and Reset
        .clk         (clk),
        .rst         (rst),
        
        // CPU-side Interface
        .req_valid   (req_valid),
        .req_rw      (req_rw),
        .req_addr    (req_addr),
        .req_wdata   (req_wdata),
        .resp_valid  (resp_valid),
        .resp_rdata  (resp_rdata),
        .hit         (hit),
        .ready       (ready),
        .hit_count   (hit_count),
        .miss_count  (miss_count),
        
        // Memory-side Interface
        .mem_we      (mem_we),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata)
    );

    //--------------------------------------------------------------------------
    // Main Memory Instance
    //--------------------------------------------------------------------------
    main_memory u_mem (
        .clk         (clk),
        .we          (mem_we),
        .addr        (mem_addr),
        .wdata       (mem_wdata),
        .rdata       (mem_rdata)
    );

endmodule
