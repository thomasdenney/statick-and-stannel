SOURCES=Alu.v CounterSignal.v UartRx.v UartTx.v IceRam.v FetchStack.v FetchInstruction.v Execute.v Io.v Core.v \
	Loader.v ResumeState.v SaveState.v RamDumper.v Processor.v SoC.v \
	Heap.v Copier.v ProcessAllocator.v MessageDelivery.v Scheduler.v Send.v Receive.v Enable.v Disable.v ChannelController.v ProcessorMessageHandler.v \
    MemoryController2x3.v MemoryController17x6.v MemoryControllerExternal6.v

TEST_BENCHES=$(wildcard *_tb.v)
TEST_BENCH_OUTPUT=$(TEST_BENCHES:.v=.vcd)
HEADERS=$(wildcard *.vh)
# 2012 is the most recently supported standard
VERILOG_OPTS=-Wall -g2012
LINT_FLAGS=--lint-only --Wall
TEST_FILE=../programs/hexes/add.hex
# Was using --force because currently NextPNR doesn't properly support combinatorial loops from
# inferred latches as the result of a register not being assigned a value in an @always block.
# My suspicion is that this occurs as the result of dodgy logic in the main always block of the
# core, and that at some point I should sit down and improve that instead.
# https://github.com/YosysHQ/nextpnr/issues/109
NEXT_PNR_OPTS=
# NOTE: This must also be changed in defaults.vh (I haven't worked out how to
# pass it in at build time)
TARGET_FREQ=32

all: SoCBlackIce.bin test

test: $(TEST_BENCH_OUTPUT)

deploy: SoCBlackIce.bin
	cat SoCBlackIce.bin > /dev/cu.usbmodem00000000001A1

BlackIcePll.v:
	icepll -i 100 -o $(TARGET_FREQ) -n BlackIcePll -m -f $@

SoCBlackIce.json: $(SOURCES) $(HEADERS) BlackIcePll.v SoCBlackIce.v
	yosys -p "synth_ice40 -json $@" $(SOURCES) BlackIcePll.v SoCBlackIce.v

SoCBlackIce.asc: SoCBlackIce.pcf SoCBlackIce.json
	nextpnr-ice40 $(NEXT_PNR_OPTS) --freq $(TARGET_FREQ) --hx8k --package tq144:4k --json SoCBlackIce.json --pcf SoCBlackIce.pcf --asc $@

%.bin: %.asc
	icepack $< $@

SoC_tb.out: $(SOURCES) $(HEADERS) SoC_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex) $(wildcard *.vh), $^)
	iverilog $(VERILOG_OPTS) -P SoC_tb.romFile=\"$(TEST_FILE)\" -o $@ $(SOURCES) SoC_tb.v
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Core_tb.out: $(SOURCES) $(HEADERS) Core_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex) $(wildcard *.vh) SoC.v Processor.v, $^)
	iverilog $(VERILOG_OPTS) -P Core_tb.romFile=\"$(TEST_FILE)\" -o $@ $(filter-out $(wildcard *.hex) SoC.v Processor.v, $(SOURCES)) core_tb.v

Processor_tb.out: $(SOURCES) $(HEADERS) Processor_tb.v
	# verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex) $(wildcard *.vh) SoC.v, $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)
	iverilog $(VERILOG_OPTS) -P Processor_tb.romFile=\"$(TEST_FILE)\" -o $@ $(filter-out $(wildcard *.hex) SoC.v, $(SOURCES)) Processor_tb.v

ResumeState_tb.out: $(SOURCES) ResumeState.v $(HEADERS) ResumeState_tb.v resume.hex
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) ResumeState.v
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Copier_tb.out: IceRam.v Copier.v Copier_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

Heap_tb.out: $(HEADERS) IceRam.v Heap.v Heap_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py Heap.v

Send_tb.out: $(HEADERS) IceRam.v Send.v Send_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Receive_tb.out: $(HEADERS) IceRam.v Receive.v Receive_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Enable_tb.out: $(HEADERS) IceRam.v Enable.v Enable_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Disable_tb.out: $(HEADERS) IceRam.v Disable.v Disable_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

MessageDelivery_tb.out: $(HEADERS) IceRam.v MessageDelivery.v MessageDelivery_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Scheduler_tb.out: $(HEADERS) IceRam.v Scheduler.v Scheduler_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

ChannelController_tb.out: $(HEADERS) IceRam.v Send.v Heap.v Receive.v Enable.v Disable.v MemoryControllerExternal6.v ChannelController.v ChannelController_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

ProcessAllocator_tb.out: $(HEADERS) IceRam.v Heap.v Copier.v ProcessAllocator.v ProcessAllocator_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

ProcessorMessageHandler_tb.out: $(HEADERS) IceRam.v Heap.v Copier.v ProcessAllocator.v MessageDelivery.v Scheduler.v Send.v Receive.v Enable.v Disable.v MemoryControllerExternal6.v ChannelController.v ProcessorMessageHandler.v MemoryController17x6.v ProcessorMessageHandler_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)
	../scripts/fsm_lint.py $(@:_tb.out=.v)

Alu_tb.out: Alu.v Alu_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

FetchStack_tb.out: $(HEADERS) fetch_test_data.hex IceRam.v FetchStack.v FetchStack_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

FetchInstruction_tb.out: $(HEADERS) fetch_test_data.hex IceRam.v FetchInstruction.v FetchInstruction_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

Execute_tb.out: $(HEADERS) execute_tb_data.hex IceRam.v Alu.v Execute.v Execute_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

Io_tb.out: $(HEADERS) execute_tb_data.hex IceRam.v Io.v Io_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

Memory_tb.out: $(HEADERS) IceRam.v MemoryController2x4.v Memory_tb.v
	iverilog $(VERILOG_OPTS) -o $@ $^

SaveState_tb.out: $(HEADERS) fetch_test_data.hex IceRam.v SaveState.v SaveState_tb.v
	verilator $(LINT_FLAGS) --top-module $(@:_tb.out=) $(filter-out $(wildcard *_tb.v) $(wildcard *.hex), $^)
	iverilog $(VERILOG_OPTS) -o $@ $(filter-out $(wildcard *.hex), $^)

# The test runner script is used to provide a non-zero exit code if $error
# is called, because I couldn't work out how to do it using iVerilog alone.
%.vcd: %.out
	./$< | ../scripts/test_runner.py

MemoryControllerExternal%.v:
	../scripts/memory_controller_external.py -o $@

MemoryController%.v:
	../scripts/memory_controller.py -o $@

clean:
	rm -rf syn
	rm -f *.bin *.txt *.blif *.out *.vcd *.json *.asc
	rm -f MemoryController*.v
	rm -f MemoryControllerExternal*.v
	rm -f *Pll.v

.PHONY: clean
