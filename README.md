![](banner.png)

**Statick** is a statically-typed stack-based programming language with support for inter-process communication using channels. It uses affine, linear, and dependent types to ensure that channel communication operations are memory safe.

```haskell
main =    -- S → S
  chan_1  -- S → S × chan(1, Rx, α) × chan(1, Tx, α)
  'sender -- S → S × (S' × chan(1, Tx, int) → S')
  proc_1  -- S × α × (S' × α → S'' : NoConsumeableOrUndroppableTypes) → S
  ?       -- S × chan(n+1, Rx, α) → S × chan(n, Rx, α) × α
  swap    -- S × α × β → S × β × α
  del     -- S × chan(0, Rx, α) → S

sender =  -- S × chan(1, Tx, int) → S
  42      -- S → S × int
  !       -- S × chan(n + 1, Tx, α) × α → S × chan(n, Tx, α)
  drop    -- S × α : Droppable → S
```

Statick compiles programs for **Stannel**, a stack-based, concurrent embedded processor I designed. My implementation of the processor supports two simultaneously executing programs on the [BlackIce II][blackice] FPGA. My implementation is a dual-core 16-bit, 2-stage pipelined processor with support for hardware-level scheduling and inter-process communication

This repository contains the code for the project I completed for my [Masters in Computer Science][mcompsci] at the [University of Oxford][ox]. I was supervised for this project by [Alex Rogers][alex].

```
Statick = static typing + stacks
Stannel = stacks + channels
```

[blackice]: https://github.com/mystorm-org/BlackIce-II/wiki
[mcompsci]: https://www.cs.ox.ac.uk
[ox]: https://ox.ac.uk
[alex]: https://www.cs.ox.ac.uk/people/alex.rogers/

## Building & using

*Please note that the following has only been tested under macOS 10.14.*

### Statick

The Statick compiler (and an instruction-level simulator of Stannel) is written in [Rust][rust]. You'll need to [download the latest version][rustup] of the Rust compiler. Afterwards, run `cargo build` in `statick-tools` to fetch dependencies and build the compiler.

[rust]: https://www.rust-lang.org
[rustup]: https://rustup.rs

The Rust project builds:

* `statickc`: The Statick compiler. Run `statickc inputfile -o outputfile` to compile Statick code to Stannel assembly
* `as`: The Stannel Assembler assembles Stannel assembly files into Stannel bytecode files
* `sim`: An instruction-level simulator of the Stannel processor

You can also run `cargo test` to run all the tests associated with the Rust project. I recommend running this *before* running tests for Stannel, as running the Rust tests produce test case programs for the processor.

### Stannel

The Stannel processor (in `stannel`) is written in Verilog. I built and tested it using the open-source YoSys toolchain for a BlackIce II (although the design could be reimplemented on other FPGAs, I've only tested it on the BlackIce), which uses a Lattice iCE FPGA. Install the following to build the processor:

* [YoSys and Project IceStorm][yosys] tools
* [NextPNR][nextpnr]
* [Verilator][verilator]
* [iVerilog][iverilog]
* [Python 3+][python] (for running test scripts)
* [GTKWave][gtkwave] (for viewing test output)

[yosys]: https://github.com/YosysHQ/yosys
[nextpnr]: https://github.com/YosysHQ/nextpnr
[verilator]: https://www.veripool.org/wiki/verilator
[iverilog]: http://iverilog.icarus.com/home
[python]: https://python.org
[gtkwave]: http://gtkwave.sourceforge.net

Once the tools are installed run `make test` in `stannel` to check the simulation executes correctly (this executes test benches with iVerilog). Then run `make deploy` to synthesize and deploy the processor to the `BlackIce II`.

In the `scripts` folder there are scripts for sending programs to the processor and checking their output against the the Rust instruction-level simulator and the Verilog simulation of the processor.
Use `scripts/test_program.py` to run one of the sample (Stannel) programs in the `programs` directory on the processor.

If you've previously run `cargo test` on the Statick tools project, run `../scripts/test_all.sh` to run compiled Statick -> Stannel compiled test cases.

## License & contributing

The contents of this repository is available under the MIT License. Please note that I cannot accept contributions to allow the examiners time to view the original code.