#===============================================================================
# Makefile for Single-Level Cache Memory System
# Compatible with Icarus Verilog (iverilog)
# Supports both Direct-Mapped and 2-Way Set-Associative configurations
#===============================================================================

# Compiler and simulator
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Compiler flags
IVFLAGS = -g2012 -I rtl -Wall

# Output files
SIM_OUT = sim
VCD_FILE = cache_system.vcd

# Source directories
RTL_DIR = rtl
TB_DIR = tb

# Source files
RTL_FILES = $(RTL_DIR)/cache_top.v \
            $(RTL_DIR)/direct_mapped_cache.v \
            $(RTL_DIR)/set_associative_cache.v \
            $(RTL_DIR)/main_memory.v

TB_FILES = $(TB_DIR)/tb_cache_system.v

PKG_FILE = $(RTL_DIR)/cache_pkg.v

ALL_FILES = $(TB_FILES) $(RTL_FILES)

#===============================================================================
# Main Targets
#===============================================================================

# Default target: compile and run (Set-Associative)
.PHONY: all
all: sim

# Compile and run simulation (Set-Associative cache by default)
.PHONY: sim
sim: $(SIM_OUT)
	@echo "=============================================="
	@echo "Running Cache Simulation (Set-Associative)"
	@echo "=============================================="
	$(VVP) $(SIM_OUT)

# Compile only
.PHONY: compile
compile: $(SIM_OUT)

$(SIM_OUT): $(ALL_FILES) $(PKG_FILE)
	$(IVERILOG) $(IVFLAGS) -o $(SIM_OUT) $(ALL_FILES)

#===============================================================================
# Cache Type Specific Targets
#===============================================================================

# Run with Direct-Mapped cache
.PHONY: sim_dm
sim_dm:
	@echo "=============================================="
	@echo "Running Cache Simulation (Direct-Mapped)"
	@echo "=============================================="
	@echo "Note: Edit rtl/cache_top.v to enable CACHE_TYPE_DM"
	$(IVERILOG) $(IVFLAGS) -DCACHE_TYPE_DM -o sim_dm $(ALL_FILES)
	$(VVP) sim_dm

# Run with Set-Associative cache
.PHONY: sim_sa
sim_sa: sim
	@echo "Running Set-Associative cache..."

#===============================================================================
# Waveform Viewing
#===============================================================================

# View waveforms with GTKWave
.PHONY: wave
wave: $(VCD_FILE)
	$(GTKWAVE) $(VCD_FILE) &

# Ensure VCD file exists
$(VCD_FILE): sim
	@if [ ! -f $(VCD_FILE) ]; then \
		echo "VCD file not found. Running simulation first..."; \
		$(VVP) $(SIM_OUT); \
	fi

#===============================================================================
# Utility Targets
#===============================================================================

# Clean generated files
.PHONY: clean
clean:
	rm -f $(SIM_OUT) sim_dm $(VCD_FILE)
	rm -f *.vcd *.lxt *.lxt2 *.fst
	@echo "Cleaned generated files."

# Show help
.PHONY: help
help:
	@echo "=============================================="
	@echo "Cache Memory System - Makefile Help"
	@echo "=============================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make sim      - Compile and run (Set-Associative, default)"
	@echo "  make sim_dm   - Compile and run (Direct-Mapped)"
	@echo "  make sim_sa   - Compile and run (Set-Associative)"
	@echo "  make compile  - Compile only"
	@echo "  make wave     - View waveforms in GTKWave"
	@echo "  make clean    - Remove generated files"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Manual commands:"
	@echo "  iverilog -g2012 -I rtl -o sim tb/tb_cache_system.v rtl/*.v"
	@echo "  vvp sim"
	@echo "  gtkwave cache_system.vcd"
	@echo ""
	@echo "To switch cache types, edit rtl/cache_top.v:"
	@echo "  \`define CACHE_TYPE_DM   // Direct-Mapped"
	@echo "  \`define CACHE_TYPE_SA   // Set-Associative (default)"

# Check syntax only
.PHONY: check
check:
	$(IVERILOG) $(IVFLAGS) -o /dev/null $(ALL_FILES) && echo "Syntax OK"

# List all source files
.PHONY: list
list:
	@echo "Source files:"
	@echo "  Package: $(PKG_FILE)"
	@echo "  RTL:     $(RTL_FILES)"
	@echo "  TB:      $(TB_FILES)"

#===============================================================================
# Windows-specific target (uses PowerShell commands)
#===============================================================================
.PHONY: sim_win
sim_win:
	@echo Running on Windows...
	powershell -Command "$$env:PATH = 'C:\\iverilog\\bin;' + $$env:PATH; iverilog -g2012 -I rtl -o sim tb/tb_cache_system.v rtl/cache_top.v rtl/set_associative_cache.v rtl/direct_mapped_cache.v rtl/main_memory.v; vvp sim"
