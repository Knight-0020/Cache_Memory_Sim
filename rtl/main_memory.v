//==============================================================================
// File: main_memory.v
// Description: Byte-addressable main memory (256 x 8-bit)
//              Synchronous read with 1-cycle latency, synchronous write
//==============================================================================

module main_memory (
    input  wire        clk,
    input  wire        we,        // Write enable
    input  wire [7:0]  addr,      // 8-bit address (256 locations)
    input  wire [7:0]  wdata,     // Write data (1 byte)
    output reg  [7:0]  rdata      // Read data (1 byte, 1-cycle latency)
);

    //--------------------------------------------------------------------------
    // Memory Array: 256 bytes
    //--------------------------------------------------------------------------
    reg [7:0] mem [0:255];

    //--------------------------------------------------------------------------
    // Initialize memory with some pattern for testing
    // Each location initialized to its own address value
    //--------------------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = i[7:0];
        end
    end

    //--------------------------------------------------------------------------
    // Synchronous Write
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata;
        end
    end

    //--------------------------------------------------------------------------
    // Synchronous Read (1-cycle latency)
    // Read data is registered on clock edge
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
