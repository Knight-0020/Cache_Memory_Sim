//==============================================================================
// File: main_memory.v
// Description: Simple Main Memory for Cache System
//              Supports block read/write for cache refill and writeback
//              Simulated latency for realistic behavior
//==============================================================================

`include "cache_pkg.v"

module main_memory (
    input  wire                         clk,
    input  wire                         rst,
    
    //--------------------------------------------------------------------------
    // Memory Interface (from Cache)
    //--------------------------------------------------------------------------
    input  wire                         mem_req,        // Memory request valid
    input  wire                         mem_rw,         // 0=Read, 1=Write
    input  wire [`ADDR_WIDTH-1:0]       mem_addr,       // Block-aligned address
    input  wire [`BLOCK_BITS-1:0]       mem_wdata,      // Write data (full block)
    
    output reg                          mem_ready,      // Memory ready for request
    output reg                          mem_resp,       // Response valid
    output reg  [`BLOCK_BITS-1:0]       mem_rdata       // Read data (full block)
);

    //--------------------------------------------------------------------------
    // Memory Array
    // 64 KB addressable memory for testing (can be increased)
    // Organized as 32-bit words
    //--------------------------------------------------------------------------
    localparam MEM_SIZE_WORDS = 16384;  // 64KB / 4 = 16K words
    
    reg [31:0] mem_array [0:MEM_SIZE_WORDS-1];
    
    //--------------------------------------------------------------------------
    // Latency Counter
    //--------------------------------------------------------------------------
    reg [3:0] latency_counter;
    reg       pending_req;
    reg       pending_rw;
    reg [`ADDR_WIDTH-1:0] pending_addr;
    reg [`BLOCK_BITS-1:0] pending_wdata;
    
    //--------------------------------------------------------------------------
    // FSM States
    //--------------------------------------------------------------------------
    localparam M_IDLE     = 2'd0;
    localparam M_LATENCY  = 2'd1;
    localparam M_RESPOND  = 2'd2;
    
    reg [1:0] mem_state;
    
    //--------------------------------------------------------------------------
    // Word address calculation
    //--------------------------------------------------------------------------
    wire [31:0] base_word_addr;
    assign base_word_addr = pending_addr[`ADDR_WIDTH-1:2];  // Divide by 4
    
    //--------------------------------------------------------------------------
    // Initialize Memory with Pattern
    //--------------------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE_WORDS; i = i + 1) begin
            // Initialize with address-based pattern for easy debugging
            mem_array[i] = i * 4;  // Each word contains its byte address
        end
    end
    
    //--------------------------------------------------------------------------
    // Memory Controller FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_state       <= M_IDLE;
            mem_ready       <= 1'b1;
            mem_resp        <= 1'b0;
            mem_rdata       <= {`BLOCK_BITS{1'b0}};
            latency_counter <= 4'd0;
            pending_req     <= 1'b0;
            pending_rw      <= 1'b0;
            pending_addr    <= {`ADDR_WIDTH{1'b0}};
            pending_wdata   <= {`BLOCK_BITS{1'b0}};
        end else begin
            case (mem_state)
                //--------------------------------------------------------------
                // IDLE: Wait for memory request
                //--------------------------------------------------------------
                M_IDLE: begin
                    mem_resp <= 1'b0;
                    
                    if (mem_req && mem_ready) begin
                        // Latch request
                        pending_req   <= 1'b1;
                        pending_rw    <= mem_rw;
                        pending_addr  <= {mem_addr[`ADDR_WIDTH-1:5], 5'b00000};  // Block-align
                        pending_wdata <= mem_wdata;
                        
                        // Start latency countdown
                        latency_counter <= `MEM_LATENCY;
                        mem_ready       <= 1'b0;
                        mem_state       <= M_LATENCY;
                    end
                end
                
                //--------------------------------------------------------------
                // LATENCY: Simulate memory access time
                //--------------------------------------------------------------
                M_LATENCY: begin
                    if (latency_counter > 0) begin
                        latency_counter <= latency_counter - 1;
                    end else begin
                        mem_state <= M_RESPOND;
                    end
                end
                
                //--------------------------------------------------------------
                // RESPOND: Complete the memory operation
                //--------------------------------------------------------------
                M_RESPOND: begin
                    if (pending_rw == 1'b0) begin
                        // READ: Assemble 32-byte block (8 words)
                        mem_rdata <= {
                            mem_array[base_word_addr + 7],
                            mem_array[base_word_addr + 6],
                            mem_array[base_word_addr + 5],
                            mem_array[base_word_addr + 4],
                            mem_array[base_word_addr + 3],
                            mem_array[base_word_addr + 2],
                            mem_array[base_word_addr + 1],
                            mem_array[base_word_addr + 0]
                        };
                    end else begin
                        // WRITE: Store 32-byte block (8 words)
                        mem_array[base_word_addr + 0] <= pending_wdata[31:0];
                        mem_array[base_word_addr + 1] <= pending_wdata[63:32];
                        mem_array[base_word_addr + 2] <= pending_wdata[95:64];
                        mem_array[base_word_addr + 3] <= pending_wdata[127:96];
                        mem_array[base_word_addr + 4] <= pending_wdata[159:128];
                        mem_array[base_word_addr + 5] <= pending_wdata[191:160];
                        mem_array[base_word_addr + 6] <= pending_wdata[223:192];
                        mem_array[base_word_addr + 7] <= pending_wdata[255:224];
                    end
                    
                    mem_resp    <= 1'b1;
                    pending_req <= 1'b0;
                    mem_state   <= M_IDLE;
                    mem_ready   <= 1'b1;
                end
                
                default: begin
                    mem_state <= M_IDLE;
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // Debug: Direct memory peek (for testbench verification)
    //--------------------------------------------------------------------------
    function [31:0] peek_word;
        input [31:0] byte_addr;
        begin
            peek_word = mem_array[byte_addr[`ADDR_WIDTH-1:2]];
        end
    endfunction

endmodule
