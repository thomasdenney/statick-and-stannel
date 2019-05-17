use crate::core::Flags;

mod call_stack;
mod channel;
mod state;
mod value_stack;

pub use call_stack::CallStack;
pub use channel::Channel;
pub use state::State;
pub use value_stack::ValueStack;

pub const NO_PROCESS: u16 = 0;

// Currently keeping this separate from MemoryCells in case I decide to implement multiple processes
// per memory cell or multiple memory cells per process.
pub trait Process {
    fn program_counter(&self) -> Result<u16, String>;
    fn set_program_counter(&mut self, pc: u16) -> Result<(), String>;
    fn call_stack_pointer(&self) -> Result<u16, String>;
    fn set_call_stack_pointer(&mut self, csp: u16) -> Result<(), String>;
    fn stack_pointer(&self) -> Result<u16, String>;
    fn set_stack_pointer(&mut self, sp: u16) -> Result<(), String>;
    fn get_flags(&self) -> Result<Flags, String>;
    fn set_flags(&mut self, flags: Flags) -> Result<(), String>;
    fn header_size(&self) -> u16;
}
