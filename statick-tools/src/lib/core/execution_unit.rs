use super::{ControllerMessage, CoreMessage};
use crate::{CallStack, Process, ValueStack, WordIO};

pub trait ExecutionUnit<M>
where
    M: Process + CallStack + ValueStack,
{
    /// This should simulate a single tick (effectively two cycles on the FPGA) of the core's clock
    /// and should manipulate memory as appropriate. It has read only access to the instruction
    /// cache. The core should then communicate information back to the controller on each tick, so
    /// that the controller can determine what the core should do next.
    fn tick(
        &mut self,
        instructions: &WordIO,
        memory: &mut M,
        verbose: bool,
    ) -> Result<CoreMessage, String>;

    /// It should always be possible for the core to process an arbitrary number of messages from
    /// the controller between two ticks of the clock (as the core clock itself could be stopped
    /// whilst the core is in a low power state).
    fn message(&mut self, message: ControllerMessage, memory: &mut M) -> Result<(), String>;
}
