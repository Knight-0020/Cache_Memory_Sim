//==============================================================================
// File: cache_pkg.v
// Description: Cache Parameters and Common Definitions
//              Single-Level Cache Memory System
//==============================================================================

//------------------------------------------------------------------------------
// Common Cache Parameters
//------------------------------------------------------------------------------
// Address width
`define ADDR_WIDTH      32

// Cache size: 1 KB = 1024 bytes
`define CACHE_SIZE      1024

// Block size: 32 bytes = 256 bits
`define BLOCK_SIZE      32 //bytes
`define BLOCK_BITS      256

// Words per block (assuming 32-bit words)
`define WORDS_PER_BLOCK 8

// Offset bits: log2(32) = 5
`define OFFSET_WIDTH    5

// Data width for CPU interface (32-bit word access)
`define DATA_WIDTH      32

//------------------------------------------------------------------------------
// Direct-Mapped Cache Parameters
//------------------------------------------------------------------------------
// Number of sets: 1024 / 32 = 32 sets
`define DM_NUM_SETS     32

// Index bits: log2(32) = 5
`define DM_INDEX_WIDTH  5

// Tag bits: 32 - 5 - 5 = 22
`define DM_TAG_WIDTH    22

// Address field positions for Direct-Mapped
// Offset: addr[4:0]
// Index:  addr[9:5]
// Tag:    addr[31:10]

//------------------------------------------------------------------------------
// FSM State Encoding
//------------------------------------------------------------------------------
`define STATE_WIDTH     4

`define S_IDLE              4'd0   // Waiting for request
`define S_COMPARE           4'd1   // Tag comparison
`define S_HIT               4'd2   // Cache hit - return data
`define S_MISS_CHECK        4'd3   // Check if victim is dirty
`define S_WRITEBACK_INIT    4'd4   // Initialize writeback
`define S_WRITEBACK         4'd5   // Write dirty block to memory
`define S_ALLOCATE_INIT     4'd6   // Initialize allocation
`define S_ALLOCATE          4'd7   // Fetch block from memory
`define S_UPDATE            4'd8   // Update cache arrays
`define S_RESP              4'd9   // Send response to CPU

// Memory latency in cycles (simulated)
`define MEM_LATENCY     2

//------------------------------------------------------------------------------
// Helper Macros
//------------------------------------------------------------------------------
// Extract offset from address
`define GET_OFFSET(addr)    ((addr) & 5'h1F)

// Extract word offset from full offset (for 32-bit word selection)
`define GET_WORD_OFFSET(addr) (((addr) >> 2) & 3'h7)

// Extract byte offset within word
`define GET_BYTE_OFFSET(addr) ((addr) & 2'h3)
