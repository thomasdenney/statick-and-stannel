use crate::memory::WordIO;
use crate::process::Process;
use std::fmt;

pub trait ValueStack: WordIO + Process {
    fn stack_pop(&mut self) -> Result<u16, String> {
        let sp = self.stack_pointer()?;
        let res = self.read_word(sp)?;
        self.set_stack_pointer(sp + 2)?;
        Ok(res)
    }

    fn stack_pop_many(&mut self, count: u16) -> Result<(), String> {
        let sp = self.stack_pointer()?;
        self.set_stack_pointer(sp + count * 2)
    }

    fn stack_push(&mut self, value: u16) -> Result<(), String> {
        let new_sp = self.stack_pointer()? - 2;
        self.set_stack_pointer(new_sp)?;
        self.write_word(new_sp, value)
    }

    fn stack_base(&self) -> u16;

    // Kind of unfortuante that this ends up getting wrapped
    fn stack_empty(&self) -> Result<bool, String> {
        Ok(self.stack_base() == self.stack_pointer()?)
    }

    fn stack_size(&self) -> Result<u16, String> {
        Ok((self.stack_base() - self.stack_pointer()?) / 2)
    }

    fn stack_peek(&self, offset: u16) -> Result<u16, String> {
        if offset < self.stack_size()? {
            self.read_word(self.stack_pointer()? + offset * 2)
        } else {
            Err(format!("{} too large a stack offset", offset))
        }
    }

    fn stack_values(&self) -> Vec<u16> {
        let mut result = Vec::new();
        for i in 0..self.stack_size().unwrap() {
            result.push(self.stack_peek(i).unwrap());
        }
        result
    }
}

impl fmt::Display for ValueStack {
    /// This method could potentially panic, but it should be fine
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "[")?;
        for i in 0..self.stack_size().unwrap() {
            if i != 0 {
                write!(f, ", {}", self.stack_peek(i).unwrap())?;
            } else {
                write!(f, "{}", self.stack_peek(i).unwrap())?;
            }
        }
        write!(f, "]")?;
        Ok(())
    }
}
