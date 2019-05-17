use super::{
    ChannelUse, ChannelVariable, Constraint, Direction, Stack, StackConstraint, StackConstraints,
    Type, TypeConstraints,
};

use std::collections::HashSet;
use std::iter::FromIterator;

#[derive(Default, Debug)]
pub struct TypeAllocator {
    generic_type_counter: usize,
    type_stack_counter: usize,
    channel_var_counter: usize,
    repeat_counter: usize,
}
macro_rules! inc {
    ($x: expr) => {{
        let old = $x;
        $x = old + 1;
        old
    }};
}

impl TypeAllocator {
    pub fn next_generic_type_counter(&mut self) -> usize {
        inc!(self.generic_type_counter)
    }

    pub fn next_type_stack_counter(&mut self) -> usize {
        inc!(self.type_stack_counter)
    }

    pub fn next_channel_var_counter(&mut self) -> ChannelVariable {
        inc!(self.channel_var_counter)
    }

    fn next_repeat_counter(&mut self) -> usize {
        inc!(self.repeat_counter)
    }

    pub fn proc_type(&mut self, k: Option<u16>) -> Type {
        let num_words = match k {
            Some(k) => k,
            None => 0,
        };
        let base = self.type_stack(StackConstraints::default());
        let mut this_stack_type = base.clone();
        let mut sc = StackConstraints::default();
        sc.insert(StackConstraint::MustBeBase);
        let mut proc_stack_type = self.type_stack(sc);
        // a b c ... are the types that the process is instantiated with
        for _ in 0..num_words {
            let a = self.generic_type();
            this_stack_type = Stack::Stack(Box::new(this_stack_type), Box::new(a.clone()));
            proc_stack_type = Stack::Stack(Box::new(proc_stack_type), Box::new(a));
        }
        // Important this is completely generic: the creating function *does not*
        // care about the final stack state of the process it creates.
        let mut constraints = StackConstraints::default();
        constraints.insert(StackConstraint::NoConsumableOrDroppableTypes);
        constraints.insert(StackConstraint::AllowBottom);
        let function_output = self.type_stack(constraints);
        let function_type = Type::Function(Box::new(proc_stack_type), Box::new(function_output));
        this_stack_type = Stack::Stack(Box::new(this_stack_type), Box::new(function_type));
        Type::Function(Box::new(this_stack_type), Box::new(base))
    }

    pub fn receive_type(&mut self, offset: u16) -> Type {
        let v = self.next_channel_var_counter();
        let (t, rx, _tx) = self.generic_channel_type(ChannelUse::Variable(v, 1));
        let mut input = vec![rx];
        for _ in 0..offset {
            input.push(self.generic_type());
        }
        let mut output = input.clone();
        output[0] = Type::Channel(
            ChannelUse::Variable(v, 0),
            Direction::Rx,
            Box::new(t.clone()),
        );
        output.push(t);
        let s = self.type_stack(StackConstraints::default());
        self.function_type(s, input, output)
    }

    pub fn send_type(&mut self, offset: u16) -> Type {
        let v = self.next_channel_var_counter();
        let (t, _rx, tx) = self.generic_channel_type(ChannelUse::Variable(v, 1));
        let mut input = vec![tx];
        if offset > 0 {
            for _ in 0..(offset - 1) {
                input.push(self.generic_type());
            }
        }
        input.push(t.clone());
        let mut output = input[..input.len() - 1].to_vec();
        output[0] = Type::Channel(
            ChannelUse::Variable(v, 0),
            Direction::Tx,
            Box::new(t.clone()),
        );
        let s = self.type_stack(StackConstraints::default());
        self.function_type(s, input, output)
    }

    pub fn del_type(&mut self, offset: u16) -> Type {
        // Tx channnel can be deleted with drop
        let in_chan_var = ChannelUse::Constant(0);
        let (_, c_rx, _) = self.generic_channel_type(in_chan_var);
        let s = self.type_stack(StackConstraints::default());
        if offset == 0 {
            self.function_type(s, vec![c_rx], vec![])
        } else {
            let mut input = vec![c_rx];
            let mut output = vec![Type::Void];
            for _ in 0..offset {
                let t = self.generic_type();
                input.push(t.clone());
                output.push(t);
            }
            self.function_type(s, input, output)
        }
    }

    pub fn repeat_type(&mut self) -> Type {
        let s = self.type_stack(StackConstraints::default());
        let new_s = self.type_stack(StackConstraints::default());
        let counter_t = Type::Counter(self.next_repeat_counter());
        let body_in = Stack::Stack(Box::new(s.clone()), Box::new(counter_t.clone()));
        let body_out = Stack::Stack(Box::new(new_s.clone()), Box::new(counter_t));
        let body_t = Type::Function(Box::new(body_in), Box::new(body_out));
        let repeat_in = Stack::Stack(Box::new(s), Box::new(body_t));
        let repeat_out = new_s;
        Type::Function(Box::new(repeat_in), Box::new(repeat_out))
    }

    pub fn chan_type(&mut self, k: Option<u16>) -> Type {
        let chan_use = match k {
            Some(k) => ChannelUse::Constant(usize::from(k)),
            None => ChannelUse::Infinity,
        };
        let (_, c_rx, c_tx) = self.generic_channel_type(chan_use);
        let s = self.type_stack(StackConstraints::default());
        self.function_type(s, vec![], vec![c_rx, c_tx])
    }

    pub fn offset_type(&mut self, offset: u16) -> Type {
        let s = self.type_stack(StackConstraints::default());
        let mut input = vec![];
        input.push(self.generic_type_with_constraints(vec![Constraint::Duplicable].into_iter()));
        for _ in 1..=offset {
            input.push(self.generic_type());
        }
        let mut output = input.clone();
        output.push(output[0].clone());
        self.function_type(s, input, output)
    }

    pub fn generic_type(&mut self) -> Type {
        Type::Generic(self.next_generic_type_counter(), TypeConstraints::default())
    }

    pub fn generic_type_with_constraints<I: IntoIterator<Item = Constraint>>(
        &mut self,
        iter: I,
    ) -> Type {
        Type::Generic(
            self.next_generic_type_counter(),
            TypeConstraints::new(HashSet::from_iter(iter)),
        )
    }

    pub fn generic_channel_type(&mut self, chan_use: ChannelUse) -> (Type, Type, Type) {
        let t = self.generic_type();
        (
            t.clone(),
            Type::Channel(chan_use, Direction::Rx, Box::new(t.clone())),
            Type::Channel(chan_use, Direction::Tx, Box::new(t)),
        )
    }

    pub fn type_stack(&mut self, c: StackConstraints) -> Stack {
        Stack::Generic(self.next_type_stack_counter(), c)
    }

    pub fn function_type(&mut self, s: Stack, inputs: Vec<Type>, outputs: Vec<Type>) -> Type {
        let mut input_t = s.clone();
        for i in inputs {
            input_t = Stack::Stack(Box::new(input_t), Box::new(i));
        }
        let mut output_t = s;
        for o in outputs {
            output_t = Stack::Stack(Box::new(output_t), Box::new(o));
        }
        Type::Function(Box::new(input_t), Box::new(output_t))
    }

    pub fn apply_type(&mut self) -> Type {
        let a = self.type_stack(StackConstraints::default());
        let b = self.type_stack(StackConstraints::default());
        let f = Type::Function(Box::new(a.clone()), Box::new(b.clone()));
        let input = Stack::Stack(Box::new(a), Box::new(f));
        Type::Function(Box::new(input), Box::new(b))
    }
}
