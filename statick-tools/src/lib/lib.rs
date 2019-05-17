use std::fs::File;
use std::io::{self, BufRead};
use std::path::Path;

pub mod assembler;
pub mod core;
pub mod isa;
pub mod memory;
pub mod process;
pub mod processor;
pub mod statick;

use assembler::{assemble, lex, IOLineIteratorWrapper};
pub use self::core::Condition;
pub use isa::*;
use memory::WordIO;
use process::{CallStack, Process, ValueStack};
pub use processor::Processor;

pub fn parse_and_assemble<P>(path: P) -> Result<Vec<u8>, String>
where
    P: AsRef<Path>,
{
    let file = match File::open(path) {
        Ok(f) => f,
        Err(_) => return Err("Failed to open file".to_string()),
    };
    let lines = io::BufReader::new(file).lines();
    let tokens = lex(IOLineIteratorWrapper { lines })?;
    assemble(tokens)
}

pub fn parse_and_run<P>(path: P, verbose: bool) -> Result<(), String>
where
    P: AsRef<Path>,
{
    let file = match File::open(path) {
        Ok(f) => f,
        Err(_) => return Err("Failed to open file".to_string()),
    };
    let lines = io::BufReader::new(file).lines();
    let tokens = lex(IOLineIteratorWrapper { lines })?;
    let instructions = assemble(tokens)?;
    let mut processor = Processor::new(4, 32);
    processor.set_instructions(&instructions)?;
    processor.run(verbose)?;
    Ok(())
}
