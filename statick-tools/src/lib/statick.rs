mod ast;
mod codegen;
mod compiler;
mod lexer;
mod parser;
mod types;

pub use compiler::compile;
