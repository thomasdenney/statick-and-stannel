use super::Channel;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CoreMessage {
    Nothing,
    StartProcess(u16, u16), // Start address only and number of words to move from the stack
    Yield,
    Halt,
    CreateChannel,
    DeleteChannel(Channel),
    Send(Channel, u16),
    Receive(Channel),
    AlternationStart,
    AlternationWait,
    AlternationEnd,
    EnableChannel(Channel),
    DisableChannel(Channel, u16, bool),
}

#[allow(dead_code)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ControllerMessage {
    ResumeFromMemory, // Currently only used in tests; might be used in the final design but probably not
    SaveToMemory,
    CreatedChannel(Channel),
    Receive(Channel, u16), // Technically the channel is redundant. TODO: Also handle alternations.
    Jump(u16),
}
