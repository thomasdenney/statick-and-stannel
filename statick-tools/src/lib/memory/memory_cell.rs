use super::WordIO;
use crate::core::Flags;
use crate::memory::Memory;
use crate::process::{CallStack, Process, ValueStack};
use std::fmt;

pub const MEMORY_CELL_SIZE: u16 = 512;

pub struct MemoryCell {
    pub memory: Memory,
}

impl Default for MemoryCell {
    fn default() -> Self {
        let memory = vec![0; MEMORY_CELL_SIZE as usize];
        MemoryCell { memory }
    }
}

impl MemoryCell {
    pub fn new(pc: u16) -> MemoryCell {
        let mut memory = MemoryCell::default();
        memory.initialise_with_program_counter(pc).unwrap();
        memory
    }

    pub fn initialise_with_program_counter(&mut self, pc: u16) -> Result<(), String> {
        self.set_program_counter(pc)?;
        self.set_call_stack_pointer(self.header_size())?;
        self.set_stack_pointer(MEMORY_CELL_SIZE)?;
        self.set_flags(Flags::default())?;
        Ok(())
    }

    pub fn stack_block_copy(&mut self, other: &MemoryCell, num_words: u16) -> Result<(), String> {
        let old_sp = self.stack_pointer()? as usize;
        let new_sp = old_sp - (num_words as usize) * 2;
        let src_sp = other.stack_pointer()? as usize;
        let src_end = src_sp + (num_words as usize) * 2;
        // Copies bytes
        self.memory[new_sp..old_sp].clone_from_slice(&other.memory[src_sp..src_end]);
        self.set_stack_pointer(new_sp as u16)
    }
}

impl Process for MemoryCell {
    fn program_counter(&self) -> Result<u16, String> {
        self.read_word(0)
    }

    fn set_program_counter(&mut self, pc: u16) -> Result<(), String> {
        self.write_word(0, pc)
    }

    fn call_stack_pointer(&self) -> Result<u16, String> {
        self.read_word(2)
    }

    fn set_call_stack_pointer(&mut self, csp: u16) -> Result<(), String> {
        self.write_word(2, csp)
    }

    fn stack_pointer(&self) -> Result<u16, String> {
        self.read_word(4)
    }

    fn set_stack_pointer(&mut self, sp: u16) -> Result<(), String> {
        self.write_word(4, sp)
    }

    fn get_flags(&self) -> Result<Flags, String> {
        Ok(Flags::decode(self.read_byte(6)?))
    }

    fn set_flags(&mut self, flags: Flags) -> Result<(), String> {
        self.write_byte(6, flags.encode())
    }

    fn header_size(&self) -> u16 {
        // Currently this is enough for program counter, call stack pointer, stack pointer, meta
        // (which includes the ALU flags but will probably exclude other stuff like next/prev
        // pointer as this can and should be stored elsewhere).
        8
    }
}

// Might take this out later; I'm not sure how useful it is going to be
impl WordIO for MemoryCell {
    fn read_word(&self, address: u16) -> Result<u16, String> {
        self.memory.read_word(address)
    }

    fn write_word(&mut self, address: u16, word: u16) -> Result<(), String> {
        self.memory.write_word(address, word)
    }
}

impl ValueStack for MemoryCell {
    fn stack_base(&self) -> u16 {
        MEMORY_CELL_SIZE
    }
}

impl CallStack for MemoryCell {}

impl fmt::Display for MemoryCell {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        ValueStack::fmt(self, f)
    }
}

#[cfg(test)]
mod word_io_tests {
    use super::*;

    fn default_memory() -> Memory {
        vec![0xC0, 0xFF, 0xEE, 0]
    }

    #[test]
    fn read_word() -> Result<(), String> {
        let mem = default_memory();
        assert_eq!(0xC0FF, mem.read_word(0)?);
        assert_eq!(0xEE00, mem.read_word(2)?);
        Ok(())
    }

    #[test]
    fn read_byte() -> Result<(), String> {
        let mem = default_memory();
        assert_eq!(0xC0, mem.read_byte(0)?);
        assert_eq!(0xFF, mem.read_byte(1)?);
        assert_eq!(0xEE, mem.read_byte(2)?);
        assert_eq!(0x00, mem.read_byte(3)?);
        Ok(())
    }

    #[test]
    fn write_word() -> Result<(), String> {
        let mut mem = default_memory();
        mem.write_word(0, 0x00EE)?;
        mem.write_word(2, 0xFF0C)?;
        assert_eq!(mem[0], 0x00);
        assert_eq!(mem[1], 0xEE);
        assert_eq!(mem[2], 0xFF);
        assert_eq!(mem[3], 0x0C);
        Ok(())
    }

    #[test]
    fn write_byte() -> Result<(), String> {
        let mut mem = default_memory();
        mem.write_byte(0, 0x00)?;
        mem.write_byte(1, 0xEE)?;
        mem.write_byte(2, 0xFF)?;
        mem.write_byte(3, 0x0C)?;
        assert_eq!(mem[0], 0x00);
        assert_eq!(mem[1], 0xEE);
        assert_eq!(mem[2], 0xFF);
        assert_eq!(mem[3], 0x0C);
        Ok(())
    }
}
