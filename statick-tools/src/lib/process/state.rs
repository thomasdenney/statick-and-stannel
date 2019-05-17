#[derive(Debug, Eq, PartialEq)]
pub enum State {
    Dead,
    Inactive,
    Running(u16),
    Waiting,
}

impl State {
    pub fn encode(&self) -> u8 {
        match self {
            State::Dead => 0b00,
            State::Inactive => 0b01,
            State::Running(core) => (core << 2) as u8 | 0b10,
            State::Waiting => 0b11,
        }
    }

    pub fn decode(byte: u8) -> State {
        match byte & 0b11 {
            0b00 => State::Dead,
            0b01 => State::Inactive,
            0b10 => State::Running(u16::from(byte >> 2)),
            0b11 => State::Waiting,
            _ => panic!(),
        }
    }
}
