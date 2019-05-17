use crate::core::{Channel, ControllerMessage, Core, CoreMessage, ExecutionUnit};
use crate::memory::{Heap, MemoryCell, WordIO, MEMORY_CELL_SIZE};
use crate::process;
use crate::process::{ValueStack, NO_PROCESS};
use std::collections::{HashMap, HashSet};

pub struct Processor {
    cycle_count: u32,
    cores: Vec<Core>,
    cells: Vec<MemoryCell>,
    channel_heap: Heap,
    core_to_process: HashMap<u16, u16>,
    current_pid_to_alloc_number: HashMap<u16, usize>,
    final_stacks: HashMap<usize, Vec<u16>>,
    has_instructions: bool,
    alternation_set: HashSet<u16>,
    alternation_ready_set: HashSet<u16>,
}

impl Default for Processor {
    fn default() -> Self {
        Processor::new(4, 32)
    }
}

#[derive(Debug, Eq, PartialEq)]
pub enum State {
    Running,
    Halted,
}

#[derive(Debug, Eq, PartialEq)]
enum SchedulerMessage {
    Schedule(u16),
    Deschedule(u16),
    Destroy(u16),
}

/// For a processor with N cores and M memory cells of size K:
///   - The first N memory cells are used for instruction caches for each core
///   - The last memory cell (M-1) is used for storing metadata:
///         - Bytes [0..M) of the cell are used for storing process metadata
///         - Bytes [M..K) are used for storing channels (4 bytes each)
///   - Memory cells [N..M-1) are used for storing process data
impl Processor {
    pub fn new(core_count: u16, cell_count: u16) -> Processor {
        assert!(core_count >= 1);
        // Each core needs its own instruction cache. There needs to be at least one memory cell for
        // running the first process in, and at least one more for storing the metadata about cell
        // usage and channels.
        assert!(cell_count > core_count + 2);
        let mut cores = Vec::with_capacity(core_count as usize);
        let mut core_to_process = HashMap::new();
        for i in 0..core_count {
            cores.push(Core::default());
            core_to_process.insert(i as u16, NO_PROCESS);
        }
        let mut cells = Vec::with_capacity(cell_count as usize);
        for _i in 0..cell_count {
            cells.push(MemoryCell::default());
        }
        let has_instructions = false;
        let cycle_count = 0;
        let channel_heap = Heap::new(cell_count, MEMORY_CELL_SIZE, 4);
        let current_pid_to_alloc_number = HashMap::new();
        let final_stacks = HashMap::new();
        let alternation_set = HashSet::new();
        let alternation_ready_set = HashSet::new();

        Processor {
            has_instructions,
            cycle_count,
            cores,
            cells,
            core_to_process,
            channel_heap,
            current_pid_to_alloc_number,
            final_stacks,
            alternation_set,
            alternation_ready_set,
        }
    }

    pub fn set_instructions(&mut self, instructions: &[u8]) -> Result<(), String> {
        if instructions.len() > MEMORY_CELL_SIZE as usize {
            return Err(format!(
                "{} instruction bytes do not fit in one memory cell",
                instructions.len()
            ));
        }
        // Copy the instructions into each core's cache
        assert!(instructions.len() < MEMORY_CELL_SIZE as usize);
        for core in 0..self.cores.len() {
            self.cells[core as usize].memory[0..instructions.len()]
                .clone_from_slice(&instructions[..]);
        }
        // Deactive all cores and processes
        for i in 0..self.cores.len() {
            self.cores[i] = Core::default();
        }
        self.core_to_process = HashMap::new();
        let fst = self.first_process_index();
        for i in (fst + 1)..self.last_process_index() {
            self.set_process_state(i as u16, process::State::Dead)?;
        }
        self.set_process_state(fst as u16, process::State::Running(0))?;
        self.current_pid_to_alloc_number = HashMap::new();
        self.final_stacks = HashMap::new();
        self.current_pid_to_alloc_number.insert(fst, 0);
        self.cells[fst as usize].initialise_with_program_counter(0)?;
        self.has_instructions = true;
        self.alternation_set.clear();
        Ok(())
    }

    fn first_process_index(&self) -> u16 {
        self.cores.len() as u16
    }

    fn last_process_index(&self) -> u16 {
        (self.cells.len() - 1) as u16
    }

    fn meta_cell_index(&self) -> usize {
        self.cells.len() - 1
    }

    fn channel_cell_index(&self) -> usize {
        // This can be shared with the |meta_cell_index|
        self.cells.len() - 1
    }

    fn set_process_state(&mut self, pid: u16, status: process::State) -> Result<(), String> {
        assert!((pid as usize) < self.cells.len());
        let byte = status.encode();
        let process_cell_idx = self.meta_cell_index();
        self.cells[process_cell_idx].write_byte(pid, byte)?;
        if let process::State::Running(core) = status {
            self.core_to_process.insert(core, pid);
        }
        Ok(())
    }

    fn get_process_state(&self, pid: u16) -> Result<process::State, String> {
        assert!((pid as usize) < self.cells.len());
        let process_cell_idx = self.meta_cell_index();
        let byte = self.cells[process_cell_idx].read_byte(pid)?;
        let status = process::State::decode(byte);
        Ok(status)
    }

    fn process_is_running(&self, pid: u16) -> Result<bool, String> {
        if let process::State::Running(_) = self.get_process_state(pid)? {
            Ok(true)
        } else {
            Ok(false)
        }
    }

    #[allow(clippy::cyclomatic_complexity)] // I'm unlikely to simplify this function
    pub fn tick(&mut self, verbose: bool) -> Result<State, String> {
        if !self.has_instructions {
            return Err("This processor has not been instantiated with instructions.".to_string());
        }
        if verbose {
            println!(
                "################ CYCLE {} ################",
                self.cycle_count
            );
            self.cycle_count += 1;
        }
        let mut messages = Vec::new();
        let mut channel_messages = HashMap::new();
        let mut channel_listeners = HashSet::new();
        for core in 0..self.cores.len() {
            if let Some(pid) = self.core_to_process.get(&(core as u16)) {
                // This is the minimal "safe" way of avoiding the issue with mutable and immutable borrows
                let instruction_cell = &self.cells[core] as *const MemoryCell;
                let process_cell = &mut self.cells[*pid as usize] as *mut MemoryCell;
                if verbose {
                    print!("Core {}: ", core);
                }
                let message = unsafe {
                    self.cores[core].tick(&*instruction_cell, &mut *process_cell, verbose)?
                };
                if verbose {
                    println!(" -> {:?}", message);
                }
                // For same-cycle channel delivery
                match message {
                    CoreMessage::Send(chan, val) => {
                        channel_messages.insert(chan, val);
                    }
                    CoreMessage::Receive(chan) => {
                        channel_listeners.insert(chan);
                    }
                    _ => {}
                };
                messages.push(Some(message));
            } else {
                messages.push(None);
            }
        }

        let mut return_messages = Vec::new();
        for _i in 0..self.cores.len() {
            return_messages.push(None)
        }

        let mut scheduler_tasks = Vec::new();

        for (core, msg) in messages.iter().enumerate() {
            let mut message_to_return = None;
            if let Some(msg) = msg {
                let pid = self.core_to_process[&(core as u16)] as u16;
                match msg {
                    CoreMessage::Yield => {
                        message_to_return = Some(ControllerMessage::SaveToMemory);
                        scheduler_tasks.push(SchedulerMessage::Deschedule(pid));
                    }
                    CoreMessage::Halt => {
                        message_to_return = Some(ControllerMessage::SaveToMemory);
                        scheduler_tasks.push(SchedulerMessage::Destroy(pid));
                    }
                    CoreMessage::StartProcess(pc, num_words) => {
                        let pc = *pc;
                        let num_words = *num_words;
                        let new_pid = self.new_process()?;
                        scheduler_tasks.push(SchedulerMessage::Schedule(new_pid));
                        self.cells[new_pid as usize].initialise_with_program_counter(pc)?;
                        assert!(pid != new_pid);
                        self.current_pid_to_alloc_number
                            .insert(new_pid, self.current_pid_to_alloc_number.len());
                        let new_cell = &mut self.cells[new_pid as usize] as *mut MemoryCell;
                        let old_cell = &self.cells[pid as usize] as *const MemoryCell;
                        unsafe {
                            (*new_cell).stack_block_copy(&*old_cell, num_words)?;
                        }
                        self.cells[pid as usize].stack_pop_many(num_words)?;
                    }
                    CoreMessage::CreateChannel => {
                        let addr = self.create_channel()?;
                        message_to_return = Some(ControllerMessage::CreatedChannel(addr));
                    }
                    CoreMessage::DeleteChannel(channel) => {
                        let chan_idx = self.channel_cell_index();
                        self.channel_heap
                            .free(&mut self.cells[chan_idx], *channel)?;
                    }
                    CoreMessage::Send(channel, value) => {
                        if !channel_listeners.contains(channel) {
                            // No other process core is currently listening on this channel so we
                            // must write its value to memory and continue
                            message_to_return = Some(ControllerMessage::SaveToMemory);
                            let mut tasks = self.send(*channel, *value, pid)?;
                            scheduler_tasks.append(&mut tasks);
                        }
                    }
                    CoreMessage::Receive(channel) => {
                        // This allows for same cycle message delivery between processor cores
                        if let Some(val) = channel_messages.get(channel) {
                            message_to_return = Some(ControllerMessage::Receive(*channel, *val));
                        } else {
                            // Otherwise we have to schedule in a save
                            message_to_return = Some(ControllerMessage::SaveToMemory);
                            scheduler_tasks.push(self.receive(*channel, pid)?);
                        }
                    }
                    CoreMessage::AlternationStart => {
                        self.alternation_set.insert(pid);
                    }
                    CoreMessage::AlternationWait => {
                        if !self.alternation_ready_set.contains(&pid) {
                            scheduler_tasks.push(SchedulerMessage::Deschedule(pid))
                        }
                    }
                    CoreMessage::AlternationEnd => {
                        self.alternation_set.remove(&pid);
                        self.alternation_ready_set.remove(&pid);
                    }
                    CoreMessage::EnableChannel(channel) => {
                        self.enable_channel(*channel, pid)?;
                    }
                    CoreMessage::DisableChannel(channel, jump_dest, has_alternation_value) => {
                        if let Some(msg) =
                            self.disable_channel(*channel, pid, *has_alternation_value)?
                        {
                            message_to_return = Some(ControllerMessage::Jump(*jump_dest));
                            scheduler_tasks.push(msg);
                        }
                    }
                    CoreMessage::Nothing => {}
                }
                return_messages[core] = message_to_return;
            }
        }

        for (core, message) in return_messages.iter().enumerate() {
            if let Some(message) = message {
                let cell_idx = self.core_to_process[&(core as u16)];
                self.cores[core].message(message.clone(), &mut self.cells[cell_idx as usize])?;
            }
        }

        let mut inactive_cores: Vec<u16> = Vec::new();
        for core in 0..(self.cores.len() as u16) {
            if !self.core_to_process.contains_key(&core) {
                inactive_cores.push(core);
            }
        }

        // Deschedule and delete processes
        for task in &scheduler_tasks {
            let mut deschedule = |pid: u16, status: process::State| -> Result<(), String> {
                let state = self.get_process_state(pid)?;
                if let process::State::Running(core) = state {
                    self.core_to_process.remove(&core);
                    inactive_cores.push(core);
                }
                self.set_process_state(pid, status)?;
                if verbose {
                    println!("{:?} with final stack {}", task, self.cells[pid as usize]);
                }
                Ok(())
            };
            match task {
                SchedulerMessage::Destroy(pid) => {
                    deschedule(*pid, process::State::Dead)?;
                    self.final_stacks.insert(
                        self.current_pid_to_alloc_number[pid],
                        self.cells[*pid as usize].stack_values(),
                    );
                }
                SchedulerMessage::Deschedule(pid) => {
                    deschedule(*pid, process::State::Inactive)?;
                }
                _ => {}
            }
        }

        // Schedule processes uncovered during this iteration
        for task in &scheduler_tasks {
            if let SchedulerMessage::Schedule(pid) = task {
                if !self.process_is_running(*pid)? {
                    match inactive_cores.pop() {
                        Some(core) => {
                            self.set_process_state(*pid, process::State::Running(core))?;
                            if verbose {
                                println!("Scheduled {} on {} (new or resumed process)", pid, core);
                            }
                        }
                        None => self.set_process_state(*pid, process::State::Waiting)?,
                    }
                }
            }
        }

        // Schedule processes if there are still cores available
        if !inactive_cores.is_empty() {
            for pid in self.first_process_index()..self.last_process_index() {
                let state = self.get_process_state(pid)?;
                if state == process::State::Waiting {
                    match inactive_cores.pop() {
                        Some(core) => {
                            self.set_process_state(pid, process::State::Running(core))?;
                            if verbose {
                                println!("Scheduled {} on {} (core was inactive)", pid, core);
                            }
                        }
                        None => break,
                    }
                }
            }
        }

        if self.core_to_process.is_empty() {
            Ok(State::Halted)
        } else {
            Ok(State::Running)
        }
    }

    fn get_channel_process(&self, channel: Channel) -> Result<process::Channel, String> {
        let chan_cell_idx = self.channel_cell_index();
        let word = self.cells[chan_cell_idx].read_word(channel)?;
        let pid = word & 0x7FFF;
        let in_alternation = word & 0x8000 != 0;
        Ok(process::Channel {
            pid,
            in_alternation,
        })
    }

    fn get_channel_value(&self, channel: Channel) -> Result<u16, String> {
        let chan_cell_idx = self.channel_cell_index();
        self.cells[chan_cell_idx].read_word(channel + 2)
    }

    fn set_channel_process(
        &mut self,
        channel: Channel,
        pid: u16,
        in_alternation: bool,
    ) -> Result<(), String> {
        assert!(pid & 0x8000 == 0);
        let chan_cell_idx = self.channel_cell_index();
        let mut word = pid;
        if in_alternation {
            word |= 0x8000;
        }
        self.cells[chan_cell_idx].write_word(channel, word)?;
        Ok(())
    }

    fn set_channel_value(&mut self, channel: Channel, value: u16) -> Result<(), String> {
        let chan_cell_idx = self.channel_cell_index();
        self.cells[chan_cell_idx].write_word(channel + 2, value)
    }

    fn create_channel(&mut self) -> Result<Channel, String> {
        let chan_cell_idx = self.channel_cell_index();
        let channel = self.channel_heap.alloc(&self.cells[chan_cell_idx])?;
        self.cells[chan_cell_idx].write_word(channel, NO_PROCESS)?;
        self.cells[chan_cell_idx].write_word(channel + 2, 0)?;
        Ok(channel)
    }

    fn send(
        &mut self,
        channel: Channel,
        message: u16,
        tx_pid: u16,
    ) -> Result<Vec<SchedulerMessage>, String> {
        self.set_channel_value(channel, message)?;
        let rx_proc = self.get_channel_process(channel)?;
        if rx_proc.is_empty() {
            self.set_channel_process(channel, tx_pid, false)?;
            Ok(vec![SchedulerMessage::Deschedule(tx_pid)])
        } else if rx_proc.in_alternation {
            self.set_channel_process(channel, tx_pid, true)?;
            if !self.alternation_ready_set.contains(&rx_proc.pid) {
                // This is the first message to reach the receiving process
                self.alternation_ready_set.insert(rx_proc.pid);
                // Don't deal with whether or nor the process is already scheduled here
                // The |disable_channel| will handle waking up this process
                Ok(vec![
                    SchedulerMessage::Schedule(rx_proc.pid),
                    SchedulerMessage::Deschedule(tx_pid),
                ])
            } else {
                // Some other process already woke up the alternation process
                // I'm not sure it matters if |in_alternation| is set
                Ok(vec![SchedulerMessage::Deschedule(tx_pid)])
            }
        } else {
            // Normal receive, so just wake the process up like normal
            self.cells[rx_proc.pid as usize].stack_push(message)?;
            self.set_channel_process(channel, NO_PROCESS, false)?;
            Ok(vec![SchedulerMessage::Schedule(rx_proc.pid)])
        }
    }

    fn receive(&mut self, channel: Channel, rx_pid: u16) -> Result<SchedulerMessage, String> {
        let tx_proc = self.get_channel_process(channel)?;
        if tx_proc.is_empty() {
            self.set_channel_process(channel, rx_pid, false)?;
            Ok(SchedulerMessage::Deschedule(rx_pid))
        } else {
            let message = self.get_channel_value(channel)?;
            self.set_channel_process(channel, NO_PROCESS, false)?;
            self.cells[rx_pid as usize].stack_push(message)?;
            Ok(SchedulerMessage::Schedule(tx_proc.pid))
        }
    }

    fn enable_channel(&mut self, channel: Channel, rx_pid: u16) -> Result<(), String> {
        let tx_proc = self.get_channel_process(channel)?;
        if tx_proc.is_empty() {
            // No sending process has yet sent to this channel, so we therefore mark that this
            // process is waiting, but that it is waiting in alternation, so if a sending process
            // sees this it will wait to be scheduled
            self.set_channel_process(channel, rx_pid, true)?;
        } else {
            // A process has already written to this channel. We shouldn't wake up that process yet
            // because other channels may have also been written to. Therefore we take this process
            // out of the alternation state so that when it reaches the 'alternation wait'
            // instruction it will not halt
            self.alternation_ready_set.insert(rx_pid);
        }
        Ok(())
    }

    fn disable_channel(
        &mut self,
        channel: Channel,
        rx_pid: u16,
        has_alternation_value: bool,
    ) -> Result<Option<SchedulerMessage>, String> {
        let tx_proc = self.get_channel_process(channel)?;
        if tx_proc.is_empty() {
            Ok(None)
        } else if tx_proc.pid == rx_pid {
            // Still hasn't received a message on the channel, so remove this channel as a listener
            // of the channel.
            self.set_channel_process(channel, NO_PROCESS, false)?;
            Ok(None)
        } else if !has_alternation_value {
            // Received a message on the channel from some other process
            let value = self.get_channel_value(channel)?;
            self.cells[rx_pid as usize].stack_push(value)?;
            self.set_channel_process(channel, NO_PROCESS, false)?;
            Ok(Some(SchedulerMessage::Schedule(tx_proc.pid)))
        } else {
            Ok(None)
        }
    }

    fn new_process(&mut self) -> Result<u16, String> {
        for pid in self.first_process_index()..self.last_process_index() {
            let status = self.get_process_state(pid)?;
            if status == process::State::Dead {
                return Ok(pid);
            }
        }
        Err("No free process slots".to_string())
    }

    pub fn run(&mut self, verbose: bool) -> Result<(), String> {
        while self.tick(verbose)? == State::Running {}
        Ok(())
    }

    #[cfg(test)]
    pub fn final_stack<'a>(&'a self, alloc_id: usize) -> &'a Vec<u16> {
        &self.final_stacks[&alloc_id]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::assembler::{assemble, lex_str};
    use crate::isa::{Instruction, Op, ProcessOp};
    use crate::*;

    #[test]
    fn single_process_halts() -> Result<(), String> {
        let is = compile![Instruction::Process(ProcessOp::End)];
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        assert_eq!(processor.tick(true)?, State::Halted);
        Ok(())
    }

    /// This is a slightly problematic test because it could run forever
    #[test]
    fn running_a_halt_works() -> Result<(), String> {
        let is = compile![Instruction::Process(ProcessOp::End)];
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)
    }

    #[test]
    fn running_a_simple_program_works() -> Result<(), String> {
        let is = compile![
            Instruction::PushSmall(3),
            Instruction::PushSmall(7),
            Instruction::ArithmeticOrLogic(Op::Add),
            Instruction::Process(ProcessOp::End)
        ];
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack0 = processor.final_stack(0);
        assert_eq!(stack0.len(), 1);
        assert_eq!(stack0[0], 10);

        Ok(())
    }

    #[test]
    fn create_a_process_and_halt() -> Result<(), String> {
        let is = compile![
            Instruction::PushSmall(3), // 0
            Instruction::PushSmall(5),
            Instruction::PushSmall(0), // 2
            Instruction::Process(ProcessOp::Start),
            Instruction::Process(ProcessOp::End), // 4
            Instruction::PushSmall(7),
            Instruction::Process(ProcessOp::End) // 6
        ];
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack0 = processor.final_stack(0);
        let stack1 = processor.final_stack(1);
        assert_eq!(stack0.len(), 1);
        assert_eq!(stack0[0], 3);
        assert_eq!(stack1.len(), 1);
        assert_eq!(stack1[0], 7);
        Ok(())
    }

    #[test]
    fn create_a_process_and_communicate() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            p0:
                chan dup
                p1 1 start
                7 ! del .
            p1:
                ? swap drop .
        ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack0 = processor.final_stack(0);
        let stack1 = processor.final_stack(1);
        assert_eq!(stack0.len(), 0);
        assert_eq!(stack1.len(), 1);
        assert_eq!(stack1[0], 7);
        Ok(())
    }

    #[test]
    fn create_a_process_and_communicate_a_couple_of_times() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            p0:
                chan dup
                p1 1 start
                ? swap ? swap del + .
            p1:
                3 ! 7 ! drop .
        ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack0 = processor.final_stack(0);
        let stack1 = processor.final_stack(1);
        assert_eq!(stack0.len(), 1);
        assert_eq!(stack0[0], 10);
        assert_eq!(stack1.len(), 0);
        Ok(())
    }

    #[test]
    fn communicate_a_channel() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            p0:
                chan dup             # Create a channel
                p1 1 start           # Initiate another process with the same channel
                chan dup rot !  # Create a new channel, send it to the other process
                swap ?               # Listen on the new channel
                swap del swap drop . # Delete the new channel, halt
            p1:
                ?                    # Receive new channel
                7 !             # Send a message on the new channel
                swap del drop .      # Delete the original channel, halt
        ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack0 = processor.final_stack(0);
        let stack1 = processor.final_stack(1);
        dbg!(&stack0);
        assert_eq!(stack0.len(), 1);
        assert_eq!(stack0[0], 7);
        assert_eq!(stack1.len(), 0);
        Ok(())
    }

    #[test]
    fn alternation() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            main:
                chan chan               # Create two channels
                0 get proc1 1 start     # Send a copy of the second channel to proc1
                1 get proc2 1 start     # Send a copy of the first channel to proc2
                altstart
                0 get enable
                1 get enable
                altwait
                0 get case1 disable
                1 get case2 disable
                altend
            case1:
                1 + 2 get ? swap drop - cleanup j
            case2:
                1 + 1 get ? swap drop - cleanup j
            cleanup:
                rot del del .
            proc1:
                3 ! .
            proc2:
                7 ! .
            ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack = processor.final_stack(0);
        assert_eq!(stack.len(), 1);
        assert_eq!(stack[0], (4 as u16).overflowing_sub(7).0);
        Ok(())
    }

    #[test]
    fn alternation_long() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            main:
                chan chan               # Create two channels
                0 get proc1 1 start     # Send a copy of the second channel to proc1
                1 get proc2 1 start     # Send a copy of the first channel to proc2
                altstart
                0 get enable
                1 get enable
                altwait
                0 get case1 disable
                1 get case2 disable
                altend
            case1:
                1 + 2 get ? swap drop - cleanup j
            case2:
                1 + 1 get ? swap drop - cleanup j
            cleanup:
                rot del del .
            proc1:
                # Ensure that this process will always complete after the other one
                nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop
                3 ! .
            proc2:
                7 ! .
            ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack = processor.final_stack(0);
        assert_eq!(stack.len(), 1);
        assert_eq!(stack[0], 5);
        Ok(())
    }
    #[test]
    fn alternation_very_long() -> Result<(), String> {
        let is = assemble(lex_str(
            "
            main:
                chan chan               # Create two channels
                0 get proc1 1 start     # Send a copy of the second channel to proc1
                1 get proc2 1 start     # Send a copy of the first channel to proc2
                altstart
                0 get enable
                1 get enable
                altwait
                0 get case1 disable
                1 get case2 disable
                altend
            case1:
                1 + 2 get ? swap drop - cleanup j
            case2:
                1 + 1 get ? swap drop - cleanup j
            cleanup:
                rot del del .
            proc1:
                nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop
                3 ! .
            proc2:
                nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop nop
                7 ! .
            ",
        )?)?;
        let mut processor = Processor::default();
        processor.set_instructions(&is)?;
        processor.run(true)?;
        let stack = processor.final_stack(0);
        assert_eq!(stack.len(), 1);
        assert!(stack[0] == 5 || stack[0] == (4 as u16).overflowing_sub(7).0);
        Ok(())
    }
}
