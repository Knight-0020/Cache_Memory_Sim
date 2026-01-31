# Direct-Mapped Cache Memory Simulation

> A Verilog implementation of a single-level, direct-mapped cache memory system with Write-Back and Write-Allocate policies.

## 🚀 Overview

This project simulates a **1 KB Direct-Mapped Cache** interacting with a main memory. It is designed for educational purposes to demonstrate cache controller logic, Finite State Machines (FSM), and memory hierarchy concepts.

### Key Features

- **Direct-Mapped Architecture**: Simple and efficient mapping.
- **Write-Back Policy**: Memory is only updated when a dirty block is evicted, reducing bus traffic.
- **Write-Allocate Policy**: Write misses fetch the block into cache before writing.
- **FSM Controller**: Robust state machine managing hits, misses, evictions, and memory transactions.
- **Waveform Analysis**: specialized debug signals for easy inspection in GTKWave.

## 📂 Project Structure

```
ADLD_EL/
├── rtl/                    # Verilog Source Code
│   ├── cache_top.v         # Top-level module
│   ├── direct_mapped_cache.v # Cache controller logic
│   ├── main_memory.v       # Simulated main memory
│   └── cache_pkg.v         # Parameters and definitions
├── tb/                     # Testbench
│   └── tb_cache_system.v   # Comprehensive test suite
├── show.md                 # Detailed Design & FSM Documentation
├── run.txt                 # Build & Run Instructions
└── Makefile                # Build automation (Unix/Linux)
```

## ⚡ Quick Start

### Prerequisites

- **Icarus Verilog**: For compilation and simulation.
- **GTKWave**: For viewing simulation waveforms.

### Running the Simulation

**Windows (PowerShell):**

```powershell
powershell -Command "$env:PATH = 'C:\iverilog\bin;' + $env:PATH; iverilog -g2012 -I rtl -o sim tb/tb_cache_system.v rtl/cache_top.v rtl/direct_mapped_cache.v rtl/main_memory.v; vvp sim"
```

**Linux / macOS:**

```bash
make sim
```

## 📖 Documentation

For a deep dive into the internal working of the cache, including **State Diagrams**, **Timing Diagrams**, and **Test Cases**, please read:

👉 **[Design Documentation (show.md)](show.md)**

For detailed setup and run commands on all platforms:

👉 **[Run Instructions (run.txt)](run.txt)**
