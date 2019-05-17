use std::error::Error;
use std::fmt;
use std::fs::File;
use std::io::prelude::*;
use std::path::Path;

use super::codegen::{codegen, CodegenError};
use super::lexer::{lex, LexerError};
use super::parser::{parse, ParserError};
use super::types::{type_check, TypeError};

#[derive(Debug)]
pub enum CompileError {
    FileOpen,
    FileRead,
    Lexer(LexerError),
    Parser(ParserError),
    Type(TypeError),
    Codegen(CodegenError),
}

impl From<LexerError> for CompileError {
    fn from(error: LexerError) -> Self {
        CompileError::Lexer(error)
    }
}

impl From<ParserError> for CompileError {
    fn from(error: ParserError) -> Self {
        CompileError::Parser(error)
    }
}

impl From<TypeError> for CompileError {
    fn from(error: TypeError) -> Self {
        CompileError::Type(error)
    }
}

impl From<CodegenError> for CompileError {
    fn from(error: CodegenError) -> Self {
        CompileError::Codegen(error)
    }
}

impl fmt::Display for CompileError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            CompileError::FileOpen => write!(f, "could not open file"),
            CompileError::FileRead => write!(f, "could not read file"),
            CompileError::Lexer(e) => write!(f, "Lexer: {}", e),
            CompileError::Parser(e) => write!(f, "Parser: {}", e),
            CompileError::Type(e) => write!(f, "Type: {}", e),
            CompileError::Codegen(e) => write!(f, "Codegen: {}", e),
        }
    }
}

impl Error for CompileError {}

pub fn compile<P>(path: P, output_types: bool) -> Result<String, CompileError>
where
    P: AsRef<Path>,
{
    let mut file = match File::open(path) {
        Ok(f) => f,
        Err(_) => return Err(CompileError::FileOpen),
    };
    let mut contents = String::new();
    if file.read_to_string(&mut contents).is_err() {
        return Err(CompileError::FileRead);
    }
    compile_str(&contents, output_types)
}

pub fn compile_str(src: &str, output_types: bool) -> Result<String, CompileError> {
    let tokens = lex(src)?;
    let mut program = parse(&tokens)?;
    type_check(&mut program)?;

    if output_types {
        for decl in &program.declarations {
            println!("{} :: {}", decl.name, decl.term.t_type.as_ref().unwrap());
        }
    }

    // Can't directly return this because the error might need to be converted, an the Result type
    // doesn't do that automatically.
    let res = codegen(program)?;
    Ok(res)
}

#[cfg(test)]
mod test;
