use crate::core::Condition;
use std::fmt;
use std::mem::transmute;
use std::str::FromStr;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum Op {
    Add = 0,
    Sub = 1,
    // Times = 2,
    // Division = 3
    ArithmeticShiftLeft = 4,
    ArithmeticShiftRight = 5,
    LogicalShiftLeft = 6,
    LogicalShiftRight = 7,
    LogicalNot = 8,
    LogicalAnd = 9,
    LogicalOr = 10,
    LogicalXor = 11,
    // The intent is that these will behave like their x86 equivalent, i.e. that they will pop two
    // values from the stack and push nothing (but set the flags in the process)
    Test = 14,
    Compare = 15,
}

impl Op {
    pub fn decode(raw: u8) -> Op {
        unsafe { transmute(raw) }
    }
}

// Work in progress
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum ProcessOp {
    Start = 0,
    End = 1,     // Maybe just end the current process
    Send = 2,    // /Shriek/Bang/put/etc
    Receive = 3, // /Query/get
    // The below are currently based on exactly what occam does
    AlternationStart = 4,
    AlternationWait = 5,
    AlternationEnd = 6,
    EnableChannel = 7,
    DisableChannel = 8,
    // Because the intent is for each stack machine to be pure, these are necessary
    CreateChannel = 9,
    DestroyChannel = 10,
    // i.e. end the process but don't destroy it
    Yield = 11,
}

impl ProcessOp {
    // NOTE: std::num::FromPrimitive is experimental and not included in Rust 1.0, hence the need to
    // implement this manually.
    // TODO: Abstract this out as a macro at some point
    pub fn decode(raw: u8) -> Result<ProcessOp, ()> {
        // NOTE: Must be kept in sync with ProcessOp definition
        if raw <= 11 {
            return Ok(unsafe { transmute(raw) });
        }
        Err(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum FunctionOp {
    Call = 0,
    Return = 1,
}

impl FunctionOp {
    pub fn decode(raw: u8) -> Result<FunctionOp, ()> {
        if raw <= 2 {
            return Ok(unsafe { transmute(raw) });
        }
        Err(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum StackOp {
    Drop = 0,
    Dup = 1,
    Swap = 2,
    Tuck = 3,
    Rot = 4,
}

impl StackOp {
    pub fn decode(raw: u8) -> Result<StackOp, ()> {
        if raw <= 4 {
            return Ok(unsafe { transmute(raw) });
        }
        Err(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Instruction {
    ArithmeticOrLogic(Op),
    // TODO: It is my hope to remove this instruction
    PushSmall(u8),
    // The intent of these two instructions is to allow for pushing 16-bit word sized values in 3
    // bytes whilst wasting minimal instruction bits (The AddSmall instruction is useful in other
    // contexts). Push next upper will take the last 4 bits of the instruction as the highest 4
    // bits of the new value, and the next byte in the instruction stream as the middle 8 bits.
    // TODO: Come up with a smarter way of doing this.
    // NOTE: I have a hypothesis that it would actually be better to have a shift/add instruction
    // and a PushLower instruction
    AddSmall(u8),
    PushNextLower(u8),
    PushNextUpper(u8),
    // My current view is that because the address space and word size are the same, and because
    // they are small, there is no advantage to having relative jumps, although I may change my
    // mind.
    Jump(Condition),
    // TODO: Consider the introduction of JumpCompare(c) and JumpTest(c) which would be equivalent to
    // ALU(Compare), Jump(c) and ALU(Test), Jump(c) respectively. This wouldn't significantly
    // reduce encoding space, and may be more efficient.
    Process(ProcessOp),
    Function(FunctionOp),
    Stack(StackOp),
    // The following are planned to enable simpler access to local variables. I still have
    // sufficient bits in the upper four bits of each instruction to do this. Some of these
    // instructions, however will definitely take multiple cycles to complete (the first two, for
    // example, require two memory operations, unless I redesign the processor to use 3 top of
    // stack registers following discussion with Alex). Note that ReadLocal and WriteLocal can be
    // encoded with other Stack operations.
    // I still haven't ironed out architectural details like reading/writing to arbitrary memory
    // locations. Therefore it may be more useful to have a Local N instruction that adds the stack
    // pointer to N, and then ReadGlobal and WriteGlobal instructions
    ReadLocal,
    WriteLocal,
    ReadLocalOffset(u8),
    WriteLocalOffset(u8),

    // The intention of this is to make it possible to easily encode push values in tests.
    Raw(u8),
}

/*
 * At some point I need to rethink how the binary encoding works. Currently only the ALU, Push, and
 * Process instructions use the 4 LSBs of the instruction byte. This is wasteful.
 */
impl Instruction {
    pub fn encode(self) -> Result<u8, String> {
        match self {
            Instruction::ArithmeticOrLogic(op) => Ok(op as u8),
            Instruction::PushSmall(i) if Instruction::fits_immediate(i) => Ok((1 << 4) | i),
            Instruction::AddSmall(i) if Instruction::fits_immediate(i) => Ok((2 << 4) | i),
            Instruction::PushNextLower(i) if Instruction::fits_immediate(i) => Ok((3 << 4) | i),
            Instruction::PushNextUpper(i) if Instruction::fits_immediate(i) => Ok((4 << 4) | i),
            Instruction::Jump(condition) => Ok(5 << 4 | (condition as u8)),
            Instruction::Process(op) => Ok((6 << 4) | (op as u8)),
            Instruction::Function(op) => Ok((7 << 4) | (op as u8)),
            Instruction::Stack(op) => Ok((8 << 4) | (op as u8)),
            Instruction::ReadLocal => Ok(12 << 4),
            Instruction::WriteLocal => Ok(13 << 4),
            Instruction::ReadLocalOffset(i) if Instruction::fits_immediate(i) => Ok((14 << 4) | i),
            Instruction::WriteLocalOffset(i) if Instruction::fits_immediate(i) => Ok((15 << 4) | i),
            Instruction::Raw(x) => Ok(x),
            _ => Err(format!("{:?} couldn't be encoded to a single byte.", self)),
        }
    }

    pub fn decode(raw: u8) -> Result<Instruction, String> {
        let operation = raw >> 4;
        let operand = raw & 0x0F;
        Ok(match operation {
            0 => Instruction::ArithmeticOrLogic(Op::decode(operand)),
            1 => Instruction::PushSmall(operand),
            2 => Instruction::AddSmall(operand),
            3 => Instruction::PushNextLower(operand),
            4 => Instruction::PushNextUpper(operand),
            5 => Instruction::Jump(Condition::decode(operand)),
            6 => Instruction::Process(match ProcessOp::decode(operand) {
                Ok(op) => op,
                Err(_) => return Err(format!("{:#X?} is not a process operation", operand)),
            }),
            7 => Instruction::Function(match FunctionOp::decode(operand) {
                Ok(op) => op,
                Err(_) => return Err(format!("{:#X?} is not a function operation", operand)),
            }),
            8 => Instruction::Stack(match StackOp::decode(operand) {
                Ok(op) => op,
                Err(_) => return Err(format!("{:#X?} is not a stack operation", operand)),
            }),
            12 => Instruction::ReadLocal,
            13 => Instruction::WriteLocal,
            14 => Instruction::ReadLocalOffset(operand),
            15 => Instruction::WriteLocalOffset(operand),
            _ => return Err(format!("Can't decode byte {:#X?} to an instruction", raw)),
        })
    }

    fn fits_immediate(value: u8) -> bool {
        value & 0x0F == value
    }

    pub fn encode_push(value: u16) -> Vec<Instruction> {
        if value < 16 {
            vec![Instruction::PushSmall(value as u8)]
        } else if value < (1 << 12) {
            vec![
                Instruction::PushNextLower((value >> 8) as u8),
                Instruction::Raw(value as u8),
            ]
        } else {
            vec![
                Instruction::PushNextUpper((value >> 12) as u8),
                Instruction::Raw(((value & 0x0FF0) >> 4) as u8),
                Instruction::AddSmall((value & 0x0F) as u8),
            ]
        }
    }

    pub const fn nop() -> Instruction {
        Instruction::Jump(Condition::Never)
    }
}

impl FromStr for Instruction {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "+" | "add" => Ok(Instruction::ArithmeticOrLogic(Op::Add)),
            "-" | "sub" => Ok(Instruction::ArithmeticOrLogic(Op::Sub)),
            "asl" => Ok(Instruction::ArithmeticOrLogic(Op::ArithmeticShiftLeft)),
            "asr" => Ok(Instruction::ArithmeticOrLogic(Op::ArithmeticShiftRight)),
            "lsl" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalShiftLeft)),
            "lsr" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalShiftRight)),
            "not" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalNot)),
            "or" | "|" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalOr)),
            "and" | "&" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalAnd)),
            "xor" | "^" => Ok(Instruction::ArithmeticOrLogic(Op::LogicalXor)),
            "test" => Ok(Instruction::ArithmeticOrLogic(Op::Test)),
            "cmp" | "compare" => Ok(Instruction::ArithmeticOrLogic(Op::Compare)),
            "call" => Ok(Instruction::Function(FunctionOp::Call)),
            "ret" | "return" => Ok(Instruction::Function(FunctionOp::Return)),
            "drop" => Ok(Instruction::Stack(StackOp::Drop)),
            "tuck" => Ok(Instruction::Stack(StackOp::Tuck)),
            "rot" => Ok(Instruction::Stack(StackOp::Rot)),
            "swap" => Ok(Instruction::Stack(StackOp::Swap)),
            "dup" => Ok(Instruction::Stack(StackOp::Dup)),
            "jeq" | "jz" => Ok(Instruction::Jump(Condition::ZeroEqual)),
            "jneq" | "jnz" => Ok(Instruction::Jump(Condition::NotZeroNotEqual)),
            "jneg" => Ok(Instruction::Jump(Condition::Negative)),
            "jnneg" => Ok(Instruction::Jump(Condition::NonNegative)),
            "ja" => Ok(Instruction::Jump(Condition::UnsignedGreater)),
            "jae" => Ok(Instruction::Jump(Condition::UnsignedGreaterOrEqual)),
            "jbe" => Ok(Instruction::Jump(Condition::UnsignedLessOrEqual)),
            "jb" => Ok(Instruction::Jump(Condition::UnsignedLess)),
            "jg" => Ok(Instruction::Jump(Condition::SignedGreater)),
            "jge" => Ok(Instruction::Jump(Condition::SignedGreaterOrEqual)),
            "jl" => Ok(Instruction::Jump(Condition::SignedLess)),
            "jle" => Ok(Instruction::Jump(Condition::SignedLessOrEqual)),
            "jo" => Ok(Instruction::Jump(Condition::Overflow)),
            "jno" => Ok(Instruction::Jump(Condition::NoOverflow)),
            "nop" => Ok(Instruction::nop()),
            "j" | "jump" => Ok(Instruction::Jump(Condition::Always)),
            "get" => Ok(Instruction::ReadLocal),
            "put" => Ok(Instruction::WriteLocal),
            "start" => Ok(Instruction::Process(ProcessOp::Start)),
            "end" | "." => Ok(Instruction::Process(ProcessOp::End)),
            "chan" => Ok(Instruction::Process(ProcessOp::CreateChannel)),
            "del" => Ok(Instruction::Process(ProcessOp::DestroyChannel)),
            "!" | "shriek" | "send" => Ok(Instruction::Process(ProcessOp::Send)),
            "?" | "query" | "receive" => Ok(Instruction::Process(ProcessOp::Receive)),
            "altstart" => Ok(Instruction::Process(ProcessOp::AlternationStart)),
            "altwait" => Ok(Instruction::Process(ProcessOp::AlternationWait)),
            "altend" => Ok(Instruction::Process(ProcessOp::AlternationEnd)),
            "enable" => Ok(Instruction::Process(ProcessOp::EnableChannel)),
            "disable" => Ok(Instruction::Process(ProcessOp::DisableChannel)),
            "yield" => Ok(Instruction::Process(ProcessOp::Yield)),
            _ => Err(()),
        }
    }
}

impl fmt::Display for Instruction {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Instruction::ArithmeticOrLogic(Op::Add) => write!(f, "+"),
            Instruction::ArithmeticOrLogic(Op::Sub) => write!(f, "-"),
            Instruction::ArithmeticOrLogic(Op::ArithmeticShiftLeft) => write!(f, "asl"),
            Instruction::ArithmeticOrLogic(Op::ArithmeticShiftRight) => write!(f, "asr"),
            Instruction::ArithmeticOrLogic(Op::LogicalShiftLeft) => write!(f, "lsl"),
            Instruction::ArithmeticOrLogic(Op::LogicalShiftRight) => write!(f, "lsr"),
            Instruction::ArithmeticOrLogic(Op::LogicalNot) => write!(f, "not"),
            Instruction::ArithmeticOrLogic(Op::LogicalOr) => write!(f, "or"),
            Instruction::ArithmeticOrLogic(Op::LogicalAnd) => write!(f, "and"),
            Instruction::ArithmeticOrLogic(Op::LogicalXor) => write!(f, "xor"),
            Instruction::ArithmeticOrLogic(Op::Test) => write!(f, "test"),
            Instruction::ArithmeticOrLogic(Op::Compare) => write!(f, "cmp"),
            Instruction::PushSmall(n) => write!(f, "{}", n),
            Instruction::AddSmall(n) => write!(f, "{} +", n),
            Instruction::Function(FunctionOp::Call) => write!(f, "call"),
            Instruction::Function(FunctionOp::Return) => write!(f, "ret"),
            Instruction::Stack(StackOp::Drop) => write!(f, "drop"),
            Instruction::Stack(StackOp::Tuck) => write!(f, "tuck"),
            Instruction::Stack(StackOp::Rot) => write!(f, "rot"),
            Instruction::Stack(StackOp::Swap) => write!(f, "swap"),
            Instruction::Stack(StackOp::Dup) => write!(f, "dup"),
            Instruction::Jump(Condition::ZeroEqual) => write!(f, "jeq"),
            Instruction::Jump(Condition::NotZeroNotEqual) => write!(f, "jneq"),
            Instruction::Jump(Condition::Negative) => write!(f, "jneg"),
            Instruction::Jump(Condition::NonNegative) => write!(f, "jnneg"),
            Instruction::Jump(Condition::UnsignedGreater) => write!(f, "ja"),
            Instruction::Jump(Condition::UnsignedGreaterOrEqual) => write!(f, "jae"),
            Instruction::Jump(Condition::UnsignedLessOrEqual) => write!(f, "jbe"),
            Instruction::Jump(Condition::UnsignedLess) => write!(f, "jb"),
            Instruction::Jump(Condition::SignedGreater) => write!(f, "jg"),
            Instruction::Jump(Condition::SignedGreaterOrEqual) => write!(f, "jge"),
            Instruction::Jump(Condition::SignedLess) => write!(f, "jl"),
            Instruction::Jump(Condition::SignedLessOrEqual) => write!(f, "jle"),
            Instruction::Jump(Condition::Overflow) => write!(f, "jo"),
            Instruction::Jump(Condition::NoOverflow) => write!(f, "jno"),
            Instruction::Jump(Condition::Always) => write!(f, "j"),
            Instruction::ReadLocal => write!(f, "get"),
            Instruction::WriteLocal => write!(f, "put"),
            Instruction::ReadLocalOffset(n) => write!(f, "{} get", *n),
            Instruction::WriteLocalOffset(n) => write!(f, "{} put", *n),
            Instruction::Process(ProcessOp::Start) => write!(f, "start"),
            Instruction::Process(ProcessOp::End) => write!(f, "end"),
            Instruction::Process(ProcessOp::CreateChannel) => write!(f, "chan"),
            Instruction::Process(ProcessOp::DestroyChannel) => write!(f, "del"),
            Instruction::Process(ProcessOp::Send) => write!(f, "!"),
            Instruction::Process(ProcessOp::Receive) => write!(f, "?"),
            Instruction::Process(ProcessOp::AlternationStart) => write!(f, "altstart"),
            Instruction::Process(ProcessOp::AlternationWait) => write!(f, "altwait"),
            Instruction::Process(ProcessOp::AlternationEnd) => write!(f, "altend"),
            Instruction::Process(ProcessOp::EnableChannel) => write!(f, "enable"),
            Instruction::Process(ProcessOp::DisableChannel) => write!(f, "disable"),
            Instruction::Process(ProcessOp::Yield) => write!(f, "yield"),
            _ => Err(fmt::Error::default()),
        }
    }
}
