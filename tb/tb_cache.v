//==============================================================================
// File: tb_cache.v
// Description: Self-checking testbench for Direct-Mapped Cache
//              Tests compulsory misses, conflict misses, write-through,
//              and no-write-allocate behavior
//==============================================================================

`timescale 1ns/1ps

module tb_cache;

    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst;

    //--------------------------------------------------------------------------
    // CPU-side Interface Signals
    //--------------------------------------------------------------------------
    reg         req_valid;
    reg         req_rw;
    reg  [7:0]  req_addr;
    reg  [7:0]  req_wdata;
    
    wire        resp_valid;
    wire [7:0]  resp_rdata;
    wire        hit;
    wire        ready;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    //--------------------------------------------------------------------------
    // Test Counters and Variables
    //--------------------------------------------------------------------------
    integer test_num;
    integer errors;
    reg [7:0] expected_data;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    top u_top (
        .clk        (clk),
        .rst        (rst),
        .req_valid  (req_valid),
        .req_rw     (req_rw),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .resp_valid (resp_valid),
        .resp_rdata (resp_rdata),
        .hit        (hit),
        .ready      (ready),
        .hit_count  (hit_count),
        .miss_count (miss_count)
    );

    //--------------------------------------------------------------------------
    // Clock Generation: 10ns period (100MHz)
    //--------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Task: do_read
    // Performs a read operation and waits for response
    //--------------------------------------------------------------------------
    task do_read;
        input [7:0] addr;
        output [7:0] data;
        output hit_result;
        begin
            // Wait until ready
            @(posedge clk);
            while (!ready) @(posedge clk);
            
            // Issue read request
            req_valid <= 1'b1;
            req_rw    <= 1'b0;  // Read
            req_addr  <= addr;
            req_wdata <= 8'h00;
            
            @(posedge clk);
            req_valid <= 1'b0;
            
            // Wait for response
            while (!resp_valid) @(posedge clk);
            
            data       = resp_rdata;
            hit_result = hit;
            
            $display("[READ]  Addr=0x%02X, Data=0x%02X, Hit=%b, Time=%0t", 
                     addr, data, hit_result, $time);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: do_write
    // Performs a write operation and waits for response
    //--------------------------------------------------------------------------
    task do_write;
        input [7:0] addr;
        input [7:0] data;
        output hit_result;
        begin
            // Wait until ready
            @(posedge clk);
            while (!ready) @(posedge clk);
            
            // Issue write request
            req_valid <= 1'b1;
            req_rw    <= 1'b1;  // Write
            req_addr  <= addr;
            req_wdata <= data;
            
            @(posedge clk);
            req_valid <= 1'b0;
            
            // Wait for response
            while (!resp_valid) @(posedge clk);
            
            hit_result = hit;
            
            $display("[WRITE] Addr=0x%02X, Data=0x%02X, Hit=%b, Time=%0t", 
                     addr, data, hit_result, $time);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: check_result
    // Verifies expected vs actual data
    //--------------------------------------------------------------------------
    task check_result;
        input [7:0] actual;
        input [7:0] expected;
        input expected_hit;
        input actual_hit;
        input [255:0] test_name;
        begin
            if (actual !== expected) begin
                $display("  *** ERROR: %s - Data mismatch! Expected=0x%02X, Got=0x%02X", 
                         test_name, expected, actual);
                errors = errors + 1;
            end
            if (actual_hit !== expected_hit) begin
                $display("  *** ERROR: %s - Hit mismatch! Expected=%b, Got=%b", 
                         test_name, expected_hit, actual_hit);
                errors = errors + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    reg [7:0] read_data;
    reg hit_flag;
    
    initial begin
        // Initialize
        $display("============================================================");
        $display("Direct-Mapped Cache Testbench");
        $display("============================================================");
        
        req_valid = 0;
        req_rw    = 0;
        req_addr  = 0;
        req_wdata = 0;
        errors    = 0;
        test_num  = 0;
        
        // Apply reset
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        $display("\n--- Initial State After Reset ---");
        $display("Hit Count: %0d, Miss Count: %0d\n", hit_count, miss_count);

        //======================================================================
        // TEST A: Compulsory Miss then Hit within same block
        //======================================================================
        $display("============================================================");
        $display("TEST A: Compulsory Miss then Hit (Same Block)");
        $display("============================================================");
        
        // Address 0x12: tag=1, index=0, offset=2
        // First access should be a MISS (compulsory)
        test_num = 1;
        $display("\nA.1: Read 0x12 - Expect MISS (compulsory)");
        do_read(8'h12, read_data, hit_flag);
        check_result(read_data, 8'h12, 1'b0, hit_flag, "A.1 Read 0x12");
        
        // Address 0x13: tag=1, index=0, offset=3 (same block as 0x12)
        // Should be a HIT since block 0x10-0x13 was just loaded
        test_num = 2;
        $display("\nA.2: Read 0x13 - Expect HIT (same block as 0x12)");
        do_read(8'h13, read_data, hit_flag);
        check_result(read_data, 8'h13, 1'b1, hit_flag, "A.2 Read 0x13");
        
        // Also test 0x10 and 0x11 which are in the same block
        test_num = 3;
        $display("\nA.3: Read 0x10 - Expect HIT (same block)");
        do_read(8'h10, read_data, hit_flag);
        check_result(read_data, 8'h10, 1'b1, hit_flag, "A.3 Read 0x10");
        
        test_num = 4;
        $display("\nA.4: Read 0x11 - Expect HIT (same block)");
        do_read(8'h11, read_data, hit_flag);
        check_result(read_data, 8'h11, 1'b1, hit_flag, "A.4 Read 0x11");

        $display("\nAfter Test A - Hit Count: %0d, Miss Count: %0d", hit_count, miss_count);

        //======================================================================
        // TEST B: Conflict Miss (Same Index, Different Tag)
        //======================================================================
        $display("\n============================================================");
        $display("TEST B: Conflict Miss (Same Index, Different Tag)");
        $display("============================================================");
        
        // Address 0x12: index = 0x12[3:2] = 0 (bits 2,3 of 0x12 = 00)
        // Address 0x52: index = 0x52[3:2] = 0 (bits 2,3 of 0x52 = 00)
        // Both map to cache line 0, but have different tags
        
        test_num = 5;
        $display("\nB.1: Read 0x12 again - Expect HIT (still in cache)");
        do_read(8'h12, read_data, hit_flag);
        check_result(read_data, 8'h12, 1'b1, hit_flag, "B.1 Read 0x12");
        
        test_num = 6;
        $display("\nB.2: Read 0x52 - Expect MISS (conflict, evicts 0x12's block)");
        // 0x52: tag=5, index=0, offset=2
        do_read(8'h52, read_data, hit_flag);
        check_result(read_data, 8'h52, 1'b0, hit_flag, "B.2 Read 0x52");
        
        test_num = 7;
        $display("\nB.3: Read 0x12 - Expect MISS (was evicted by 0x52)");
        do_read(8'h12, read_data, hit_flag);
        check_result(read_data, 8'h12, 1'b0, hit_flag, "B.3 Read 0x12");

        $display("\nAfter Test B - Hit Count: %0d, Miss Count: %0d", hit_count, miss_count);

        //======================================================================
        // TEST C: Write-Through Hit
        //======================================================================
        $display("\n============================================================");
        $display("TEST C: Write-Through Hit");
        $display("============================================================");
        
        // First, read address 0x24 to bring it into cache
        // 0x24: tag=2, index=1, offset=0
        test_num = 8;
        $display("\nC.1: Read 0x24 - Expect MISS (bring into cache)");
        do_read(8'h24, read_data, hit_flag);
        check_result(read_data, 8'h24, 1'b0, hit_flag, "C.1 Read 0x24");
        
        // Write new value to 0x24 (should be a HIT)
        test_num = 9;
        $display("\nC.2: Write 0xAA to 0x24 - Expect HIT (write-through)");
        do_write(8'h24, 8'hAA, hit_flag);
        if (hit_flag !== 1'b1) begin
            $display("  *** ERROR: C.2 Write Hit - Expected HIT");
            errors = errors + 1;
        end
        
        // Read back 0x24 - should be HIT and return new value
        test_num = 10;
        $display("\nC.3: Read 0x24 - Expect HIT with value 0xAA");
        do_read(8'h24, read_data, hit_flag);
        check_result(read_data, 8'hAA, 1'b1, hit_flag, "C.3 Read 0x24");
        
        // Force eviction by reading conflicting address, then read back
        // to verify write-through updated main memory
        // 0x64: tag=6, index=1, offset=0 (same index as 0x24)
        test_num = 11;
        $display("\nC.4: Read 0x64 - Evict 0x24's block to verify write-through");
        do_read(8'h64, read_data, hit_flag);
        check_result(read_data, 8'h64, 1'b0, hit_flag, "C.4 Read 0x64");
        
        test_num = 12;
        $display("\nC.5: Read 0x24 - MISS, should return 0xAA from main memory");
        do_read(8'h24, read_data, hit_flag);
        check_result(read_data, 8'hAA, 1'b0, hit_flag, "C.5 Read 0x24");

        $display("\nAfter Test C - Hit Count: %0d, Miss Count: %0d", hit_count, miss_count);

        //======================================================================
        // TEST D: Write Miss with No-Write-Allocate
        //======================================================================
        $display("\n============================================================");
        $display("TEST D: Write Miss (No-Write-Allocate)");
        $display("============================================================");
        
        // Write to address 0x88 which is NOT in cache
        // 0x88: tag=8, index=2, offset=0
        test_num = 13;
        $display("\nD.1: Write 0xBB to 0x88 - Expect MISS (no-write-allocate)");
        do_write(8'h88, 8'hBB, hit_flag);
        if (hit_flag !== 1'b0) begin
            $display("  *** ERROR: D.1 Write Miss - Expected MISS");
            errors = errors + 1;
        end
        
        // Read 0x88 - should be a MISS (cache was NOT allocated on write miss)
        // But should return the written value from main memory
        test_num = 14;
        $display("\nD.2: Read 0x88 - Expect MISS (not allocated), value=0xBB");
        do_read(8'h88, read_data, hit_flag);
        check_result(read_data, 8'hBB, 1'b0, hit_flag, "D.2 Read 0x88");
        
        // Now 0x88 should be in cache, read again for HIT
        test_num = 15;
        $display("\nD.3: Read 0x88 - Expect HIT (now in cache)");
        do_read(8'h88, read_data, hit_flag);
        check_result(read_data, 8'hBB, 1'b1, hit_flag, "D.3 Read 0x88");

        $display("\nAfter Test D - Hit Count: %0d, Miss Count: %0d", hit_count, miss_count);

        //======================================================================
        // TEST E: Additional Edge Cases
        //======================================================================
        $display("\n============================================================");
        $display("TEST E: Additional Edge Cases");
        $display("============================================================");
        
        // Test reading from all 4 cache lines
        // Line 0: already tested
        // Line 1: already tested  
        // Line 2: 0x88 is there
        // Line 3: test with 0x0C
        
        test_num = 16;
        $display("\nE.1: Read 0x0C - Expect MISS (cache line 3)");
        // 0x0C: tag=0, index=3, offset=0
        do_read(8'h0C, read_data, hit_flag);
        check_result(read_data, 8'h0C, 1'b0, hit_flag, "E.1 Read 0x0C");
        
        test_num = 17;
        $display("\nE.2: Read 0x0F - Expect HIT (same block as 0x0C)");
        // 0x0F: tag=0, index=3, offset=3
        do_read(8'h0F, read_data, hit_flag);
        check_result(read_data, 8'h0F, 1'b1, hit_flag, "E.2 Read 0x0F");
        
        // Test boundary addresses
        test_num = 18;
        $display("\nE.3: Read 0x00 - Expect MISS");
        do_read(8'h00, read_data, hit_flag);
        check_result(read_data, 8'h00, 1'b0, hit_flag, "E.3 Read 0x00");
        
        test_num = 19;
        $display("\nE.4: Read 0xFF - Expect MISS");
        do_read(8'hFF, read_data, hit_flag);
        check_result(read_data, 8'hFF, 1'b0, hit_flag, "E.4 Read 0xFF");

        //======================================================================
        // Final Report
        //======================================================================
        $display("\n============================================================");
        $display("FINAL RESULTS");
        $display("============================================================");
        $display("Total Hit Count:  %0d", hit_count);
        $display("Total Miss Count: %0d", miss_count);
        $display("Hit Rate: %0d%%", (hit_count * 100) / (hit_count + miss_count));
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
    // Optional: Timeout watchdog
    //--------------------------------------------------------------------------
    initial begin
        #100000;
        $display("\n*** TIMEOUT: Simulation exceeded maximum time ***");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Optional: Dump waveforms for debugging
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("cache_sim.vcd");
        $dumpvars(0, tb_cache);
    end

endmodule
