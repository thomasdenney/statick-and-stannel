use super::super::ast::Program;
use super::super::lexer::lex;
use super::super::parser::parse;
use super::super::types::type_check;
use super::*;

use Instruction::*;
use FunctionOp::*;
use Token::*;
use Condition::*;

fn parse_and_check(src: &str) -> Program {
    let tokens = lex(src).unwrap();
    let mut program = parse(&tokens).unwrap();
    type_check(&mut program).unwrap();
    dbg!(&program);
    program
}

fn compile_blocks(src: &str) -> CodegenResult<Vec<Block>> {
    let blocks = codegen_blocks(parse_and_check(src))?;
    println!("{}", CodeGenerator::flatten(&blocks));
    Ok(blocks)
}

#[test]
fn the_empty_program() -> CodegenResult<()> {
    let blocks = compile_blocks("main = .")?;
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].tokens, [I(Function(Return))]);
    Ok(())
}

#[test]
fn push_number() -> CodegenResult<()> {
    let blocks = compile_blocks("main = 1")?;
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].tokens, [ N(1), I(Function(Return))]);
    Ok(())
}

#[test]
fn repeat_compiles_to_an_infinite_loop() -> CodegenResult<()> {
    let blocks = compile_blocks("main = repeat (.)")?;
    assert_eq!(blocks.len(), 1);
    let l = blocks[0].label.clone().unwrap();
    assert_eq!(blocks[0].tokens, [L(l), I(Jump(Always))]);
    Ok(())
}

#[test]
fn if_returns() -> CodegenResult<()> {
    let blocks = compile_blocks("main = if (true) then (2) else (3)")?;
    assert_eq!(blocks.len(), 3);
    assert_eq!(blocks[1].tokens[blocks[1].tokens.len()-1], I(Function(Return)));
    assert_eq!(blocks[2].tokens[blocks[2].tokens.len()-1], I(Function(Return)));
    Ok(())
}
