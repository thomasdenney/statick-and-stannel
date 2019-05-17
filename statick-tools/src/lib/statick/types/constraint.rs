use std::fmt;

use super::ConstraintSet;

/**
 * These act a lot like type classes (Haskell) or traits (Rust, Scala) but they are called
 * "constraints" here seen as (a) the language doesn't admit introducing new constraints, (b) they
 * only affect a very small number of functions, and (c) the language doesn't support user-defined
 * concrete types, so they won't need implementing for those types.
 */
#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub enum Constraint {
    Droppable,
    Duplicable,
    MustConsume,
    IntLike,
}

impl fmt::Display for Constraint {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        use Constraint::*;
        match self {
            Droppable => write!(f, "Droppable"),
            Duplicable => write!(f, "Duplicable"),
            MustConsume => write!(f, "MustConsume"),
            IntLike => write!(f, "IntLike"),
        }
    }
}

pub type TypeConstraints = ConstraintSet<Constraint>;
