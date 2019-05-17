use super::{compile_str, CompileError};
use crate::assembler::{assemble, lex_str};
use crate::Processor;
use std::error::Error;
use std::fmt;
use std::fs;

#[derive(Debug)]
enum CompilerTestError {
    CompilerFailure(CompileError),
    AssemblerOrExecutionFailure(String),
    FsError(std::io::Error),
}

impl From<CompileError> for CompilerTestError {
    fn from(error: CompileError) -> Self {
        CompilerTestError::CompilerFailure(error)
    }
}

impl From<String> for CompilerTestError {
    fn from(error: String) -> Self {
        CompilerTestError::AssemblerOrExecutionFailure(error)
    }
}

impl From<std::io::Error> for CompilerTestError {
    fn from(error: std::io::Error) -> Self {
        CompilerTestError::FsError(error)
    }
}
impl fmt::Display for CompilerTestError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        use CompilerTestError::*;
        match self {
            CompilerFailure(e) => e.fmt(f),
            AssemblerOrExecutionFailure(e) => e.fmt(f),
            FsError(e) => e.fmt(f),
        }
    }
}

impl Error for CompilerTestError {}

type CompilerTestResult = Result<(), CompilerTestError>;

fn compile_expect(name: &str, statick_src: &str, stacks: Vec<Vec<u16>>) -> CompilerTestResult {
    let program = compile_str(statick_src, false)?;
    println!("{}", program);

    let path = format!(
        "/Users/thomas/Oxford/Year 4/Project/programs/auto_{}.txt",
        name
    );
    let mut src_to_write = "".to_string();
    for s in &stacks {
        src_to_write += &format!(
            "# Expect: {}\n",
            s.iter()
                .map(|x| format!("{}", x))
                .collect::<Vec<String>>()
                .join(" ")
        );
    }
    src_to_write += &program;
    fs::write(path, src_to_write)?;

    let is = assemble(lex_str(&program)?)?;
    let mut processor = Processor::default();
    processor.set_instructions(&is)?;
    processor.run(true)?;
    for (i, s) in stacks.iter().enumerate() {
        let stack = processor.final_stack(i);
        assert_eq!(stack, s);
    }
    Ok(())
}

#[test]
fn empty_program() -> CompilerTestResult {
    compile_expect("empty", "main = .", vec![vec![]])
}

#[test]
fn arithmetic() -> CompilerTestResult {
    compile_expect("arithmetic1", "main = 1 2 +", vec![vec![3]])?;
    compile_expect("arithmetic2", "main = 7 1 -", vec![vec![6]])?;
    Ok(())
}

#[test]
fn basic_if() -> CompilerTestResult {
    compile_expect(
        "if1",
        "main = if (true) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if2",
        "main = if (false) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if3",
        "main = if (0 1 ==) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if4",
        "main = if (0 1 !=) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if5",
        "main = if (0 1 <) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if6",
        "main = if (0 1 <=) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if7",
        "main = if (0 1 >) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if8",
        "main = if (0 1 >=) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if9",
        "main = if (true true and) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if10",
        "main = if (true false and) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if11",
        "main = if (false false and) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if12",
        "main = if (false false and) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if13",
        "main = if (true true or) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if14",
        "main = if (true false or) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if15",
        "main = if (false true or) then (13) else (12)",
        vec![vec![13]],
    )?;
    compile_expect(
        "if16",
        "main = if (false false or) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if17",
        "main = if (true not) then (13) else (12)",
        vec![vec![12]],
    )?;
    compile_expect(
        "if18",
        "main = if (false not) then (13) else (12)",
        vec![vec![13]],
    )?;
    Ok(())
}

#[test]
fn basic_while() -> CompilerTestResult {
    compile_expect("while1", "main = while (false) do () 42", vec![vec![42]])?;
    compile_expect(
        "while2",
        "main = 0 while (dup 10 !=) do (1 +)",
        vec![vec![10]],
    )?;
    compile_expect(
        "while3",
        "main = 7 true while (dup true and) do (swap 1 + swap not) drop",
        vec![vec![8]],
    )?;
    Ok(())
}

#[test]
fn calls() -> CompilerTestResult {
    compile_expect("call1", "main = 'other apply other = 10", vec![vec![10]])?;
    compile_expect("call2", "main = other other = 10", vec![vec![10]])?;
    Ok(())
}

// Tests below this point have been directly adapted from type checking tests

#[test]
fn push_bool() -> CompilerTestResult {
    compile_expect("bool1", "main = true", vec![vec![1]])?;
    compile_expect("bool2", "main = false", vec![vec![0]])?;
    Ok(())
}

#[test]
fn push_int() -> CompilerTestResult {
    compile_expect("int1", "main = 1", vec![vec![1]])?;
    Ok(())
}

#[test]
fn anonymous_call() -> CompilerTestResult {
    compile_expect("anonymous_call1", "main = 0 (1+) apply", vec![vec![1]])?;
    Ok(())
}

#[test]
fn if_in_another_fn_type_checks() -> CompilerTestResult {
    compile_expect(
        "if_fn1",
        "main = true fn
        fn = if () then (0) else (1)",
        vec![vec![0]],
    )?;
    Ok(())
}

#[test]
fn really_basic_rec() -> CompilerTestResult {
    compile_expect(
        "rec1",
        "main = 0 rec
        rec = if (@0 0 ==) then () else (1 - rec)",
        vec![vec![0]],
    )?;
    Ok(())
}

#[test]
fn fib() -> CompilerTestResult {
    compile_expect(
        "fib0",
        "main = 0 fib
        fib = if (@0 0 ==) then () else (
                if (@0 1 ==) then () else (
                    @0 1 - fib swap 2 - fib +))",
        vec![vec![0]],
    )?;
    compile_expect(
        "fib1",
        "main = 1 fib
        fib = if (@0 0 ==) then () else (
                if (@0 1 ==) then () else (
                    @0 1 - fib swap 2 - fib +))",
        vec![vec![1]],
    )?;
    compile_expect(
        "fib2",
        "main = 2 fib
        fib = if (@0 0 ==) then () else (
                if (@0 1 ==) then () else (
                    @0 1 - fib swap 2 - fib +))",
        vec![vec![1]],
    )?;
    compile_expect(
        "fib3",
        "main = 3 fib
        fib = if (@0 0 ==) then () else (
                if (@0 1 ==) then () else (
                    @0 1 - fib swap 2 - fib +))",
        vec![vec![2]],
    )?;
    compile_expect(
        "fib4",
        "main = 4 fib
        fib = if (@0 0 ==) then () else (
                if (@0 1 ==) then () else (
                    @0 1 - fib swap 2 - fib +))",
        vec![vec![3]],
    )?;
    Ok(())
}

#[test]
fn empty_process_creation() -> CompilerTestResult {
    compile_expect("empty_proc", "main = () proc", vec![vec![], vec![]])
}

#[test]
fn proc_consumes_a_chan() -> CompilerTestResult {
    compile_expect(
        "proc_consumes_a_channel",
        "main = chan_1 (1 ! drop) proc_1 ? drop del",
        vec![vec![], vec![]],
    )
}

#[test]
fn dup_dup() -> CompilerTestResult {
    compile_expect(
        "dup_dup",
        "main = 0 dupDup
        dupDup = dup dup",
        vec![vec![0, 0, 0]],
    )
}

#[test]
fn dup_drop() -> CompilerTestResult {
    compile_expect(
        "dup_drop",
        "main = 0 dupDrop
        dupDrop = dup drop",
        vec![vec![0]],
    )
}

#[test]
fn send_receive_once_type() -> CompilerTestResult {
    compile_expect(
        "send_reiceve_once",
        "main = myMakeOnce 'sender proc_1 ? swap del
         myMakeOnce = chan_1
         sender = 10 ! drop",
        vec![vec![10], vec![]],
    )
}

#[test]
fn can_drop_used_channel() -> CompilerTestResult {
    compile_expect(
        "can_drop_used_channel",
        "main = chan_1 'sender proc_1 ? drop drop
        sender = 10 ! drop",
        vec![vec![], vec![]],
    )
}

#[test]
fn subscript_channel_ops() -> CompilerTestResult {
    compile_expect(
        "subscript_channel_ops",
        "main = chan_1 'sender proc_1 2 ?_1 + del_1 swap drop
        sender = 10 !_1 1 swap drop",
        vec![vec![12], vec![1]],
    )
}

#[test]
fn quoted_standard_library_function() -> CompilerTestResult {
    compile_expect(
        "quoted_standard_library_function",
        "main = 1 2 '+ apply",
        vec![vec![3]],
    )
}

#[test]
fn comparison_ifs() -> CompilerTestResult {
    compile_expect(
        "comparison_ifs_1",
        "main = 1 2 if (==) then (7) else (13)",
        vec![vec![13]],
    )?;
    compile_expect(
        "comparison_ifs_2",
        "main = 2 2 if (==) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_3",
        "main = 1 2 if (!=) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_4",
        "main = 2 2 if (!=) then (7) else (13)",
        vec![vec![13]],
    )?;
    compile_expect(
        "comparison_ifs_5",
        "main = 1 2 if (<) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_6",
        "main = 1 2 if (>) then (7) else (13)",
        vec![vec![13]],
    )?;
    compile_expect(
        "comparison_ifs_7",
        "main = 1 2 if (<=) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_8",
        "main = 1 2 if (>=) then (7) else (13)",
        vec![vec![13]],
    )?;
    compile_expect(
        "comparison_ifs_9",
        "main = 2 2 if (<=) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_10",
        "main = 2 2 if (>=) then (7) else (13)",
        vec![vec![7]],
    )?;
    compile_expect(
        "comparison_ifs_11",
        "main = 3 2 if (<=) then (7) else (13)",
        vec![vec![13]],
    )?;
    compile_expect(
        "comparison_ifs_12",
        "main = 2 3 if (>=) then (7) else (13)",
        vec![vec![13]],
    )?;
    Ok(())
}

#[test]
fn if_nested() -> CompilerTestResult {
    compile_expect(
        "if_nested",
        "main = 1 if (1 ==) then (10 if (10 ==) then (13) else (14)) else (19)",
        vec![vec![13]],
    )
}

#[test]
fn repeat_nested() -> CompilerTestResult {
    compile_expect(
        "repeat_nested",
        "main = 0 repeat_10 (repeat_10 (tuck 1 + rot))",
        vec![vec![100]],
    )
}

#[test]
fn repeat_once() -> CompilerTestResult {
    compile_expect(
        "repeat_once",
        "main = 2 repeat_1 (swap 1 + swap)",
        vec![vec![3]],
    )
}

#[test]
fn repeat_twice() -> CompilerTestResult {
    compile_expect(
        "repeat_twice",
        "main = 2 repeat_2 (swap 2 + swap)",
        vec![vec![6]],
    )
}

#[test]
fn repeat_many_times() -> CompilerTestResult {
    compile_expect(
        "repeat_many_times",
        "main = 2 repeat_10 (swap 2 + swap)",
        vec![vec![22]],
    )
}

#[test]
fn repeat_duplication() -> CompilerTestResult {
    compile_expect(
        "repeat_duplication",
        "main = repeat_10 (toInt swap)",
        vec![vec![9, 8, 7, 6, 5, 4, 3, 2, 1, 0]],
    )
}

#[test]
fn repeat_with_channels() -> CompilerTestResult {
    compile_expect(
        "repeat_with_channels",
        "main = chan_3 'sender proc_1 repeat_3 (swap ? drop swap) del
        sender = repeat_3 (swap 4 ! swap) drop",
        vec![vec![], vec![]],
    )
}
