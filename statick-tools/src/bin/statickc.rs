extern crate simlib;
extern crate structopt;

use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use structopt::StructOpt;

use simlib::statick::compile;

#[derive(StructOpt, Debug)]
struct Opts {
    #[structopt(short = "v", long = "verbose")]
    /// Produce verbose output
    verbose: bool,

    #[structopt(short = "o", long = "output", parse(from_os_str))]
    /// Path to output the assembly to
    output: PathBuf,

    #[structopt(name = "INPUT", parse(from_os_str))]
    /// Path to the filename to assemble
    input: PathBuf,

    #[structopt(short = "t", long = "types")]
    /// Output definition types in standard out. Note the assembler includes this in its output
    /// too.
    output_types: bool,
}

fn main() {
    let opts = Opts::from_args();

    let assembly = match compile(&opts.input, opts.output_types) {
        Ok(a) => a,
        Err(reason) => panic!("Error generating assembly: {}", reason),
    };

    let mut file = match File::create(&opts.output) {
        Ok(f) => f,
        Err(reason) => panic!("Error creating file {}", reason),
    };
    if let Err(reason) = file.write_all(&assembly.as_bytes()) {
        panic!("Failed to write to {:?} because {}", opts.output, reason)
    }
}
