//==============================================================================
// File: cache_direct_mapped.v
// Description: Direct-Mapped Cache Controller
//              - 4 cache lines, 4 bytes per block
//              - 8-bit address: tag[7:4], index[3:2], offset[1:0]
//              - Write-through policy, No-write-allocate on miss
//              - FSM for handling read miss refill
//==============================================================================

module cache_direct_mapped (
    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst,

    //--------------------------------------------------------------------------
    // CPU-side Interface
    //--------------------------------------------------------------------------
    input  wire        req_valid,      // Request valid
    input  wire        req_rw,         // 0=read, 1=write
    input  wire [7:0]  req_addr,       // Request address
    input  wire [7:0]  req_wdata,      // Write data (byte)
    
    output reg         resp_valid,     // Response valid
    output reg  [7:0]  resp_rdata,     // Response read data
    output reg         hit,            // Hit indicator for current request
    output reg         ready,          // Ready to accept new request
    output reg  [31:0] hit_count,      // Hit counter
    output reg  [31:0] miss_count,     // Miss counter

    //--------------------------------------------------------------------------
    // Memory-side Interface (to main_memory)
    //--------------------------------------------------------------------------
    output reg         mem_we,         // Memory write enable
    output reg  [7:0]  mem_addr,       // Memory address
    output reg  [7:0]  mem_wdata,      // Memory write data
    input  wire [7:0]  mem_rdata       // Memory read data
);

    //--------------------------------------------------------------------------
    // FSM State Encoding
    //--------------------------------------------------------------------------
    localparam [2:0] IDLE       = 3'd0;  // Idle/Lookup state
    localparam [2:0] MISS_RD0   = 3'd1;  // Read byte 0 from memory
    localparam [2:0] MISS_RD1   = 3'd2;  // Read byte 1 from memory
    localparam [2:0] MISS_RD2   = 3'd3;  // Read byte 2 from memory
    localparam [2:0] MISS_RD3   = 3'd4;  // Read byte 3 from memory
    localparam [2:0] RESP       = 3'd5;  // Response state after refill
    localparam [2:0] WRITE_MEM  = 3'd6;  // Write-through to memory

    reg [2:0] state, next_state;

    //--------------------------------------------------------------------------
    // Cache Arrays
    //--------------------------------------------------------------------------
    reg        valid_arr   [0:3];    // Valid bits (1 per line)
    reg [3:0]  tag_arr     [0:3];    // Tag array (4 bits per line)
    reg [31:0] data_arr    [0:3];    // Data array (32 bits = 4 bytes per line)

    //--------------------------------------------------------------------------
    // Address Decomposition
    //--------------------------------------------------------------------------
    wire [3:0] req_tag;
    wire [1:0] req_index;
    wire [1:0] req_offset;

    assign req_tag    = req_addr[7:4];   // Upper 4 bits
    assign req_index  = req_addr[3:2];   // Middle 2 bits (selects 1 of 4 lines)
    assign req_offset = req_addr[1:0];   // Lower 2 bits (selects 1 of 4 bytes)

    //--------------------------------------------------------------------------
    // Latched Request Registers (hold request during multi-cycle operations)
    //--------------------------------------------------------------------------
    reg [7:0]  latched_addr;
    reg [7:0]  latched_wdata;
    reg        latched_rw;

    wire [3:0] latched_tag;
    wire [1:0] latched_index;
    wire [1:0] latched_offset;

    assign latched_tag    = latched_addr[7:4];
    assign latched_index  = latched_addr[3:2];
    assign latched_offset = latched_addr[1:0];

    //--------------------------------------------------------------------------
    // Hit Detection
    //--------------------------------------------------------------------------
    wire cache_hit;
    assign cache_hit = valid_arr[req_index] && (tag_arr[req_index] == req_tag);

    //--------------------------------------------------------------------------
    // Block Base Address (aligned to 4-byte boundary)
    //--------------------------------------------------------------------------
    wire [7:0] block_base_addr;
    assign block_base_addr = {latched_addr[7:2], 2'b00};

    //--------------------------------------------------------------------------
    // Temporary buffer for refill bytes
    //--------------------------------------------------------------------------
    reg [7:0] refill_byte0;
    reg [7:0] refill_byte1;
    reg [7:0] refill_byte2;
    reg [7:0] refill_byte3;

    //--------------------------------------------------------------------------
    // Byte extraction from 32-bit block
    // Block stored as: data_arr = {byte3, byte2, byte1, byte0}
    // offset 0 -> byte0 (bits [7:0])
    // offset 1 -> byte1 (bits [15:8])
    // offset 2 -> byte2 (bits [23:16])
    // offset 3 -> byte3 (bits [31:24])
    //--------------------------------------------------------------------------
    function [7:0] get_byte;
        input [31:0] block;
        input [1:0]  offset;
        begin
            case (offset)
                2'b00: get_byte = block[7:0];
                2'b01: get_byte = block[15:8];
                2'b10: get_byte = block[23:16];
                2'b11: get_byte = block[31:24];
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Set byte within 32-bit block
    //--------------------------------------------------------------------------
    function [31:0] set_byte;
        input [31:0] block;
        input [1:0]  offset;
        input [7:0]  byte_data;
        begin
            set_byte = block;
            case (offset)
                2'b00: set_byte[7:0]   = byte_data;
                2'b01: set_byte[15:8]  = byte_data;
                2'b10: set_byte[23:16] = byte_data;
                2'b11: set_byte[31:24] = byte_data;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // FSM: State Register
    //--------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
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
            IDLE: begin
                if (req_valid) begin
                    if (req_rw == 1'b0) begin
                        // READ request
                        if (cache_hit) begin
                            next_state = IDLE;  // Hit: respond immediately
                        end else begin
                            next_state = MISS_RD0;  // Miss: start refill
                        end
                    end else begin
                        // WRITE request
                        if (cache_hit) begin
                            next_state = WRITE_MEM;  // Hit: write-through
                        end else begin
                            next_state = WRITE_MEM;  // Miss: no-write-allocate, just write to mem
                        end
                    end
                end
            end

            MISS_RD0: begin
                next_state = MISS_RD1;  // Wait for byte 0, request byte 1
            end

            MISS_RD1: begin
                next_state = MISS_RD2;  // Capture byte 0, wait for byte 1
            end

            MISS_RD2: begin
                next_state = MISS_RD3;  // Capture byte 1, wait for byte 2
            end

            MISS_RD3: begin
                next_state = RESP;      // Capture byte 2, wait for byte 3
            end

            RESP: begin
                next_state = IDLE;      // Capture byte 3, complete refill, respond
            end

            WRITE_MEM: begin
                next_state = IDLE;      // Write complete
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // FSM: Output and Datapath Logic
    //--------------------------------------------------------------------------
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset cache state
            for (i = 0; i < 4; i = i + 1) begin
                valid_arr[i] <= 1'b0;
                tag_arr[i]   <= 4'b0;
                data_arr[i]  <= 32'b0;
            end
            
            // Reset outputs
            resp_valid   <= 1'b0;
            resp_rdata   <= 8'b0;
            hit          <= 1'b0;
            ready        <= 1'b1;
            hit_count    <= 32'b0;
            miss_count   <= 32'b0;
            
            // Reset memory interface
            mem_we       <= 1'b0;
            mem_addr     <= 8'b0;
            mem_wdata    <= 8'b0;
            
            // Reset latched values
            latched_addr  <= 8'b0;
            latched_wdata <= 8'b0;
            latched_rw    <= 1'b0;
            
            // Reset refill buffer
            refill_byte0 <= 8'b0;
            refill_byte1 <= 8'b0;
            refill_byte2 <= 8'b0;
            refill_byte3 <= 8'b0;
            
        end else begin
            // Default: clear response valid each cycle
            resp_valid <= 1'b0;
            mem_we     <= 1'b0;
            
            case (state)
                //--------------------------------------------------------------
                // IDLE State: Accept new requests, handle hits immediately
                //--------------------------------------------------------------
                IDLE: begin
                    if (req_valid) begin
                        // Latch request
                        latched_addr  <= req_addr;
                        latched_wdata <= req_wdata;
                        latched_rw    <= req_rw;
                        
                        if (req_rw == 1'b0) begin
                            // READ request
                            if (cache_hit) begin
                                // READ HIT: respond immediately
                                resp_valid <= 1'b1;
                                resp_rdata <= get_byte(data_arr[req_index], req_offset);
                                hit        <= 1'b1;
                                hit_count  <= hit_count + 1;
                                ready      <= 1'b1;
                            end else begin
                                // READ MISS: start refill sequence
                                hit        <= 1'b0;
                                miss_count <= miss_count + 1;
                                ready      <= 1'b0;
                                // Request byte 0
                                mem_addr   <= {req_addr[7:2], 2'b00};
                            end
                        end else begin
                            // WRITE request
                            ready <= 1'b0;
                            if (cache_hit) begin
                                // WRITE HIT: update cache, write-through
                                hit        <= 1'b1;
                                hit_count  <= hit_count + 1;
                                // Update cache data
                                data_arr[req_index] <= set_byte(data_arr[req_index], req_offset, req_wdata);
                            end else begin
                                // WRITE MISS: no-write-allocate
                                hit        <= 1'b0;
                                miss_count <= miss_count + 1;
                            end
                            // Setup memory write (both hit and miss)
                            mem_addr  <= req_addr;
                            mem_wdata <= req_wdata;
                        end
                    end else begin
                        ready <= 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // MISS_RD0: Byte 0 address sent, wait for memory latency
                //--------------------------------------------------------------
                MISS_RD0: begin
                    // Memory address for byte 1
                    mem_addr <= block_base_addr + 8'd1;
                end

                //--------------------------------------------------------------
                // MISS_RD1: Capture byte 0, byte 1 address sent
                //--------------------------------------------------------------
                MISS_RD1: begin
                    refill_byte0 <= mem_rdata;
                    // Memory address for byte 2
                    mem_addr <= block_base_addr + 8'd2;
                end

                //--------------------------------------------------------------
                // MISS_RD2: Capture byte 1, byte 2 address sent
                //--------------------------------------------------------------
                MISS_RD2: begin
                    refill_byte1 <= mem_rdata;
                    // Memory address for byte 3
                    mem_addr <= block_base_addr + 8'd3;
                end

                //--------------------------------------------------------------
                // MISS_RD3: Capture byte 2, byte 3 will be ready next cycle
                //--------------------------------------------------------------
                MISS_RD3: begin
                    refill_byte2 <= mem_rdata;
                end

                //--------------------------------------------------------------
                // RESP: Capture byte 3, complete refill, send response
                //--------------------------------------------------------------
                RESP: begin
                    refill_byte3 <= mem_rdata;
                    
                    // Update cache line with all 4 bytes
                    data_arr[latched_index]  <= {mem_rdata, refill_byte2, refill_byte1, refill_byte0};
                    tag_arr[latched_index]   <= latched_tag;
                    valid_arr[latched_index] <= 1'b1;
                    
                    // Return the requested byte
                    case (latched_offset)
                        2'b00: resp_rdata <= refill_byte0;
                        2'b01: resp_rdata <= refill_byte1;
                        2'b10: resp_rdata <= refill_byte2;
                        2'b11: resp_rdata <= mem_rdata;
                    endcase
                    
                    resp_valid <= 1'b1;
                    hit        <= 1'b0;  // This was a miss
                    ready      <= 1'b1;
                end

                //--------------------------------------------------------------
                // WRITE_MEM: Complete write-through to memory
                //--------------------------------------------------------------
                WRITE_MEM: begin
                    mem_we     <= 1'b1;
                    mem_addr   <= latched_addr;
                    mem_wdata  <= latched_wdata;
                    resp_valid <= 1'b1;
                    resp_rdata <= 8'b0;  // Write doesn't return data
                    ready      <= 1'b1;
                end

                default: begin
                    ready <= 1'b1;
                end
            endcase
        end
    end

endmodule
