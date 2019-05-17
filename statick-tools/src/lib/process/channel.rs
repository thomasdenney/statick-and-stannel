use super::NO_PROCESS;

pub struct Channel {
    pub pid: u16,
    pub in_alternation: bool,
}

impl Channel {
    pub fn is_empty(&self) -> bool {
        self.pid == NO_PROCESS
    }
}
