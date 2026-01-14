//==============================================================================
// File: direct_mapped_cache.v
// Description: Direct-Mapped Cache Controller
//              - 1 KB Cache, 32-byte blocks, 32 sets
//              - Write-back policy with dirty bits
//              - FSM-based controller
//==============================================================================

`include "cache_pkg.v"

module direct_mapped_cache (
    input  wire                         clk,
    input  wire                         rst,
    
    //--------------------------------------------------------------------------
    // CPU Interface
    //--------------------------------------------------------------------------
    input  wire                         cpu_req,        // CPU request valid
    input  wire                         cpu_rw,         // 0=Read, 1=Write
    input  wire [`ADDR_WIDTH-1:0]       cpu_addr,       // CPU address
    input  wire [`DATA_WIDTH-1:0]       cpu_wdata,      // CPU write data (word)
    input  wire [3:0]                   cpu_wstrb,      // Write strobe (byte enables)
    
    output reg                          cpu_ready,      // Ready for new request
    output reg                          cpu_resp,       // Response valid
    output reg  [`DATA_WIDTH-1:0]       cpu_rdata,      // CPU read data
    
    //--------------------------------------------------------------------------
    // Memory Interface
    //--------------------------------------------------------------------------
    output reg                          mem_req,        // Memory request
    output reg                          mem_rw,         // 0=Read, 1=Write
    output reg  [`ADDR_WIDTH-1:0]       mem_addr,       // Memory address
    output reg  [`BLOCK_BITS-1:0]       mem_wdata,      // Memory write data
    
    input  wire                         mem_ready,      // Memory ready
    input  wire                         mem_resp,       // Memory response valid
    input  wire [`BLOCK_BITS-1:0]       mem_rdata,      // Memory read data
    
    //--------------------------------------------------------------------------
    // Debug/Waveform Signals
    //--------------------------------------------------------------------------
    output wire                         dbg_hit,
    output wire                         dbg_miss,
    output wire [`STATE_WIDTH-1:0]      dbg_state,
    output wire                         dbg_valid,
    output wire                         dbg_dirty,
    output wire                         dbg_tag_match,
    output wire                         dbg_writeback
);

    //--------------------------------------------------------------------------
    // Cache Arrays
    //--------------------------------------------------------------------------
    reg                         valid_arr   [0:`DM_NUM_SETS-1];
    reg                         dirty_arr   [0:`DM_NUM_SETS-1];
    reg  [`DM_TAG_WIDTH-1:0]    tag_arr     [0:`DM_NUM_SETS-1];
    reg  [`BLOCK_BITS-1:0]      data_arr    [0:`DM_NUM_SETS-1];
    
    //--------------------------------------------------------------------------
    // Address Decomposition
    //--------------------------------------------------------------------------
    wire [`OFFSET_WIDTH-1:0]    req_offset;
    wire [`DM_INDEX_WIDTH-1:0]  req_index;
    wire [`DM_TAG_WIDTH-1:0]    req_tag;
    wire [2:0]                  req_word_offset;  // Which word in block (0-7)
    
    assign req_offset      = cpu_addr[`OFFSET_WIDTH-1:0];
    assign req_index       = cpu_addr[`OFFSET_WIDTH +: `DM_INDEX_WIDTH];
    assign req_tag         = cpu_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`DM_TAG_WIDTH];
    assign req_word_offset = cpu_addr[4:2];  // Bits [4:2] select word in 32-byte block
    
    //--------------------------------------------------------------------------
    // Latched Request
    //--------------------------------------------------------------------------
    reg  [`ADDR_WIDTH-1:0]      latched_addr;
    reg  [`DATA_WIDTH-1:0]      latched_wdata;
    reg  [3:0]                  latched_wstrb;
    reg                         latched_rw;
    
    wire [`OFFSET_WIDTH-1:0]    lat_offset;
    wire [`DM_INDEX_WIDTH-1:0]  lat_index;
    wire [`DM_TAG_WIDTH-1:0]    lat_tag;
    wire [2:0]                  lat_word_offset;
    
    assign lat_offset      = latched_addr[`OFFSET_WIDTH-1:0];
    assign lat_index       = latched_addr[`OFFSET_WIDTH +: `DM_INDEX_WIDTH];
    assign lat_tag         = latched_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`DM_TAG_WIDTH];
    assign lat_word_offset = latched_addr[4:2];
    
    //--------------------------------------------------------------------------
    // Hit/Miss Detection
    //--------------------------------------------------------------------------
    wire cache_valid;
    wire cache_dirty;
    wire tag_match;
    wire cache_hit;
    wire cache_miss;
    
    assign cache_valid = valid_arr[lat_index];
    assign cache_dirty = dirty_arr[lat_index];
    assign tag_match   = (tag_arr[lat_index] == lat_tag);
    assign cache_hit   = cache_valid && tag_match;
    assign cache_miss  = !cache_hit;
    
    //--------------------------------------------------------------------------
    // Block Data Access
    //--------------------------------------------------------------------------
    wire [`BLOCK_BITS-1:0]  current_block;
    assign current_block = data_arr[lat_index];
    
    // Extract word from block based on word offset
    function [`DATA_WIDTH-1:0] get_word;
        input [`BLOCK_BITS-1:0] block;
        input [2:0] word_sel;
        begin
            case (word_sel)
                3'd0: get_word = block[31:0];
                3'd1: get_word = block[63:32];
                3'd2: get_word = block[95:64];
                3'd3: get_word = block[127:96];
                3'd4: get_word = block[159:128];
                3'd5: get_word = block[191:160];
                3'd6: get_word = block[223:192];
                3'd7: get_word = block[255:224];
            endcase
        end
    endfunction
    
    // Update word in block with byte strobes
    function [`BLOCK_BITS-1:0] set_word;
        input [`BLOCK_BITS-1:0] block;
        input [2:0] word_sel;
        input [`DATA_WIDTH-1:0] new_word;
        input [3:0] wstrb;
        reg [`DATA_WIDTH-1:0] old_word;
        reg [`DATA_WIDTH-1:0] merged_word;
        begin
            old_word = get_word(block, word_sel);
            merged_word[7:0]   = wstrb[0] ? new_word[7:0]   : old_word[7:0];
            merged_word[15:8]  = wstrb[1] ? new_word[15:8]  : old_word[15:8];
            merged_word[23:16] = wstrb[2] ? new_word[23:16] : old_word[23:16];
            merged_word[31:24] = wstrb[3] ? new_word[31:24] : old_word[31:24];
            
            set_word = block;
            case (word_sel)
                3'd0: set_word[31:0]     = merged_word;
                3'd1: set_word[63:32]    = merged_word;
                3'd2: set_word[95:64]    = merged_word;
                3'd3: set_word[127:96]   = merged_word;
                3'd4: set_word[159:128]  = merged_word;
                3'd5: set_word[191:160]  = merged_word;
                3'd6: set_word[223:192]  = merged_word;
                3'd7: set_word[255:224]  = merged_word;
            endcase
        end
    endfunction
    
    //--------------------------------------------------------------------------
    // Writeback Address Reconstruction
    //--------------------------------------------------------------------------
    wire [`ADDR_WIDTH-1:0] writeback_addr;
    assign writeback_addr = {tag_arr[lat_index], lat_index, 5'b00000};
    
    //--------------------------------------------------------------------------
    // FSM State Register
    //--------------------------------------------------------------------------
    reg [`STATE_WIDTH-1:0] state, next_state;
    
    //--------------------------------------------------------------------------
    // Statistics Counters
    //--------------------------------------------------------------------------
    reg [31:0] hit_count;
    reg [31:0] miss_count;
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    reg hit_flag;
    reg miss_flag;
    reg writeback_flag;
    reg hit_latch;       // Latched hit signal for response phase
    reg miss_latch;      // Latched miss signal for response phase
    
    //--------------------------------------------------------------------------
    // Debug Signal Assignments
    //--------------------------------------------------------------------------
    assign dbg_hit       = hit_latch;   // Use latched value for response
    assign dbg_miss      = miss_latch;  // Use latched value for response
    assign dbg_state     = state;
    assign dbg_valid     = cache_valid;
    assign dbg_dirty     = cache_dirty;
    assign dbg_tag_match = tag_match;
    assign dbg_writeback = writeback_flag;
    
    //--------------------------------------------------------------------------
    // FSM: State Register
    //--------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= `S_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //--------------------------------------------------------------------------
    // FSM: Next State Logic
    //--------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        
        case (state)
            `S_IDLE: begin
                if (cpu_req && cpu_ready) begin
                    next_state = `S_COMPARE;
                end
            end
            
            `S_COMPARE: begin
                if (cache_hit) begin
                    next_state = `S_HIT;
                end else begin
                    next_state = `S_MISS_CHECK;
                end
            end
            
            `S_HIT: begin
                next_state = `S_RESP;
            end
            
            `S_MISS_CHECK: begin
                if (cache_valid && cache_dirty) begin
                    next_state = `S_WRITEBACK_INIT;
                end else begin
                    next_state = `S_ALLOCATE_INIT;
                end
            end
            
            `S_WRITEBACK_INIT: begin
                if (mem_ready) begin
                    next_state = `S_WRITEBACK;
                end
            end
            
            `S_WRITEBACK: begin
                if (mem_resp) begin
                    next_state = `S_ALLOCATE_INIT;
                end
            end
            
            `S_ALLOCATE_INIT: begin
                if (mem_ready) begin
                    next_state = `S_ALLOCATE;
                end
            end
            
            `S_ALLOCATE: begin
                if (mem_resp) begin
                    next_state = `S_UPDATE;
                end
            end
            
            `S_UPDATE: begin
                next_state = `S_RESP;
            end
            
            `S_RESP: begin
                next_state = `S_IDLE;
            end
            
            default: begin
                next_state = `S_IDLE;
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // FSM: Output and Datapath Logic
    //--------------------------------------------------------------------------
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset cache arrays
            for (i = 0; i < `DM_NUM_SETS; i = i + 1) begin
                valid_arr[i] <= 1'b0;
                dirty_arr[i] <= 1'b0;
                tag_arr[i]   <= {`DM_TAG_WIDTH{1'b0}};
                data_arr[i]  <= {`BLOCK_BITS{1'b0}};
            end
            
            // Reset outputs
            cpu_ready   <= 1'b1;
            cpu_resp    <= 1'b0;
            cpu_rdata   <= {`DATA_WIDTH{1'b0}};
            
            mem_req     <= 1'b0;
            mem_rw      <= 1'b0;
            mem_addr    <= {`ADDR_WIDTH{1'b0}};
            mem_wdata   <= {`BLOCK_BITS{1'b0}};
            
            // Reset latched values
            latched_addr  <= {`ADDR_WIDTH{1'b0}};
            latched_wdata <= {`DATA_WIDTH{1'b0}};
            latched_wstrb <= 4'b0;
            latched_rw    <= 1'b0;
            
            // Reset counters and flags
            hit_count      <= 32'd0;
            miss_count     <= 32'd0;
            hit_flag       <= 1'b0;
            miss_flag      <= 1'b0;
            writeback_flag <= 1'b0;
            hit_latch      <= 1'b0;
            miss_latch     <= 1'b0;
            
        end else begin
            // Default: clear single-cycle signals
            cpu_resp       <= 1'b0;
            mem_req        <= 1'b0;
            hit_flag       <= 1'b0;
            miss_flag      <= 1'b0;
            writeback_flag <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                // IDLE: Wait for CPU request
                //--------------------------------------------------------------
                `S_IDLE: begin
                    if (cpu_req && cpu_ready) begin
                        // Latch request
                        latched_addr  <= cpu_addr;
                        latched_wdata <= cpu_wdata;
                        latched_wstrb <= cpu_wstrb;
                        latched_rw    <= cpu_rw;
                        cpu_ready     <= 1'b0;
                        hit_latch     <= 1'b0;   // Clear latches for new request
                        miss_latch    <= 1'b0;
                    end
                end
                
                //--------------------------------------------------------------
                // COMPARE: Check for hit/miss (combinational in next_state)
                //--------------------------------------------------------------
                `S_COMPARE: begin
                    // Hit/miss determined combinationally
                end
                
                //--------------------------------------------------------------
                // HIT: Handle cache hit
                //--------------------------------------------------------------
                `S_HIT: begin
                    hit_flag   <= 1'b1;
                    hit_latch  <= 1'b1;   // Latch hit for response phase
                    miss_latch <= 1'b0;   // Clear miss latch
                    hit_count  <= hit_count + 1;
                    
                    if (latched_rw == 1'b0) begin
                        // READ HIT: Get word from cache
                        cpu_rdata <= get_word(current_block, lat_word_offset);
                    end else begin
                        // WRITE HIT: Update cache and set dirty
                        data_arr[lat_index]  <= set_word(current_block, lat_word_offset, 
                                                         latched_wdata, latched_wstrb);
                        dirty_arr[lat_index] <= 1'b1;
                    end
                end
                
                //--------------------------------------------------------------
                // MISS_CHECK: Check if writeback needed
                //--------------------------------------------------------------
                `S_MISS_CHECK: begin
                    miss_flag  <= 1'b1;
                    miss_latch <= 1'b1;   // Latch miss for response phase
                    hit_latch  <= 1'b0;   // Clear hit latch
                    miss_count <= miss_count + 1;
                end
                
                //--------------------------------------------------------------
                // WRITEBACK_INIT: Start writeback to memory
                //--------------------------------------------------------------
                `S_WRITEBACK_INIT: begin
                    writeback_flag <= 1'b1;
                    if (mem_ready) begin
                        mem_req   <= 1'b1;
                        mem_rw    <= 1'b1;  // Write
                        mem_addr  <= writeback_addr;
                        mem_wdata <= current_block;
                    end
                end
                
                //--------------------------------------------------------------
                // WRITEBACK: Wait for memory write to complete
                //--------------------------------------------------------------
                `S_WRITEBACK: begin
                    writeback_flag <= 1'b1;
                    // Wait for mem_resp
                end
                
                //--------------------------------------------------------------
                // ALLOCATE_INIT: Start block fetch from memory
                //--------------------------------------------------------------
                `S_ALLOCATE_INIT: begin
                    if (mem_ready) begin
                        mem_req  <= 1'b1;
                        mem_rw   <= 1'b0;  // Read
                        mem_addr <= {latched_addr[`ADDR_WIDTH-1:5], 5'b00000};  // Block-aligned
                    end
                end
                
                //--------------------------------------------------------------
                // ALLOCATE: Wait for memory read to complete
                //--------------------------------------------------------------
                `S_ALLOCATE: begin
                    // Wait for mem_resp
                end
                
                //--------------------------------------------------------------
                // UPDATE: Update cache with new block
                //--------------------------------------------------------------
                `S_UPDATE: begin
                    // Install new block in cache
                    valid_arr[lat_index] <= 1'b1;
                    tag_arr[lat_index]   <= lat_tag;
                    
                    if (latched_rw == 1'b0) begin
                        // READ MISS: Just install the block
                        data_arr[lat_index]  <= mem_rdata;
                        dirty_arr[lat_index] <= 1'b0;
                        cpu_rdata            <= get_word(mem_rdata, lat_word_offset);
                    end else begin
                        // WRITE MISS (write-allocate): Install and modify
                        data_arr[lat_index]  <= set_word(mem_rdata, lat_word_offset,
                                                         latched_wdata, latched_wstrb);
                        dirty_arr[lat_index] <= 1'b1;
                    end
                end
                
                //--------------------------------------------------------------
                // RESP: Send response to CPU
                //--------------------------------------------------------------
                `S_RESP: begin
                    cpu_resp  <= 1'b1;
                    cpu_ready <= 1'b1;
                end
                
                default: begin
                    cpu_ready <= 1'b1;
                end
            endcase
        end
    end

endmodule
