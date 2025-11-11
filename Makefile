VCS ?= vcs
VERDI ?= verdi

TOP ?= tb

SRC_DIR ?= ./
FILELIST ?= 

GENERATED_FILELIST := filelist.f
ifeq ($(strip $(FILELIST)),)
	USE_FILELIST := $(GENERATED_FILELIST)
else
	USE_FILELIST := $(FILELIST)
endif

VCS_FLAGS ?= -top $(TOP) \
	+libext+.v +libext+.sv +libext+.vc \
	-full64 -sverilog \
	-f $(USE_FILELIST) \
	-l $(BUILD_DIR)/compile.log \
	-debug_region=cell+encrypt -debug_acc+all \
	-timescale=1ns/1ps \
	-kdb \
	-o $(BUILD_DIR)/simv \
	-Mdirectory=$(BUILD_DIR)/csrc
         
DOFILE ?= dump_fsdb.tcl
BUILD_DIR ?= build

.PHONY: all
all: run

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(GENERATED_FILELIST):
	@echo "Generating $(GENERATED_FILELIST) from $(SRC_DIR) ..."
	@find $(SRC_DIR) -type f \( -name "*.sv" -o -name "*.v" \) | sort > $(GENERATED_FILELIST)
	@echo "Wrote $(GENERATED_FILELIST) with $$(wc -l < $(GENERATED_FILELIST)) entries."

.PHONY: compile
compile: $(if $(filter $(GENERATED_FILELIST),$(USE_FILELIST)),$(GENERATED_FILELIST)) $(BUILD_DIR)
	@echo "=== VCS compiling (top=$(TOP)) ==="
	@if [ ! -s $(USE_FILELIST) ]; then \
		echo "Error: filelist '$(USE_FILELIST)' is empty or not found."; exit 1; \
	fi
	@echo "Using filelist: $(USE_FILELIST)"
	$(VCS) $(VCS_FLAGS)
	@echo "=== VCS compile finished (check compile.log) ==="

.PHONY: verdi
verdi:
	@echo "Starting Verdi (background)..."
	cd $(BUILD_DIR) && $(VERDI) -dbdir simv.daidir &

MACROS = +BIN=$(BIN) +SPDLOG_LEVEL_SV=$(SPDLOG_LEVEL_SV)

VCS_ARGS    ?=
VCS_ARGS   += +firmware=$(firmware)

.PHONY: sim
sim:
	@if [ ! -x $(SIMV) ]; then \
		echo "Error: $(SIMV) not found or not executable. Run 'make compile' first."; exit 1; \
	fi
	@echo "Running simv..."
	cd $(BUILD_DIR) && ./simv -ucli -do ../$(DOFILE) -no_save $(MACROS) $(VCS_ARGS)

.PHONY: run
run: compile sim

.PHONY: clean
clean:
	@echo "Cleaning generated simulation files..."
	@rm -rf $(BUILD_DIR) 
	@echo "Done."

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all (default)   - compile + run"
	@echo "  compile         - run vcs to build simv"
	@echo "  sim             - run ./simv (requires compile done)"
	@echo "  run             - compile then sim"
	@echo "  verdi           - start Verdi GUI (background)"
	@echo "  clean           - remove generated files"
	@echo ""
	@echo "Common variables you can override on the make command line:"
	@echo "  TOP, SRC_DIR, FILELIST, BUILD_DIR"
	@echo "Example:"
	@echo "  make run TOP=nova_tb BIN=/home/host/Projects/nova-riscv/hardware/tb/sram/test.bin fsdb_file=test"

.PHONY: all compile sim run verdi clean help firmware
