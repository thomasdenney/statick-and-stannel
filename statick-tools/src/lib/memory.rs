mod heap;
mod memory_cell;
mod word_io;

pub use heap::Heap;
pub use memory_cell::{MemoryCell, MEMORY_CELL_SIZE};
pub use word_io::WordIO;

pub type Memory = Vec<u8>;

impl WordIO for Memory {
    fn write_word(&mut self, address: u16, word: u16) -> Result<(), String> {
        if address & 1 == 1 {
            return Err(format!(
                "{} is not a valid word address (LSB is 1)",
                address
            ));
        }
        self[address as usize] = (word >> 8) as u8;
        self[(address + 1) as usize] = (word & 0xFF) as u8;
        Ok(())
    }

    fn read_word(&self, address: u16) -> Result<u16, String> {
        if address & 1 == 1 {
            return Err(format!(
                "{} is not a valid word address (LSB is 1)",
                address
            ));
        }
        // Currently supporting out of bounds reads when requesting the last byte because the
        // instruction memory may be an odd-length vector
        if ((address + 1) as usize) < self.len() {
            let address = address as usize;
            Ok(u16::from(self[address]) << 8 | u16::from(self[address + 1]))
        } else if (address as usize) < self.len() {
            let address = address as usize;
            Ok(u16::from(self[address]) << 8)
        } else {
            Err(format!("{} is out of bounds", address))
        }
    }
}
