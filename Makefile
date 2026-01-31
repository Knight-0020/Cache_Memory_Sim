#===============================================================================
# Makefile for Cache Memory System (Direct-Mapped Only)
# Compatible with Icarus Verilog (iverilog)
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
            $(RTL_DIR)/main_memory.v

TB_FILES = $(TB_DIR)/tb_cache_system.v

PKG_FILE = $(RTL_DIR)/cache_pkg.v

ALL_FILES = $(TB_FILES) $(RTL_FILES)

#===============================================================================
# Main Targets
#===============================================================================

# Default target: compile and run
.PHONY: all
all: sim

# Compile and run simulation
.PHONY: sim
sim: $(SIM_OUT)
	@echo "=============================================="
	@echo "Running Cache Simulation (Direct-Mapped Only)"
	@echo "=============================================="
	$(VVP) $(SIM_OUT)

# Compile only
.PHONY: compile
compile: $(SIM_OUT)

$(SIM_OUT): $(ALL_FILES) $(PKG_FILE)
	$(IVERILOG) $(IVFLAGS) -o $(SIM_OUT) $(ALL_FILES)

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
	@echo "  make sim      - Compile and run"
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
	powershell -Command "$$env:PATH = 'C:\\iverilog\\bin;' + $$env:PATH; iverilog -g2012 -I rtl -o sim tb/tb_cache_system.v rtl/cache_top.v rtl/direct_mapped_cache.v rtl/main_memory.v; vvp sim"
