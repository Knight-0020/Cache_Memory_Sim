# Single-Level Cache Memory System

## EL-1 Academic Project - Cache Memory Design

This project implements a **single-level cache memory system** in Verilog, supporting both Direct-Mapped and 2-Way Set-Associative configurations. The design prioritizes correctness, clarity, and explainability for academic purposes.

---

## Table of Contents

1. [Overview](#overview)
2. [Cache Concept](#cache-concept)
3. [Cache Configurations](#cache-configurations)
4. [Address Decoding](#address-decoding)
5. [Cache Policies](#cache-policies)
6. [FSM Controller](#fsm-controller)
7. [File Structure](#file-structure)
8. [Build and Run](#build-and-run)
9. [Waveform Analysis](#waveform-analysis)
10. [Design Decisions](#design-decisions)

---

## Overview

### Specifications

| Parameter | Value |
|-----------|-------|
| Address Width | 32-bit |
| Cache Size | 1 KB |
| Block Size | 32 bytes (256 bits) |
| Word Size | 32-bit |
| Words per Block | 8 |

### Features

- ✅ Direct-Mapped Cache (32 sets)
- ✅ 2-Way Set-Associative Cache (16 sets × 2 ways)
- ✅ Write-back policy with dirty bits
- ✅ Write-allocate on miss
- ✅ LRU replacement (for 2-way)
- ✅ FSM-based controller
- ✅ Debug signals for waveform analysis

---

## Cache Concept

### What is a Cache?

A **cache** is a small, fast memory placed between the CPU and main memory. It stores recently accessed data to reduce average memory access time.

### Memory Hierarchy

```
CPU ←→ L1 Cache ←→ Main Memory ←→ Disk
      (fast)       (slow)        (slower)
```

### Locality of Reference

Caches exploit two types of locality:

1. **Temporal Locality**: Recently accessed data is likely to be accessed again
2. **Spatial Locality**: Data near recently accessed data is likely to be accessed

---

## Cache Configurations

### Direct-Mapped Cache

Each memory address maps to exactly **one** cache line.

```
┌─────────────────────────────────────────────────────────┐
│                    DIRECT-MAPPED CACHE                   │
├─────────────────────────────────────────────────────────┤
│  Set 0:  [Valid][Dirty][Tag: 22-bit][Data: 256-bit]     │
│  Set 1:  [Valid][Dirty][Tag: 22-bit][Data: 256-bit]     │
│  ...                                                     │
│  Set 31: [Valid][Dirty][Tag: 22-bit][Data: 256-bit]     │
└─────────────────────────────────────────────────────────┘
```

**Advantages:**
- Simple hardware
- Fast lookup

**Disadvantages:**
- Conflict misses (two addresses can't coexist if they map to same set)

### 2-Way Set-Associative Cache

Each memory address can be stored in **one of two** cache lines (ways).

```
┌─────────────────────────────────────────────────────────────────────┐
│                   2-WAY SET-ASSOCIATIVE CACHE                        │
├─────────────────────────────────────────────────────────────────────┤
│        │         WAY 0              │         WAY 1              │LRU│
├────────┼────────────────────────────┼────────────────────────────┼───┤
│ Set 0  │ [V][D][Tag:23][Data:256]   │ [V][D][Tag:23][Data:256]   │ 0 │
│ Set 1  │ [V][D][Tag:23][Data:256]   │ [V][D][Tag:23][Data:256]   │ 1 │
│ ...    │                            │                            │   │
│ Set 15 │ [V][D][Tag:23][Data:256]   │ [V][D][Tag:23][Data:256]   │ 0 │
└────────┴────────────────────────────┴────────────────────────────┴───┘
```

**Advantages:**
- Fewer conflict misses
- Better hit rate

**Disadvantages:**
- More complex hardware
- Needs replacement policy (LRU)

---

## Address Decoding

### 32-bit Address Format

#### Direct-Mapped Cache

```
┌────────────────────────────────────────────────┐
│ 31                10 │ 9           5 │ 4     0 │
├──────────────────────┼───────────────┼─────────┤
│        TAG           │     INDEX     │  OFFSET │
│      (22 bits)       │   (5 bits)    │ (5 bits)│
└──────────────────────┴───────────────┴─────────┘
```

- **Tag (22 bits)**: Identifies which memory block
- **Index (5 bits)**: Selects 1 of 32 cache sets
- **Offset (5 bits)**: Selects byte within 32-byte block

#### 2-Way Set-Associative Cache

```
┌─────────────────────────────────────────────────┐
│ 31                 9 │ 8           5 │ 4      0 │
├──────────────────────┼───────────────┼──────────┤
│         TAG          │     INDEX     │  OFFSET  │
│      (23 bits)       │   (4 bits)    │ (5 bits) │
└──────────────────────┴───────────────┴──────────┘
```

- **Tag (23 bits)**: Identifies which memory block
- **Index (4 bits)**: Selects 1 of 16 cache sets
- **Offset (5 bits)**: Selects byte within 32-byte block

### Example Address Breakdown

Address: `0x0000_0124`

**Direct-Mapped:**
- Tag = `0x0000_0124 >> 10` = `0x000000`
- Index = `(0x124 >> 5) & 0x1F` = `9`
- Offset = `0x124 & 0x1F` = `4`

**Set-Associative:**
- Tag = `0x0000_0124 >> 9` = `0x000000`
- Index = `(0x124 >> 5) & 0xF` = `9`
- Offset = `0x124 & 0x1F` = `4`

---

## Cache Policies

### Read Operation

#### Read Hit
1. CPU sends read request
2. Cache compares tag → **MATCH**
3. Return data from cache immediately

#### Read Miss
1. CPU sends read request
2. Cache compares tag → **NO MATCH**
3. If victim is dirty → **Write back** victim to memory
4. Fetch new block from memory
5. Store in cache, return data to CPU

### Write Operation

#### Write Hit (Write-Back)
1. CPU sends write request
2. Cache compares tag → **MATCH**
3. Update cache with new data
4. Set dirty bit = 1
5. (Memory NOT updated until eviction)

#### Write Miss (Write-Allocate)
1. CPU sends write request
2. Cache compares tag → **NO MATCH**
3. If victim is dirty → Write back victim to memory
4. Fetch block from memory
5. Modify fetched block with write data
6. Store in cache with dirty = 1

### LRU Replacement (2-Way Only)

The **Least Recently Used** (LRU) policy evicts the way that was accessed longest ago.

```
Access way 0 → LRU bit = 1 (way 1 is now LRU)
Access way 1 → LRU bit = 0 (way 0 is now LRU)
On eviction  → Evict way indicated by LRU bit
```

---

## FSM Controller

### State Diagram

```
                    ┌──────────────────────┐
                    │        IDLE          │◄─────────────────────┐
                    │  (Wait for request)  │                      │
                    └──────────┬───────────┘                      │
                               │ cpu_req                          │
                               ▼                                  │
                    ┌──────────────────────┐                      │
                    │       COMPARE        │                      │
                    │  (Tag comparison)    │                      │
                    └──────────┬───────────┘                      │
                               │                                  │
              ┌────────────────┴────────────────┐                 │
              │ cache_hit                       │ cache_miss      │
              ▼                                 ▼                 │
    ┌───────────────┐                ┌───────────────┐            │
    │      HIT      │                │  MISS_CHECK   │            │
    │ (Update LRU)  │                │(Check dirty)  │            │
    └───────┬───────┘                └───────┬───────┘            │
            │                                │                    │
            │                 ┌──────────────┴──────────────┐     │
            │                 │ dirty                       │clean│
            │                 ▼                             ▼     │
            │       ┌───────────────┐             ┌─────────────┐ │
            │       │WRITEBACK_INIT │             │ALLOCATE_INIT│ │
            │       └───────┬───────┘             └──────┬──────┘ │
            │               │                            │        │
            │               ▼                            │        │
            │       ┌───────────────┐                    │        │
            │       │   WRITEBACK   │────────────────────┤        │
            │       └───────────────┘                    │        │
            │                                            ▼        │
            │                                   ┌─────────────┐   │
            │                                   │   ALLOCATE  │   │
            │                                   └──────┬──────┘   │
            │                                          │          │
            │                                          ▼          │
            │                                   ┌─────────────┐   │
            │                                   │    UPDATE   │   │
            │                                   └──────┬──────┘   │
            │                                          │          │
            └──────────────────┬───────────────────────┘          │
                               │                                  │
                               ▼                                  │
                    ┌──────────────────────┐                      │
                    │        RESP          │──────────────────────┘
                    │ (Send response)      │
                    └──────────────────────┘
```

### State Descriptions

| State | Description |
|-------|-------------|
| IDLE | Waiting for CPU request |
| COMPARE | Perform tag comparison |
| HIT | Handle cache hit, update LRU |
| MISS_CHECK | Check if victim block is dirty |
| WRITEBACK_INIT | Start writeback to memory |
| WRITEBACK | Wait for memory write completion |
| ALLOCATE_INIT | Start fetching block from memory |
| ALLOCATE | Wait for memory read completion |
| UPDATE | Update cache arrays with new block |
| RESP | Send response to CPU |

---

## File Structure

```
ADLD_EL/
├── rtl/
│   ├── cache_pkg.v              # Parameters and definitions
│   ├── main_memory.v            # Simulated main memory
│   ├── direct_mapped_cache.v    # Direct-mapped cache
│   ├── set_associative_cache.v  # 2-way set-associative cache
│   └── cache_top.v              # Top-level module
├── tb/
│   └── tb_cache_system.v        # Comprehensive testbench
├── README.md                    # This documentation
├── info.txt                     # Detailed viva preparation
└── Makefile                     # Build automation
```

---

## Build and Run

### Prerequisites

- Icarus Verilog (`iverilog`)
- GTKWave (optional, for waveforms)

### Quick Start

```bash
# Compile and run (2-way set-associative by default)
make sim

# View waveforms
make wave

# Clean generated files
make clean
```

### Manual Commands

```bash
# Compile
iverilog -g2012 -I rtl -o sim tb/tb_cache_system.v rtl/cache_top.v rtl/set_associative_cache.v rtl/direct_mapped_cache.v rtl/main_memory.v

# Run
vvp sim

# View waveforms
gtkwave cache_system.vcd
```

### Switching Cache Types

Edit `rtl/cache_top.v`:

```verilog
// For Direct-Mapped:
`define CACHE_TYPE_DM

// For 2-Way Set-Associative (default):
`define CACHE_TYPE_SA
```

---

## Waveform Analysis

### Key Signals to Observe

| Signal | Description |
|--------|-------------|
| `dbg_state` | FSM current state |
| `dbg_hit` | Cache hit indicator |
| `dbg_miss` | Cache miss indicator |
| `dbg_valid` | Valid bits for set |
| `dbg_dirty` | Dirty bits for set |
| `dbg_tag_match` | Tag comparison result |
| `dbg_lru` | LRU bit for current set |
| `dbg_selected_way` | Which way is being accessed |
| `dbg_writeback` | Writeback in progress |

### Expected Waveform Patterns

1. **Compulsory Miss**: First access shows MISS, subsequent same-block access shows HIT
2. **Conflict Miss**: Different tag to same index causes MISS
3. **Dirty Writeback**: `dbg_writeback` asserts before new block allocation
4. **LRU Update**: `dbg_lru` toggles after each access

---

## Design Decisions

### Why Single-Level Cache?

1. **Simplicity**: Multi-level caches add significant complexity
2. **Educational Value**: Clearer demonstration of cache concepts
3. **Debugging**: Easier to trace and verify behavior
4. **Academic Focus**: Appropriate for EL-1 level understanding

### Why Write-Back?

1. **Efficiency**: Reduces memory traffic
2. **Real-World**: Most modern caches use write-back
3. **Dirty Bits**: Teaches important concept

### Why Write-Allocate?

1. **Locality**: Exploits spatial locality for writes
2. **Consistency**: Common pairing with write-back

### Why LRU for 2-Way?

1. **Simple**: Only 1 bit per set needed
2. **Effective**: Works well for 2-way associativity
3. **Educational**: Easy to understand and verify

---

## Test Coverage

| Test | Description |
|------|-------------|
| A | Compulsory miss then hit (same block) |
| B | Conflict miss (same index, different tag) |
| C | Write hit with write-back |
| D | Dirty eviction with writeback |
| E | Write miss with write-allocate |
| F | LRU replacement correctness (2-way only) |
| G | Sequential block access pattern |

---

## Authors

EL-1 Cache Memory Design Project

---

## License

Academic use only.
