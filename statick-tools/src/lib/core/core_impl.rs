use super::{Condition, ControllerMessage, CoreMessage, ExecutionUnit, Flags};
use crate::isa::{FunctionOp, Instruction, Op, ProcessOp, StackOp};
use crate::memory::WordIO;
use crate::process::{CallStack, Process, ValueStack};
use std::ops::{BitAnd, BitOr, BitXor, Shl, Shr};

#[derive(Default)]
pub struct Core {
    pub flags: Flags,
    pub core_id: u16,
    has_alternation_value: bool,
}

impl<M> ExecutionUnit<M> for Core
where
    M: Process + CallStack + ValueStack + std::fmt::Display,
{
    fn tick(
        &mut self,
        instructions: &WordIO,
        memory: &mut M,
        verbose: bool,
    ) -> Result<CoreMessage, String> {
        let pc = memory.program_counter()?;
        let instruction = Instruction::decode(instructions.read_byte(pc)?)?;
        if verbose {
            println!("{:?} @ {} with stack {}", instruction, pc, memory);
        }
        memory.set_program_counter(pc + 1)?;

        match instruction {
            Instruction::ArithmeticOrLogic(op) => self.alu(op, memory),
            Instruction::PushSmall(x) => self.push_small(u16::from(x), memory),
            Instruction::AddSmall(x) => self.add_small(u16::from(x), memory),
            Instruction::PushNextUpper(x) => {
                self.push_next_upper(u16::from(x), instructions, memory)
            }
            Instruction::PushNextLower(x) => {
                self.push_next_lower(u16::from(x), instructions, memory)
            }
            Instruction::Jump(condition) => self.jump(condition, memory),
            Instruction::Process(p) => self.process(p, memory),
            Instruction::Function(op) => self.function(op, memory),
            Instruction::Stack(op) => self.stack(op, memory),
            Instruction::ReadLocal => {
                let offset = memory.stack_pop()?;
                self.read_local(memory, offset)
            }
            Instruction::WriteLocal => {
                let offset = memory.stack_pop()?;
                let word = memory.stack_pop()?;
                self.write_local(memory, offset, word)
            }
            Instruction::ReadLocalOffset(offset) => self.read_local(memory, offset.into()),
            Instruction::WriteLocalOffset(offset) => {
                let word = memory.stack_pop()?;
                self.write_local(memory, offset.into(), word)
            }
            Instruction::Raw(x) => Err(format!("Byte {:X?} is not an instruction", x)),
        }
    }

    fn message(&mut self, message: ControllerMessage, memory: &mut M) -> Result<(), String>
    where
        M: Process + ValueStack + CallStack,
    {
        match message {
            ControllerMessage::ResumeFromMemory => {
                self.flags = memory.get_flags()?;
            }
            ControllerMessage::SaveToMemory => {
                memory.set_flags(self.flags)?;
            }
            ControllerMessage::Receive(_channel, message) => {
                self.has_alternation_value = true;
                memory.stack_push(message)?;
            }
            ControllerMessage::CreatedChannel(channel) => {
                memory.stack_push(channel)?;
            }
            ControllerMessage::Jump(dest) => {
                memory.set_program_counter(dest)?;
            }
        }
        Ok(())
    }
}

impl Core {
    fn alu<M>(&mut self, op: Op, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        // TODO: Determine if the flags should be set in the event of an unsuccessful push
        macro_rules! set_flags_overflow {
            ($operation:ident) => {
                // Enclosed in braces so that Rust permits multiple statements
                {
                    let b = memory.stack_pop()?;
                    let a = memory.stack_pop()?;
                    // I did some investigation with Compiler Explorer:
                    // https://gcc.godbolt.org/z/N7hkt5 The operation overflowing_* will either
                    // retrieve the carry bit or the overflow bit depending on whether it was an
                    // unsigned or signed operation respectively, hence the casting in this
                    // macro. Secondly, the investigation there also demonstrates that the
                    // operation (result == 0) will just read the zero flag, there is no need for a
                    // comparison or conditional branch.
                    let (_, overflow_flag) = (a as i16).$operation(b as i16);
                    let (result, carry_flag) = (a as u16).$operation(b as u16);
                    // TODO: Maybe use the macro below for setting these
                    self.flags.zero = result == 0;
                    // Annoyingly under maximal optimisation this just results in a right shift by
                    // 15, rather than directly reading from the Intel processor's own sign flag
                    self.flags.sign = (result & (1 << 15)) != 0;
                    self.flags.carry = carry_flag;
                    self.flags.overflow = overflow_flag;
                    result
                }
            };
        }
        macro_rules! set_flags_overflow_push {
            ($op: ident) => {{
                let result = set_flags_overflow!($op);
                memory.stack_push(result)?;
            }};
        }
        macro_rules! set_zero_and_sign_flags {
            ($result: expr) => {{
                let result = $result as u16;
                self.flags.zero = result == 0;
                self.flags.sign = (result & (1 << 15)) != 0;
                result
            }};
        }
        macro_rules! do_op {
            ($op: ident) => {{
                let b = memory.stack_pop()?;
                let a = memory.stack_pop()?;
                set_zero_and_sign_flags!(a.$op(b))
            }};
        }
        macro_rules! do_op_push {
            ($op: ident) => {{
                let result = do_op!($op);
                memory.stack_push(result)?;
            }};
        }
        // NOTE: Other operations may affect the flags...
        self.flags = Flags::default();
        match op {
            Op::Add => set_flags_overflow_push!(overflowing_add),
            Op::Sub => set_flags_overflow_push!(overflowing_sub),
            Op::ArithmeticShiftLeft => {
                // Rust generates arithmetic shifts for signed integers and logical shifts for
                // unsigned integers, hence the need for casting here.
                let b = memory.stack_pop()? as i16;
                let a = memory.stack_pop()? as i16;
                let result = set_zero_and_sign_flags!(a << b);
                memory.stack_push(result)?;
            }
            Op::ArithmeticShiftRight => {
                let b = memory.stack_pop()? as i16;
                let a = memory.stack_pop()? as i16;
                let result = set_zero_and_sign_flags!(a >> b);
                memory.stack_push(result)?;
            }
            Op::LogicalShiftLeft => do_op_push!(shl),
            Op::LogicalShiftRight => do_op_push!(shr),
            Op::LogicalNot => {
                let a = memory.stack_pop()?;
                let result = set_zero_and_sign_flags!(!a);
                memory.stack_push(result)?;
            }
            Op::LogicalAnd => {
                do_op_push!(bitand);
            }
            Op::LogicalOr => {
                do_op_push!(bitor);
            }
            Op::LogicalXor => {
                do_op_push!(bitxor);
            }
            Op::Test => {
                do_op!(bitand);
            }
            Op::Compare => {
                set_flags_overflow!(overflowing_sub);
            }
        };
        Ok(CoreMessage::Nothing)
    }

    fn push_small<M>(&mut self, x: u16, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        memory.stack_push(x)?;
        Ok(CoreMessage::Nothing)
    }

    fn add_small<M>(&mut self, x: u16, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        // NOTE: Duplicating code here to save time; must test separately
        // Can't just simulate push/pop because this operation must still work if the
        // stack is full.
        let a = memory.stack_pop()?;
        let b = x as u16;
        let (result, _) = (a as u16).overflowing_add(b as u16);
        memory.stack_push(result)?;
        Ok(CoreMessage::Nothing)
    }

    fn push_next_upper<M>(
        &mut self,
        upper: u16,
        instructions: &WordIO,
        memory: &mut M,
    ) -> Result<CoreMessage, String>
    where
        M: Process + ValueStack,
    {
        // TODO: Verify that next instruction can actually be read --- would produce a
        // memory error in a real system
        let pc = memory.program_counter()?;
        let mid = instructions.read_byte(pc)?;
        memory.set_program_counter(pc + 1)?;
        let result = (upper << 12) | (u16::from(mid) << 4);
        memory.stack_push(result)?;
        Ok(CoreMessage::Nothing)
    }

    fn push_next_lower<M>(
        &mut self,
        upper: u16,
        instructions: &WordIO,
        memory: &mut M,
    ) -> Result<CoreMessage, String>
    where
        M: Process + ValueStack,
    {
        let pc = memory.program_counter()?;
        let lower = instructions.read_byte(pc)?;
        memory.set_program_counter(pc + 1)?;
        let result = (upper << 8) | u16::from(lower);
        memory.stack_push(result)?;
        Ok(CoreMessage::Nothing)
    }

    fn jump<M>(&mut self, condition: Condition, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: Process + ValueStack,
    {
        let new_pc = if condition != Condition::Never {
            memory.stack_pop()?
        } else {
            0
        };
        if self.flags.matches_condition(condition) {
            memory.set_program_counter(new_pc)?;
        }
        Ok(CoreMessage::Nothing)
    }

    fn process<M>(&mut self, op: ProcessOp, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        match op {
            ProcessOp::Start => {
                let number_of_words = memory.stack_pop()?;
                let start_address = memory.stack_pop()?;
                Ok(CoreMessage::StartProcess(start_address, number_of_words))
            }
            ProcessOp::End => Ok(CoreMessage::Halt),
            ProcessOp::Send => {
                let message = memory.stack_pop()?;
                let channel = memory.stack_peek(0)?;
                Ok(CoreMessage::Send(channel, message))
            }
            ProcessOp::CreateChannel => Ok(CoreMessage::CreateChannel),
            ProcessOp::DestroyChannel => {
                let channel = memory.stack_pop()?;
                Ok(CoreMessage::DeleteChannel(channel))
            }
            ProcessOp::Receive => {
                let channel = memory.stack_peek(0)?;
                Ok(CoreMessage::Receive(channel))
            }
            ProcessOp::Yield => Ok(CoreMessage::Yield),
            ProcessOp::AlternationStart => {
                self.has_alternation_value = false;
                Ok(CoreMessage::AlternationStart)
            }
            ProcessOp::AlternationWait => Ok(CoreMessage::AlternationWait),
            ProcessOp::AlternationEnd => Ok(CoreMessage::AlternationEnd),
            ProcessOp::EnableChannel => {
                let channel = memory.stack_pop()?;
                Ok(CoreMessage::EnableChannel(channel))
            }
            ProcessOp::DisableChannel => {
                let dest = memory.stack_pop()?;
                let channel = memory.stack_pop()?;
                Ok(CoreMessage::DisableChannel(
                    channel,
                    dest,
                    self.has_alternation_value,
                ))
            }
        }
    }

    fn function<M>(&mut self, op: FunctionOp, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: Process + CallStack + ValueStack,
    {
        match op {
            FunctionOp::Call => {
                let address = memory.stack_pop()?;
                memory.call_stack_push(memory.program_counter()?)?;
                memory.set_program_counter(address)?;
                Ok(CoreMessage::Nothing)
            }
            FunctionOp::Return => {
                if memory.call_stack_pointer()? == 8 {
                    Ok(CoreMessage::Halt)
                } else {
                    let address = memory.call_stack_pop()?;
                    memory.set_program_counter(address)?;
                    Ok(CoreMessage::Nothing)
                }
            }
        }
    }

    fn stack<M>(&mut self, op: StackOp, memory: &mut M) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        match op {
            StackOp::Drop => {
                memory.stack_pop()?;
            }
            StackOp::Dup => {
                let x = memory.stack_pop()?;
                memory.stack_push(x)?;
                memory.stack_push(x)?;
            }
            StackOp::Swap => {
                let a = memory.stack_pop()?;
                let b = memory.stack_pop()?;
                memory.stack_push(a)?;
                memory.stack_push(b)?;
            }
            StackOp::Tuck => {
                let a = memory.stack_pop()?;
                let b = memory.stack_pop()?;
                let c = memory.stack_pop()?;
                memory.stack_push(b)?;
                memory.stack_push(a)?;
                memory.stack_push(c)?;
            }
            StackOp::Rot => {
                let a = memory.stack_pop()?;
                let b = memory.stack_pop()?;
                let c = memory.stack_pop()?;
                memory.stack_push(a)?;
                memory.stack_push(c)?;
                memory.stack_push(b)?;
            }
        }
        Ok(CoreMessage::Nothing)
    }

    fn read_local<M>(&mut self, memory: &mut M, offset: u16) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        let value = memory.stack_peek(offset)?;
        memory.stack_push(value)?;
        Ok(CoreMessage::Nothing)
    }

    fn write_local<M>(
        &mut self,
        memory: &mut M,
        offset: u16,
        value: u16,
    ) -> Result<CoreMessage, String>
    where
        M: ValueStack,
    {
        let sp = memory.stack_pointer()?;
        memory.write_word(sp + offset * 2, value)?;
        Ok(CoreMessage::Nothing)
    }

    #[cfg(test)]
    pub fn run<M>(
        &mut self,
        instructions: &WordIO,
        memory: &mut M,
        verbose: bool,
    ) -> Result<(), String>
    where
        M: Process + ValueStack + CallStack + std::fmt::Display,
    {
        let mut status = self.tick(instructions, memory, verbose);
        while status.is_ok() && status != Ok(CoreMessage::Halt) {
            status = self.tick(instructions, memory, verbose);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::assembler::{assemble, lex_str};
    use crate::memory::MemoryCell;
    use crate::*;

    use super::*;

    #[test]
    fn push_small() -> Result<(), String> {
        let is = compile![
            Instruction::PushSmall(7),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();

        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing);
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Halt);
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 7);

        Ok(())
    }

    #[test]
    fn push_medium_1() -> Result<(), String> {
        let mut is = Vec::new();
        push!(is, 17);
        halt!(is);
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 17);
        Ok(())
    }

    #[test]
    fn push_medium_2() -> Result<(), String> {
        let mut is = Vec::new();
        push!(is, 1 << 9);
        halt!(is);
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 1 << 9);
        Ok(())
    }

    #[test]
    fn push_large() -> Result<(), String> {
        let mut is = Vec::new();
        push!(is, 1 << 13);
        halt!(is);
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 1 << 13);
        Ok(())
    }

    macro_rules! compare_test {
        ($name: ident, $a: expr, $b: expr, $rel: expr) => {
            #[test]
            fn $name() -> Result<(), String> {
                let mut is = Vec::new();
                push!(is, $a);
                push!(is, $b);
                compile_vec!(is, Instruction::ArithmeticOrLogic(Op::Compare));
                halt!(is);
                let mut memory = MemoryCell::new(0);
                let mut core = Core::default();
                core.run(&is, &mut memory, true)?;

                assert!(core.flags.matches_condition($rel));
                Ok(())
            }
        };
    }

    compare_test!(eq, 77, 77, Condition::ZeroEqual);
    compare_test!(neq, 77, 76, Condition::NotZeroNotEqual);
    compare_test!(neg, 10, 20, Condition::Negative);
    compare_test!(non_neg, 20, 10, Condition::NonNegative);

    compare_test!(unsigned_greater, 20, 10, Condition::UnsignedGreater);
    compare_test!(
        unsigned_greater_equal_1,
        20,
        10,
        Condition::UnsignedGreaterOrEqual
    );
    compare_test!(
        unsigned_greater_equal_2,
        20,
        20,
        Condition::UnsignedGreaterOrEqual
    );
    compare_test!(unsigned_less, 10, 20, Condition::UnsignedLess);
    compare_test!(
        unsigned_less_equal_1,
        10,
        20,
        Condition::UnsignedLessOrEqual
    );
    compare_test!(
        unsigned_less_equal_2,
        20,
        20,
        Condition::UnsignedLessOrEqual
    );

    macro_rules! n16 {
        ($e: expr) => {
            ($e as i16) as u16
        };
    }

    compare_test!(
        signed_greater_1,
        n16!(10),
        n16!(-10),
        Condition::SignedGreater
    );
    compare_test!(
        signed_greater_2,
        n16!(-10),
        n16!(-12),
        Condition::SignedGreater
    );
    compare_test!(
        signed_greater_3,
        n16!(12),
        n16!(10),
        Condition::SignedGreater
    );

    compare_test!(
        signed_greater_equal_1,
        n16!(10),
        n16!(-10),
        Condition::SignedGreaterOrEqual
    );
    compare_test!(
        signed_greater_equal_2,
        n16!(-10),
        n16!(-12),
        Condition::SignedGreaterOrEqual
    );
    compare_test!(
        signed_greater_equal_3,
        n16!(12),
        n16!(10),
        Condition::SignedGreaterOrEqual
    );
    compare_test!(
        signed_greater_equal_4,
        n16!(10),
        n16!(10),
        Condition::SignedGreaterOrEqual
    );
    compare_test!(
        signed_greater_equal_5,
        n16!(-10),
        n16!(-10),
        Condition::SignedGreaterOrEqual
    );

    compare_test!(signed_less_1, n16!(-10), n16!(10), Condition::SignedLess);
    compare_test!(signed_less_2, n16!(10), n16!(12), Condition::SignedLess);
    compare_test!(signed_less_3, n16!(-12), n16!(-10), Condition::SignedLess);

    compare_test!(
        signed_less_equal_1,
        n16!(-10),
        n16!(10),
        Condition::SignedLessOrEqual
    );
    compare_test!(
        signed_less_equal_2,
        n16!(10),
        n16!(12),
        Condition::SignedLessOrEqual
    );
    compare_test!(
        signed_less_equal_3,
        n16!(-12),
        n16!(-10),
        Condition::SignedLessOrEqual
    );
    compare_test!(
        signed_less_equal_4,
        n16!(-10),
        n16!(-10),
        Condition::SignedLessOrEqual
    );
    compare_test!(
        signed_less_equal_5,
        n16!(10),
        n16!(10),
        Condition::SignedLessOrEqual
    );

    // TODO: Tests of overflow flags

    compare_test!(always_1, 0, 0, Condition::Always);
    compare_test!(always_2, 0, 1, Condition::Always);
    compare_test!(always_3, 1, 0, Condition::Always);

    #[test]
    fn swap() -> Result<(), String> {
        let a = 7;
        let b = 12;
        let is = compile![
            Instruction::PushSmall(a),
            Instruction::PushSmall(b),
            Instruction::Stack(StackOp::Swap),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 2);
        assert_eq!(memory.stack_peek(0)?, a.into());
        assert_eq!(memory.stack_peek(1)?, b.into());
        Ok(())
    }

    #[test]
    fn rot() -> Result<(), String> {
        let a = 7;
        let b = 3;
        let c = 12;
        let is = compile![
            Instruction::PushSmall(c),
            Instruction::PushSmall(b),
            Instruction::PushSmall(a),
            Instruction::Stack(StackOp::Rot),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 3);
        assert_eq!(memory.stack_peek(0)?, b.into());
        assert_eq!(memory.stack_peek(1)?, c.into());
        assert_eq!(memory.stack_peek(2)?, a.into());
        Ok(())
    }

    #[test]
    fn tuck() -> Result<(), String> {
        let a = 7;
        let b = 3;
        let c = 12;
        let is = compile![
            Instruction::PushSmall(c),
            Instruction::PushSmall(b),
            Instruction::PushSmall(a),
            Instruction::Stack(StackOp::Tuck),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 3);
        assert_eq!(memory.stack_peek(0)?, c.into());
        assert_eq!(memory.stack_peek(1)?, a.into());
        assert_eq!(memory.stack_peek(2)?, b.into());
        Ok(())
    }

    #[test]
    fn create_and_destroy_channel() -> Result<(), String> {
        let is = compile![
            Instruction::Process(ProcessOp::CreateChannel),
            Instruction::PushSmall(7),
            Instruction::Process(ProcessOp::Send),
            Instruction::Process(ProcessOp::DestroyChannel),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();

        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::CreateChannel
        );
        let channel = 0;
        core.message(ControllerMessage::CreatedChannel(channel), &mut memory)?;
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing); // Push 7
        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::Send(channel, 7)
        );
        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::DeleteChannel(channel)
        );
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Halt);
        assert_eq!(memory.stack_size()?, 0);

        Ok(())
    }

    #[test]
    fn create_process_and_receive_message_from_it() -> Result<(), String> {
        let num_words_to_copy = 1;
        let start_address = 0;
        let is = compile![
            Instruction::Process(ProcessOp::CreateChannel),
            Instruction::Stack(StackOp::Dup),
            Instruction::PushSmall(start_address),
            Instruction::PushSmall(num_words_to_copy),
            Instruction::Process(ProcessOp::Start),
            Instruction::Process(ProcessOp::Receive),
            Instruction::Stack(StackOp::Swap),
            Instruction::Process(ProcessOp::DestroyChannel),
            Instruction::Process(ProcessOp::End)
        ];
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();

        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::CreateChannel
        );
        let channel = 12;
        core.message(ControllerMessage::CreatedChannel(channel), &mut memory)?;
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing); // Dup
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing); // num_words_to_copy
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing); // start_address
        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::StartProcess(start_address.into(), num_words_to_copy.into())
        ); // Dup
        for _i in 0..num_words_to_copy {
            memory.stack_pop()?;
        }
        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::Receive(channel)
        );
        let message = 7;
        core.message(ControllerMessage::Receive(channel, message), &mut memory)?;
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Nothing); // Swap
        assert_eq!(
            core.tick(&is, &mut memory, true)?,
            CoreMessage::DeleteChannel(channel)
        );
        assert_eq!(core.tick(&is, &mut memory, true)?, CoreMessage::Halt);
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, message);

        Ok(())
    }

    #[test]
    fn single_core_runs_two_processes() -> Result<(), String> {
        let num_words_to_copy = 1;
        let start_address = 9;
        let message = 7;
        let is = compile![
            // Process 1
            Instruction::Process(ProcessOp::CreateChannel), // 0
            Instruction::Stack(StackOp::Dup),
            Instruction::PushSmall(start_address),
            Instruction::PushSmall(num_words_to_copy), // 3
            Instruction::Process(ProcessOp::Start),
            Instruction::Process(ProcessOp::Receive), // 5
            Instruction::Stack(StackOp::Swap),
            Instruction::Process(ProcessOp::DestroyChannel), // 7
            Instruction::Process(ProcessOp::End),            // Process 2
            Instruction::PushSmall(message),                 // 9
            Instruction::Process(ProcessOp::Send),
            Instruction::Process(ProcessOp::End) // 11
        ];

        let mut memory1 = MemoryCell::new(0);
        let mut core = Core::default();

        // Run the process until it needs to wait to receive a message
        assert_eq!(
            core.tick(&is, &mut memory1, true)?,
            CoreMessage::CreateChannel
        );
        let rx_channel = 12;
        core.message(ControllerMessage::CreatedChannel(rx_channel), &mut memory1)?;
        assert_eq!(core.tick(&is, &mut memory1, true)?, CoreMessage::Nothing); // Dup
        assert_eq!(core.tick(&is, &mut memory1, true)?, CoreMessage::Nothing); // num_words_to_copy
        assert_eq!(core.tick(&is, &mut memory1, true)?, CoreMessage::Nothing); // start_address
        assert_eq!(
            core.tick(&is, &mut memory1, true)?,
            CoreMessage::StartProcess(start_address.into(), num_words_to_copy.into())
        ); // Dup

        let tx_channel = memory1.stack_pop()?;
        assert_eq!(rx_channel, tx_channel);

        assert_eq!(
            core.tick(&is, &mut memory1, true)?,
            CoreMessage::Receive(rx_channel.into())
        );
        core.message(ControllerMessage::SaveToMemory, &mut memory1)?;

        let mut memory2 = MemoryCell::new(start_address.into());
        memory2.stack_push(tx_channel)?;
        core.message(ControllerMessage::ResumeFromMemory, &mut memory2)?;

        assert_eq!(core.tick(&is, &mut memory2, true)?, CoreMessage::Nothing); // Push message
        assert_eq!(
            core.tick(&is, &mut memory2, true)?,
            CoreMessage::Send(tx_channel.into(), message.into())
        );
        core.message(ControllerMessage::SaveToMemory, &mut memory2)?;

        memory1.stack_push(message.into())?;

        core.message(ControllerMessage::ResumeFromMemory, &mut memory1)?;
        assert_eq!(core.tick(&is, &mut memory1, true)?, CoreMessage::Nothing); // Swap
        assert_eq!(
            core.tick(&is, &mut memory1, true)?,
            CoreMessage::DeleteChannel(rx_channel.into())
        );
        assert_eq!(core.tick(&is, &mut memory1, true)?, CoreMessage::Halt);

        assert_eq!(memory1.stack_size()?, 1);
        assert_eq!(memory1.stack_peek(0)?, message.into());

        core.message(ControllerMessage::ResumeFromMemory, &mut memory2)?;
        assert_eq!(core.tick(&is, &mut memory2, true)?, CoreMessage::Halt);

        assert_eq!(memory2.stack_size()?, 1);

        Ok(())
    }

    #[test]
    fn read_local_by_offset() -> Result<(), String> {
        let is = assemble(lex_str("1 0 get + .")?)?;
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 2);
        Ok(())
    }

    #[test]
    fn read_local_by_medium_offset() -> Result<(), String> {
        let is = assemble(lex_str("16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 8 get .")?)?;
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 18);
        assert_eq!(memory.stack_peek(0)?, 8);
        Ok(())
    }

    #[test]
    fn read_local_by_large_offset() -> Result<(), String> {
        let is = assemble(lex_str(
            "16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 16 get .",
        )?)?;
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 18);
        assert_eq!(memory.stack_peek(0)?, 16);
        Ok(())
    }

    #[test]
    fn write_local_by_offset() -> Result<(), String> {
        let is = assemble(lex_str("0 1 0 put .")?)?;
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 1);
        assert_eq!(memory.stack_peek(0)?, 1);
        Ok(())
    }

    #[test]
    fn write_local_by_medium_offset() -> Result<(), String> {
        let is = assemble(lex_str("4 3 2 1 10 3 put .")?)?;
        let mut memory = MemoryCell::new(0);
        let mut core = Core::default();
        core.run(&is, &mut memory, true)?;
        assert_eq!(memory.stack_size()?, 4);
        assert_eq!(memory.stack_peek(0)?, 1);
        assert_eq!(memory.stack_peek(1)?, 2);
        assert_eq!(memory.stack_peek(2)?, 3);
        assert_eq!(memory.stack_peek(3)?, 10);
        Ok(())
    }
}
