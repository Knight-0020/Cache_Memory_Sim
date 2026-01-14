#===============================================================================
# Makefile for Direct-Mapped Cache Simulation
# Compatible with Icarus Verilog (iverilog)
#===============================================================================

# Compiler and simulator
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Compiler flags
IVFLAGS = -g2012

# Output files
SIM_OUT = sim
VCD_FILE = cache_sim.vcd

# Source files
RTL_DIR = rtl
TB_DIR = tb

RTL_FILES = $(RTL_DIR)/main_memory.v \
            $(RTL_DIR)/cache_direct_mapped.v \
            $(RTL_DIR)/top.v

TB_FILES = $(TB_DIR)/tb_cache.v

ALL_FILES = $(TB_FILES) $(RTL_FILES)

#===============================================================================
# Targets
#===============================================================================

# Default target: compile and run
.PHONY: all
all: run

# Compile all Verilog files
.PHONY: compile
compile: $(SIM_OUT)

$(SIM_OUT): $(ALL_FILES)
	$(IVERILOG) $(IVFLAGS) -o $(SIM_OUT) $(ALL_FILES)

# Run simulation
.PHONY: run
run: $(SIM_OUT)
	$(VVP) $(SIM_OUT)

# View waveforms with GTKWave
.PHONY: wave
wave: $(VCD_FILE)
	$(GTKWAVE) $(VCD_FILE) &

# Clean generated files
.PHONY: clean
clean:
	rm -f $(SIM_OUT) $(VCD_FILE)

# Help
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all     - Compile and run simulation (default)"
	@echo "  compile - Compile Verilog files only"
	@echo "  run     - Run simulation"
	@echo "  wave    - View waveforms in GTKWave"
	@echo "  clean   - Remove generated files"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Manual commands (without make):"
	@echo "  iverilog -g2012 -o sim tb/tb_cache.v rtl/top.v rtl/cache_direct_mapped.v rtl/main_memory.v"
	@echo "  vvp sim"
	@echo "  gtkwave cache_sim.vcd"
