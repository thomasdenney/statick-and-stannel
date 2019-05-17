use super::{ChannelUse, ChannelVariable, Stack, Type};

#[derive(Debug, Eq, PartialEq)]
pub enum UnifierStep {
    Type(usize, Type),
    Stack(usize, Stack),
    Channel(ChannelVariable, ChannelUse),
}

pub trait ApplyUnifierStep {
    fn apply_unifier_step(&self, step: &UnifierStep) -> Self;
}

/**
 * Maps from the type IDs of generic or stack variables to new type IDs
 * TODO: Implement a significantly more efficient version of this interface
 */
#[derive(Debug, Default)]
pub struct Unifier {
    pub unification_steps: Vec<UnifierStep>,
}

impl Unifier {
    pub fn add(&mut self, step: UnifierStep) {
        self.unification_steps.push(step);
    }

    pub fn compose(&mut self, other: Unifier) {
        self.unification_steps.extend(other.unification_steps);
    }

    pub fn apply<T: ApplyUnifierStep + Clone>(&self, t: &T) -> T {
        let mut t = t.clone();
        for step in &self.unification_steps {
            t = t.apply_unifier_step(step);
        }
        t
    }
}
