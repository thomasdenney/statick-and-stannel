extern crate simlib;
extern crate structopt;

use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use structopt::StructOpt;

use simlib::parse_and_assemble;

#[derive(StructOpt, Debug)]
struct Opts {
    #[structopt(short = "v", long = "verbose")]
    /// Produce verbose output
    verbose: bool,

    #[structopt(short = "o", long = "output", parse(from_os_str))]
    /// Path to output the binary assembly to
    output: PathBuf,

    #[structopt(name = "INPUT", parse(from_os_str))]
    /// Path to the filename to assemble
    input: PathBuf,
}

fn main() {
    let opts = Opts::from_args();

    let instructions = match parse_and_assemble(&opts.input) {
        Ok(p) => p,
        Err(reason) => panic!("Error assembling program {}", reason),
    };
    let mut file = match File::create(opts.output) {
        Ok(f) => f,
        Err(reason) => panic!("Error creating file {}", reason),
    };
    if let Err(reason) = file.write_all(&instructions) {
        panic!("Failed to write to file {}", reason)
    }
}
