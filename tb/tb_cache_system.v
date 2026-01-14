//==============================================================================
// File: tb_cache_system.v
// Description: Comprehensive Testbench for Cache Memory System
//              Tests both Direct-Mapped and Set-Associative configurations
//              Includes all required test scenarios
//==============================================================================

`timescale 1ns/1ps

`include "cache_pkg.v"

module tb_cache_system;

    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    reg                         clk;
    reg                         rst;
    
    //--------------------------------------------------------------------------
    // CPU Interface
    //--------------------------------------------------------------------------
    reg                         cpu_req;
    reg                         cpu_rw;
    reg  [`ADDR_WIDTH-1:0]      cpu_addr;
    reg  [`DATA_WIDTH-1:0]      cpu_wdata;
    reg  [3:0]                  cpu_wstrb;
    
    wire                        cpu_ready;
    wire                        cpu_resp;
    wire [`DATA_WIDTH-1:0]      cpu_rdata;
    
    //--------------------------------------------------------------------------
    // Debug Signals
    //--------------------------------------------------------------------------
    wire                        dbg_hit;
    wire                        dbg_miss;
    wire [`STATE_WIDTH-1:0]     dbg_state;
    wire                        dbg_writeback;
    wire [1:0]                  dbg_valid;
    wire [1:0]                  dbg_dirty;
    wire [1:0]                  dbg_tag_match;
    wire                        dbg_lru;
    wire                        dbg_selected_way;
    
    //--------------------------------------------------------------------------
    // Test Variables
    //--------------------------------------------------------------------------
    integer                     test_num;
    integer                     errors;
    reg  [`DATA_WIDTH-1:0]      expected_data;
    reg  [`DATA_WIDTH-1:0]      read_data;
    reg                         hit_flag;
    integer                     total_hits;
    integer                     total_misses;
    
    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    cache_top u_dut (
        .clk            (clk),
        .rst            (rst),
        
        .cpu_req        (cpu_req),
        .cpu_rw         (cpu_rw),
        .cpu_addr       (cpu_addr),
        .cpu_wdata      (cpu_wdata),
        .cpu_wstrb      (cpu_wstrb),
        
        .cpu_ready      (cpu_ready),
        .cpu_resp       (cpu_resp),
        .cpu_rdata      (cpu_rdata),
        
        .dbg_hit        (dbg_hit),
        .dbg_miss       (dbg_miss),
        .dbg_state      (dbg_state),
        .dbg_writeback  (dbg_writeback),
        .dbg_valid      (dbg_valid),
        .dbg_dirty      (dbg_dirty),
        .dbg_tag_match  (dbg_tag_match),
        .dbg_lru        (dbg_lru),
        .dbg_selected_way (dbg_selected_way)
    );
    
    //--------------------------------------------------------------------------
    // Clock Generation: 10ns period (100MHz)
    //--------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    //--------------------------------------------------------------------------
    // Task: wait_ready
    // Wait until cache is ready for new request
    //--------------------------------------------------------------------------
    task wait_ready;
        begin
            while (!cpu_ready) @(posedge clk);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Task: do_read
    // Perform a read operation and wait for response
    //--------------------------------------------------------------------------
    task do_read;
        input [`ADDR_WIDTH-1:0] addr;
        output [`DATA_WIDTH-1:0] data;
        output was_hit;
        begin
            wait_ready();
            @(posedge clk);
            
            cpu_req   <= 1'b1;
            cpu_rw    <= 1'b0;
            cpu_addr  <= addr;
            cpu_wdata <= 32'd0;
            cpu_wstrb <= 4'b0000;
            
            @(posedge clk);
            cpu_req <= 1'b0;
            
            // Wait for response
            while (!cpu_resp) @(posedge clk);
            
            data    = cpu_rdata;
            was_hit = dbg_hit;
            
            // Track statistics
            if (dbg_hit) total_hits = total_hits + 1;
            if (dbg_miss) total_misses = total_misses + 1;
            
            $display("[READ]  Addr=0x%08X, Data=0x%08X, Hit=%b, State=%0d, Time=%0t",
                     addr, data, was_hit, dbg_state, $time);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Task: do_write
    // Perform a write operation and wait for response
    //--------------------------------------------------------------------------
    task do_write;
        input [`ADDR_WIDTH-1:0] addr;
        input [`DATA_WIDTH-1:0] data;
        input [3:0] strb;
        output was_hit;
        begin
            wait_ready();
            @(posedge clk);
            
            cpu_req   <= 1'b1;
            cpu_rw    <= 1'b1;
            cpu_addr  <= addr;
            cpu_wdata <= data;
            cpu_wstrb <= strb;
            
            @(posedge clk);
            cpu_req <= 1'b0;
            
            // Wait for response
            while (!cpu_resp) @(posedge clk);
            
            was_hit = dbg_hit;
            
            // Track statistics
            if (dbg_hit) total_hits = total_hits + 1;
            if (dbg_miss) total_misses = total_misses + 1;
            
            $display("[WRITE] Addr=0x%08X, Data=0x%08X, Strb=%b, Hit=%b, Writeback=%b, Time=%0t",
                     addr, data, strb, was_hit, dbg_writeback, $time);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Task: check_read
    // Read and verify against expected value
    //--------------------------------------------------------------------------
    task check_read;
        input [`ADDR_WIDTH-1:0] addr;
        input [`DATA_WIDTH-1:0] expected;
        input expect_hit;
        input [255:0] test_name;
        reg [`DATA_WIDTH-1:0] actual;
        reg was_hit;
        begin
            do_read(addr, actual, was_hit);
            
            if (actual !== expected) begin
                $display("  *** ERROR %s: Data mismatch! Expected=0x%08X, Got=0x%08X",
                         test_name, expected, actual);
                errors = errors + 1;
            end
            
            if (was_hit !== expect_hit) begin
                $display("  *** ERROR %s: Hit mismatch! Expected=%b, Got=%b",
                         test_name, expect_hit, was_hit);
                errors = errors + 1;
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("Cache Memory System - Comprehensive Testbench");
        $display("============================================================");
        `ifdef CACHE_TYPE_DM
        $display("Cache Type: DIRECT-MAPPED");
        $display("  Sets: 32, Block Size: 32 bytes");
        `else
        $display("Cache Type: 2-WAY SET-ASSOCIATIVE");
        $display("  Sets: 16, Ways: 2, Block Size: 32 bytes");
        `endif
        $display("============================================================\n");
        
        // Initialize
        cpu_req   = 0;
        cpu_rw    = 0;
        cpu_addr  = 0;
        cpu_wdata = 0;
        cpu_wstrb = 0;
        errors    = 0;
        test_num  = 0;
        total_hits   = 0;
        total_misses = 0;
        
        // Reset
        rst = 1;
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
        
        $display("--- Reset Complete ---\n");
        
        //======================================================================
        // TEST A: Compulsory Miss then Hit (Same Block)
        //======================================================================
        $display("============================================================");
        $display("TEST A: Compulsory Miss then Hit (Same Block)");
        $display("============================================================");
        
        // First read to address 0x100 - should MISS (compulsory)
        // Block: 0x100-0x11F (32 bytes)
        test_num = 1;
        $display("\nA.1: Read 0x100 - Expect MISS (compulsory)");
        check_read(32'h0000_0100, 32'h0000_0100, 1'b0, "A.1");
        
        // Read same block, different offset - should HIT
        test_num = 2;
        $display("\nA.2: Read 0x104 - Expect HIT (same block)");
        check_read(32'h0000_0104, 32'h0000_0104, 1'b1, "A.2");
        
        test_num = 3;
        $display("\nA.3: Read 0x110 - Expect HIT (same block)");
        check_read(32'h0000_0110, 32'h0000_0110, 1'b1, "A.3");
        
        test_num = 4;
        $display("\nA.4: Read 0x11C - Expect HIT (same block, last word)");
        check_read(32'h0000_011C, 32'h0000_011C, 1'b1, "A.4");
        
        $display("\n--- Test A Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // TEST B: Conflict Miss (Same Index, Different Tag)
        //======================================================================
        $display("============================================================");
        $display("TEST B: Conflict Miss");
        $display("============================================================");
        
        `ifdef CACHE_TYPE_DM
        // Direct-Mapped: addr with same index causes immediate conflict
        // Index = addr[9:5], so addresses 0x400 and 0x100 have same index
        // 0x100: index = (0x100 >> 5) & 0x1F = 8
        // Need address with same index but different tag
        // 0x100 + 0x400 = 0x500 has same index (8)
        
        test_num = 5;
        $display("\nB.1: Read 0x100 - Expect HIT (already in cache)");
        check_read(32'h0000_0100, 32'h0000_0100, 1'b1, "B.1");
        
        test_num = 6;
        $display("\nB.2: Read 0x500 - Expect MISS (conflict, evicts 0x100)");
        check_read(32'h0000_0500, 32'h0000_0500, 1'b0, "B.2");
        
        test_num = 7;
        $display("\nB.3: Read 0x100 - Expect MISS (was evicted)");
        check_read(32'h0000_0100, 32'h0000_0100, 1'b0, "B.3");
        
        `else
        // 2-Way Set-Associative: Need 3 addresses with same index to cause conflict
        // Index = addr[8:5], so need addr % 512 to have same bits [8:5]
        // 0x100: index = (0x100 >> 5) & 0xF = 8
        // 0x300: index = (0x300 >> 5) & 0xF = 8  (different tag, way 1)
        // 0x500: index = (0x500 >> 5) & 0xF = 8  (causes eviction)
        
        test_num = 5;
        $display("\nB.1: Read 0x100 - Expect HIT (already in cache)");
        check_read(32'h0000_0100, 32'h0000_0100, 1'b1, "B.1");
        
        test_num = 6;
        $display("\nB.2: Read 0x300 - Expect MISS (fills way 1)");
        check_read(32'h0000_0300, 32'h0000_0300, 1'b0, "B.2");
        
        test_num = 7;
        $display("\nB.3: Read 0x100 - Expect HIT (still in way 0)");
        check_read(32'h0000_0100, 32'h0000_0100, 1'b1, "B.3");
        
        test_num = 8;
        $display("\nB.4: Read 0x500 - Expect MISS (evicts LRU way)");
        check_read(32'h0000_0500, 32'h0000_0500, 1'b0, "B.4");
        
        test_num = 9;
        $display("\nB.5: Read 0x300 - Expect MISS (was LRU, evicted)");
        check_read(32'h0000_0300, 32'h0000_0300, 1'b0, "B.5");
        `endif
        
        $display("\n--- Test B Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // TEST C: Write Hit (Write-Back)
        //======================================================================
        $display("============================================================");
        $display("TEST C: Write Hit (Write-Back Policy)");
        $display("============================================================");
        
        // First, read to bring block into cache
        test_num = 10;
        $display("\nC.1: Read 0x200 - Bring block into cache");
        check_read(32'h0000_0200, 32'h0000_0200, 1'b0, "C.1");
        
        // Write to same address - should HIT and set dirty
        test_num = 11;
        $display("\nC.2: Write 0xDEADBEEF to 0x200 - Expect HIT");
        do_write(32'h0000_0200, 32'hDEAD_BEEF, 4'b1111, hit_flag);
        if (!hit_flag) begin
            $display("  *** ERROR C.2: Expected HIT on write");
            errors = errors + 1;
        end
        
        // Read back - should return written value
        test_num = 12;
        $display("\nC.3: Read 0x200 - Expect HIT with new value");
        check_read(32'h0000_0200, 32'hDEAD_BEEF, 1'b1, "C.3");
        
        // Test partial write (byte strobe)
        test_num = 13;
        $display("\nC.4: Partial write 0xFF to byte 0 of 0x204");
        do_read(32'h0000_0204, read_data, hit_flag);  // Get current value
        do_write(32'h0000_0204, 32'h0000_00FF, 4'b0001, hit_flag);
        
        test_num = 14;
        $display("\nC.5: Verify partial write at 0x204");
        expected_data = (read_data & 32'hFFFFFF00) | 32'h000000FF;
        check_read(32'h0000_0204, expected_data, 1'b1, "C.5");
        
        $display("\n--- Test C Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // TEST D: Dirty Eviction with Writeback
        //======================================================================
        $display("============================================================");
        $display("TEST D: Dirty Eviction with Writeback");
        $display("============================================================");
        
        // Write to establish dirty block at 0x200 (already dirty from Test C)
        // Force eviction by accessing conflicting address
        
        `ifdef CACHE_TYPE_DM
        // 0x200: index = (0x200 >> 5) & 0x1F = 0x10
        // 0x600: same index, different tag
        
        test_num = 15;
        $display("\nD.1: Read 0x600 - Should trigger writeback of dirty 0x200");
        do_read(32'h0000_0600, read_data, hit_flag);
        // Writeback should have occurred
        
        test_num = 16;
        $display("\nD.2: Read 0x200 - Miss, reload - should have persisted value");
        check_read(32'h0000_0200, 32'hDEAD_BEEF, 1'b0, "D.2");
        
        `else
        // 2-Way: Need to fill both ways and trigger eviction
        // 0x200 is dirty in one way
        // Access another address with same index to fill second way
        // Then access third address to evict
        
        // 0x200: index = (0x200 >> 5) & 0xF = 0
        // 0x400: same index
        // 0x600: same index - will evict LRU (0x200 is dirty)
        
        test_num = 15;
        $display("\nD.1: Read 0x400 - Fill second way");
        do_read(32'h0000_0400, read_data, hit_flag);
        
        test_num = 16;
        $display("\nD.2: Read 0x600 - Evict LRU (dirty writeback expected)");
        do_read(32'h0000_0600, read_data, hit_flag);
        
        test_num = 17;
        $display("\nD.3: Read 0x200 - Miss, reload - should have persisted value");
        check_read(32'h0000_0200, 32'hDEAD_BEEF, 1'b0, "D.3");
        `endif
        
        $display("\n--- Test D Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // TEST E: Write Miss (Write-Allocate)
        //======================================================================
        $display("============================================================");
        $display("TEST E: Write Miss (Write-Allocate Policy)");
        $display("============================================================");
        
        // Write to address not in cache
        test_num = 18;
        $display("\nE.1: Write 0xCAFEBABE to 0x800 - Expect MISS (write-allocate)");
        do_write(32'h0000_0800, 32'hCAFE_BABE, 4'b1111, hit_flag);
        if (hit_flag) begin
            $display("  *** ERROR E.1: Expected MISS on first write");
            errors = errors + 1;
        end
        
        // Read back - should HIT now (was allocated)
        test_num = 19;
        $display("\nE.2: Read 0x800 - Expect HIT with written value");
        check_read(32'h0000_0800, 32'hCAFE_BABE, 1'b1, "E.2");
        
        // Verify other words in block are from memory
        test_num = 20;
        $display("\nE.3: Read 0x804 - Should be original memory value");
        check_read(32'h0000_0804, 32'h0000_0804, 1'b1, "E.3");
        
        $display("\n--- Test E Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // TEST F: LRU Replacement (Set-Associative Only)
        //======================================================================
        `ifndef CACHE_TYPE_DM
        $display("============================================================");
        $display("TEST F: LRU Replacement Correctness");
        $display("============================================================");
        
        // Use a fresh set (index = 1, addresses 0x020, 0x220, 0x420)
        // 0x020: index = (0x020 >> 5) & 0xF = 1
        
        test_num = 21;
        $display("\nF.1: Read 0x020 - Fill way 0");
        do_read(32'h0000_0020, read_data, hit_flag);
        
        test_num = 22;
        $display("\nF.2: Read 0x220 - Fill way 1, LRU=way0");
        do_read(32'h0000_0220, read_data, hit_flag);
        
        test_num = 23;
        $display("\nF.3: Read 0x020 - HIT, LRU=way1");
        check_read(32'h0000_0020, 32'h0000_0020, 1'b1, "F.3");
        
        test_num = 24;
        $display("\nF.4: Read 0x420 - MISS, evicts LRU (way1=0x220)");
        do_read(32'h0000_0420, read_data, hit_flag);
        
        test_num = 25;
        $display("\nF.5: Read 0x020 - Should still be HIT");
        check_read(32'h0000_0020, 32'h0000_0020, 1'b1, "F.5");
        
        test_num = 26;
        $display("\nF.6: Read 0x220 - Should be MISS (was evicted)");
        check_read(32'h0000_0220, 32'h0000_0220, 1'b0, "F.6");
        
        $display("\n--- Test F Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        `endif
        
        //======================================================================
        // TEST G: Sequential Block Access Pattern
        //======================================================================
        $display("============================================================");
        $display("TEST G: Sequential Access Pattern");
        $display("============================================================");
        
        // Access 4 consecutive blocks
        test_num = 27;
        $display("\nG.1-4: Sequential block reads");
        check_read(32'h0000_1000, 32'h0000_1000, 1'b0, "G.1");  // Miss
        check_read(32'h0000_1020, 32'h0000_1020, 1'b0, "G.2");  // Miss (next block)
        check_read(32'h0000_1040, 32'h0000_1040, 1'b0, "G.3");  // Miss
        check_read(32'h0000_1060, 32'h0000_1060, 1'b0, "G.4");  // Miss
        
        // Re-access - should all hit (if fits in cache)
        $display("\nG.5-8: Re-access same blocks");
        check_read(32'h0000_1000, 32'h0000_1000, 1'b1, "G.5");  // Hit
        check_read(32'h0000_1020, 32'h0000_1020, 1'b1, "G.6");  // Hit
        check_read(32'h0000_1040, 32'h0000_1040, 1'b1, "G.7");  // Hit
        check_read(32'h0000_1060, 32'h0000_1060, 1'b1, "G.8");  // Hit
        
        $display("\n--- Test G Complete ---");
        $display("Hits: %0d, Misses: %0d\n", total_hits, total_misses);
        
        //======================================================================
        // Final Report
        //======================================================================
        $display("============================================================");
        $display("FINAL RESULTS");
        $display("============================================================");
        $display("Total Hits:   %0d", total_hits);
        $display("Total Misses: %0d", total_misses);
        if ((total_hits + total_misses) > 0)
            $display("Hit Rate:     %0d%%", (total_hits * 100) / (total_hits + total_misses));
        $display("------------------------------------------------------------");
        
        if (errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d ERRORS DETECTED ***", errors);
        end
        
        $display("============================================================");
        $display("Simulation Complete at time %0t", $time);
        $display("============================================================\n");
        
        #100;
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Timeout Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #500000;
        $display("\n*** TIMEOUT: Simulation exceeded maximum time ***");
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // VCD Waveform Dump
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("cache_system.vcd");
        $dumpvars(0, tb_cache_system);
    end

endmodule
