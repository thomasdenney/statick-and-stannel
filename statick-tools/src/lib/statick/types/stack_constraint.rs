use super::ConstraintSet;
use std::fmt;

/**
 * These act a lot like type classes (Haskell) or traits (Rust, Scala) but they are called
 * "constraints" here seen as (a) the language doesn't admit introducing new constraints, (b) they
 * only affect a very small number of functions, and (c) the language doesn't support user-defined
 * concrete types, so they won't need implementing for those types.
 */
#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub enum StackConstraint {
    NoConsumableOrDroppableTypes,
    AllowBottom,
    MustBeBase,
}

impl fmt::Display for StackConstraint {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            StackConstraint::NoConsumableOrDroppableTypes => {
                write!(f, "NoConsumableOrDroppableTypes")
            }
            StackConstraint::AllowBottom => write!(f, "AllowBottom"),
            StackConstraint::MustBeBase => write!(f, "MustBeBase"),
        }
    }
}

pub type StackConstraints = ConstraintSet<StackConstraint>;
