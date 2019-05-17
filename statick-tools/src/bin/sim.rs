extern crate simlib;
extern crate structopt;

use simlib::parse_and_run;
use std::path::PathBuf;
use structopt::StructOpt;

#[derive(StructOpt, Debug)]
struct Opts {
    #[structopt(short = "v", long = "verbose")]
    /// Produce verbose output
    verbose: bool,
    #[structopt(name = "INPUT", parse(from_os_str))]
    /// The input file to run
    input: PathBuf,
}

fn main() {
    let opts = Opts::from_args();
    if let Err(msg) = parse_and_run(&opts.input, opts.verbose) {
        panic!("Running machine failed: {}", msg);
    }
}
