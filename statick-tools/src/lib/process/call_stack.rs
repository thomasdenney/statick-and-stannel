use crate::memory::WordIO;
use crate::process::Process;

pub trait CallStack: WordIO + Process {
    fn call_stack_pop(&mut self) -> Result<u16, String> {
        let csp = self.call_stack_pointer()?;
        let new_csp = csp - 2;
        let res = self.read_word(new_csp)?;
        self.set_call_stack_pointer(new_csp)?;
        Ok(res)
    }

    fn call_stack_push(&mut self, address: u16) -> Result<(), String> {
        let old_csp = self.call_stack_pointer()?;
        let new_csp = old_csp + 2;
        self.set_call_stack_pointer(new_csp)?;
        self.write_word(old_csp, address)
    }
}
