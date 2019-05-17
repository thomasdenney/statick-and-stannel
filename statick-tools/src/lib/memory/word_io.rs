pub trait WordIO {
    fn read_word(&self, offset: u16) -> Result<u16, String>;
    fn write_word(&mut self, offset: u16, value: u16) -> Result<(), String>;

    fn read_byte(&self, address: u16) -> Result<u8, String> {
        // Ignore least significant bit of address
        let word = self.read_word(address & 0xFFFE)?;
        if address & 1 == 1 {
            Ok((word & 0xFF) as u8)
        } else {
            Ok((word >> 8) as u8)
        }
    }

    fn write_byte(&mut self, address: u16, byte: u8) -> Result<(), String> {
        let io_address = address & 0xFFFE;
        let mut word = self.read_word(io_address)?;
        if address & 1 == 1 {
            word = (word & 0xFF00) | u16::from(byte);
        } else {
            word = (word & 0x00FF) | (u16::from(byte) << 8);
        }
        self.write_word(io_address, word)
    }
}
