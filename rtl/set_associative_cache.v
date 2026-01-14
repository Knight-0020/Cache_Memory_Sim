//==============================================================================
// File: set_associative_cache.v
// Description: 2-Way Set-Associative Cache Controller
//              - 1 KB Cache, 32-byte blocks, 16 sets, 2 ways
//              - Write-back policy with dirty bits
//              - LRU replacement (1-bit per set)
//              - FSM-based controller
//==============================================================================

`include "cache_pkg.v"

module set_associative_cache (
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
    output wire [1:0]                   dbg_valid,      // Valid bits for both ways
    output wire [1:0]                   dbg_dirty,      // Dirty bits for both ways
    output wire [1:0]                   dbg_tag_match,  // Tag match for both ways
    output wire                         dbg_lru,        // LRU bit for current set
    output wire                         dbg_selected_way,
    output wire                         dbg_writeback
);

    //--------------------------------------------------------------------------
    // Cache Arrays (2 ways)
    //--------------------------------------------------------------------------
    // Way 0
    reg                         valid_arr_0   [0:`SA_NUM_SETS-1];
    reg                         dirty_arr_0   [0:`SA_NUM_SETS-1];
    reg  [`SA_TAG_WIDTH-1:0]    tag_arr_0     [0:`SA_NUM_SETS-1];
    reg  [`BLOCK_BITS-1:0]      data_arr_0    [0:`SA_NUM_SETS-1];
    
    // Way 1
    reg                         valid_arr_1   [0:`SA_NUM_SETS-1];
    reg                         dirty_arr_1   [0:`SA_NUM_SETS-1];
    reg  [`SA_TAG_WIDTH-1:0]    tag_arr_1     [0:`SA_NUM_SETS-1];
    reg  [`BLOCK_BITS-1:0]      data_arr_1    [0:`SA_NUM_SETS-1];
    
    // LRU bits: 0 = way 0 is LRU, 1 = way 1 is LRU
    reg                         lru_arr       [0:`SA_NUM_SETS-1];
    
    //--------------------------------------------------------------------------
    // Address Decomposition
    //--------------------------------------------------------------------------
    wire [`OFFSET_WIDTH-1:0]    req_offset;
    wire [`SA_INDEX_WIDTH-1:0]  req_index;
    wire [`SA_TAG_WIDTH-1:0]    req_tag;
    wire [2:0]                  req_word_offset;
    
    assign req_offset      = cpu_addr[`OFFSET_WIDTH-1:0];
    assign req_index       = cpu_addr[`OFFSET_WIDTH +: `SA_INDEX_WIDTH];
    assign req_tag         = cpu_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`SA_TAG_WIDTH];
    assign req_word_offset = cpu_addr[4:2];
    
    //--------------------------------------------------------------------------
    // Latched Request
    //--------------------------------------------------------------------------
    reg  [`ADDR_WIDTH-1:0]      latched_addr;
    reg  [`DATA_WIDTH-1:0]      latched_wdata;
    reg  [3:0]                  latched_wstrb;
    reg                         latched_rw;
    
    wire [`OFFSET_WIDTH-1:0]    lat_offset;
    wire [`SA_INDEX_WIDTH-1:0]  lat_index;
    wire [`SA_TAG_WIDTH-1:0]    lat_tag;
    wire [2:0]                  lat_word_offset;
    
    assign lat_offset      = latched_addr[`OFFSET_WIDTH-1:0];
    assign lat_index       = latched_addr[`OFFSET_WIDTH +: `SA_INDEX_WIDTH];
    assign lat_tag         = latched_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`SA_TAG_WIDTH];
    assign lat_word_offset = latched_addr[4:2];
    
    //--------------------------------------------------------------------------
    // Hit/Miss Detection for Both Ways
    //--------------------------------------------------------------------------
    wire valid_0, valid_1;
    wire dirty_0, dirty_1;
    wire tag_match_0, tag_match_1;
    wire hit_0, hit_1;
    wire cache_hit;
    wire cache_miss;
    wire hit_way;  // Which way hit (0 or 1)
    
    assign valid_0     = valid_arr_0[lat_index];
    assign valid_1     = valid_arr_1[lat_index];
    assign dirty_0     = dirty_arr_0[lat_index];
    assign dirty_1     = dirty_arr_1[lat_index];
    assign tag_match_0 = (tag_arr_0[lat_index] == lat_tag);
    assign tag_match_1 = (tag_arr_1[lat_index] == lat_tag);
    assign hit_0       = valid_0 && tag_match_0;
    assign hit_1       = valid_1 && tag_match_1;
    assign cache_hit   = hit_0 || hit_1;
    assign cache_miss  = !cache_hit;
    assign hit_way     = hit_1;  // 0 if way 0 hit, 1 if way 1 hit
    
    //--------------------------------------------------------------------------
    // LRU-based Victim Selection
    //--------------------------------------------------------------------------
    wire lru_bit;
    wire victim_way;
    wire victim_valid;
    wire victim_dirty;
    
    assign lru_bit      = lru_arr[lat_index];
    assign victim_way   = lru_bit;  // LRU way is the victim
    assign victim_valid = victim_way ? valid_1 : valid_0;
    assign victim_dirty = victim_way ? dirty_1 : dirty_0;
    
    //--------------------------------------------------------------------------
    // Selected Way for Operations
    //--------------------------------------------------------------------------
    reg selected_way;  // Registered: which way to operate on
    
    //--------------------------------------------------------------------------
    // Block Data Access
    //--------------------------------------------------------------------------
    wire [`BLOCK_BITS-1:0] current_block_0;
    wire [`BLOCK_BITS-1:0] current_block_1;
    wire [`BLOCK_BITS-1:0] hit_block;
    wire [`BLOCK_BITS-1:0] victim_block;
    
    assign current_block_0 = data_arr_0[lat_index];
    assign current_block_1 = data_arr_1[lat_index];
    assign hit_block       = hit_way ? current_block_1 : current_block_0;
    assign victim_block    = victim_way ? current_block_1 : current_block_0;
    
    // Extract word from block
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
    wire [`SA_TAG_WIDTH-1:0] victim_tag;
    assign victim_tag     = victim_way ? tag_arr_1[lat_index] : tag_arr_0[lat_index];
    assign writeback_addr = {victim_tag, lat_index, 5'b00000};
    
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
    assign dbg_hit          = hit_latch;   // Use latched value for response
    assign dbg_miss         = miss_latch;  // Use latched value for response
    assign dbg_state        = state;
    assign dbg_valid        = {valid_1, valid_0};
    assign dbg_dirty        = {dirty_1, dirty_0};
    assign dbg_tag_match    = {tag_match_1, tag_match_0};
    assign dbg_lru          = lru_bit;
    assign dbg_selected_way = selected_way;
    assign dbg_writeback    = writeback_flag;
    
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
                if (victim_valid && victim_dirty) begin
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
            // Reset cache arrays for both ways
            for (i = 0; i < `SA_NUM_SETS; i = i + 1) begin
                valid_arr_0[i] <= 1'b0;
                dirty_arr_0[i] <= 1'b0;
                tag_arr_0[i]   <= {`SA_TAG_WIDTH{1'b0}};
                data_arr_0[i]  <= {`BLOCK_BITS{1'b0}};
                
                valid_arr_1[i] <= 1'b0;
                dirty_arr_1[i] <= 1'b0;
                tag_arr_1[i]   <= {`SA_TAG_WIDTH{1'b0}};
                data_arr_1[i]  <= {`BLOCK_BITS{1'b0}};
                
                lru_arr[i]     <= 1'b0;
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
            selected_way  <= 1'b0;
            
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
                // COMPARE: Tag comparison (combinational)
                //--------------------------------------------------------------
                `S_COMPARE: begin
                    // Store which way to use
                    if (cache_hit) begin
                        selected_way <= hit_way;
                    end else begin
                        selected_way <= victim_way;
                    end
                end
                
                //--------------------------------------------------------------
                // HIT: Handle cache hit
                //--------------------------------------------------------------
                `S_HIT: begin
                    hit_flag   <= 1'b1;
                    hit_latch  <= 1'b1;   // Latch hit for response phase
                    miss_latch <= 1'b0;   // Clear miss latch
                    hit_count  <= hit_count + 1;
                    
                    // Update LRU: mark the OTHER way as LRU
                    lru_arr[lat_index] <= ~selected_way;
                    
                    if (latched_rw == 1'b0) begin
                        // READ HIT
                        cpu_rdata <= get_word(hit_block, lat_word_offset);
                    end else begin
                        // WRITE HIT
                        if (selected_way == 1'b0) begin
                            data_arr_0[lat_index]  <= set_word(current_block_0, lat_word_offset,
                                                               latched_wdata, latched_wstrb);
                            dirty_arr_0[lat_index] <= 1'b1;
                        end else begin
                            data_arr_1[lat_index]  <= set_word(current_block_1, lat_word_offset,
                                                               latched_wdata, latched_wstrb);
                            dirty_arr_1[lat_index] <= 1'b1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // MISS_CHECK: Determine if writeback needed
                //--------------------------------------------------------------
                `S_MISS_CHECK: begin
                    miss_flag  <= 1'b1;
                    miss_latch <= 1'b1;   // Latch miss for response phase
                    hit_latch  <= 1'b0;   // Clear hit latch
                    miss_count <= miss_count + 1;
                end
                
                //--------------------------------------------------------------
                // WRITEBACK_INIT: Start writeback
                //--------------------------------------------------------------
                `S_WRITEBACK_INIT: begin
                    writeback_flag <= 1'b1;
                    if (mem_ready) begin
                        mem_req   <= 1'b1;
                        mem_rw    <= 1'b1;
                        mem_addr  <= writeback_addr;
                        mem_wdata <= victim_block;
                    end
                end
                
                //--------------------------------------------------------------
                // WRITEBACK: Wait for memory write
                //--------------------------------------------------------------
                `S_WRITEBACK: begin
                    writeback_flag <= 1'b1;
                end
                
                //--------------------------------------------------------------
                // ALLOCATE_INIT: Start block fetch
                //--------------------------------------------------------------
                `S_ALLOCATE_INIT: begin
                    if (mem_ready) begin
                        mem_req  <= 1'b1;
                        mem_rw   <= 1'b0;
                        mem_addr <= {latched_addr[`ADDR_WIDTH-1:5], 5'b00000};
                    end
                end
                
                //--------------------------------------------------------------
                // ALLOCATE: Wait for memory read
                //--------------------------------------------------------------
                `S_ALLOCATE: begin
                    // Wait for mem_resp
                end
                
                //--------------------------------------------------------------
                // UPDATE: Update cache with new block
                //--------------------------------------------------------------
                `S_UPDATE: begin
                    // Update LRU: mark the OTHER way as LRU
                    lru_arr[lat_index] <= ~selected_way;
                    
                    if (selected_way == 1'b0) begin
                        valid_arr_0[lat_index] <= 1'b1;
                        tag_arr_0[lat_index]   <= lat_tag;
                        
                        if (latched_rw == 1'b0) begin
                            data_arr_0[lat_index]  <= mem_rdata;
                            dirty_arr_0[lat_index] <= 1'b0;
                            cpu_rdata              <= get_word(mem_rdata, lat_word_offset);
                        end else begin
                            data_arr_0[lat_index]  <= set_word(mem_rdata, lat_word_offset,
                                                               latched_wdata, latched_wstrb);
                            dirty_arr_0[lat_index] <= 1'b1;
                        end
                    end else begin
                        valid_arr_1[lat_index] <= 1'b1;
                        tag_arr_1[lat_index]   <= lat_tag;
                        
                        if (latched_rw == 1'b0) begin
                            data_arr_1[lat_index]  <= mem_rdata;
                            dirty_arr_1[lat_index] <= 1'b0;
                            cpu_rdata              <= get_word(mem_rdata, lat_word_offset);
                        end else begin
                            data_arr_1[lat_index]  <= set_word(mem_rdata, lat_word_offset,
                                                               latched_wdata, latched_wstrb);
                            dirty_arr_1[lat_index] <= 1'b1;
                        end
                    end
                end
                
                //--------------------------------------------------------------
                // RESP: Send response
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
