use super::{subscripted, ChannelUse, Stack, StackConstraints, Type, TypeConstraints};
use std::collections::HashSet;
use std::error::Error;
use std::fmt;

#[derive(Debug, Eq, PartialEq)]
pub enum TypeError {
    DuplicateName(String),
    UnknownName(String),
    ExpressionMissingType,
    AlreadyHasMapping(Type, Type, Type),
    NonUnifiableTypes(Type, Type),
    MissingConstraints(Type, Type, TypeConstraints),
    MissingStackConstraints(Stack, Stack, StackConstraints),
    NonUnifiableStacks(Stack, Stack),
    NonUnifiableChannelUses(ChannelUse, ChannelUse),
    BottomNotAllowed(Stack, Stack),
    BadMain(Type),
    UndefinedMain,
    InputOutputStacksDontMatch(Type),
    NotAFunction(Type),
    ConsumedTypesWerentConsumed(Stack, Stack, HashSet<Type>),
    NameHasNoParameter(String, u16),
    CantUseExhaustedChannel,
    EmptyAlternationsNotAllowed,
    RepeatZero,
}

impl fmt::Display for TypeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            TypeError::DuplicateName(n) => write!(f, "{} is already defined", n),
            TypeError::UnknownName(n) => {
                write!(f, "{} is not defined in the global environment", n)
            }
            TypeError::ExpressionMissingType => {
                write!(f, "Expression was not annotated with a type")
            }
            TypeError::AlreadyHasMapping(from, to, new) => write!(
                f,
                "Already has mapping {} -> {}, can't replace with {} -> {}",
                from, to, from, new
            ),
            TypeError::NonUnifiableTypes(a, b) => write!(f, "Can't unify {} with {}", a, b),
            TypeError::MissingConstraints(a, b, cs) => write!(
                f,
                "Can't unify {} with {} because it is missing {}",
                a, b, cs
            ),
            TypeError::MissingStackConstraints(a, b, cs) => write!(
                f,
                "Can't unify stack {} with {} because it is missing {}",
                a, b, cs
            ),
            TypeError::NonUnifiableStacks(a, b) => write!(f, "Can't unify {} with {}", a, b),
            TypeError::BottomNotAllowed(a, b) => {
                write!(f, "Can't unify {} with {} because bottom not allowed", a, b)
            }
            TypeError::NonUnifiableChannelUses(a, b) => {
                write!(f, "Can't unify channel use {:?} with {:?}", a, b)
            }
            TypeError::UndefinedMain => write!(f, "main is not defined"),
            TypeError::BadMain(t) => write!(
                f,
                "main should be a function that takes no arguments, not {}",
                t
            ),
            TypeError::InputOutputStacksDontMatch(t) => write!(
                f,
                "The input and output types of {} for it to be a valid function",
                t
            ),
            TypeError::NotAFunction(t) => write!(f, "Attempt to use type {} as a function type", t),
            TypeError::ConsumedTypesWerentConsumed(i, o, ts) => {
                let mut iter = ts.iter();
                write!(f, "{:?}", iter.next().unwrap())?;
                for t in iter {
                    write!(f, ", {:?}", t)?;
                }
                write!(
                    f,
                    " occur(s) in {} and {} but should have been consumed",
                    i, o
                )
            }
            TypeError::NameHasNoParameter(n, k) => write!(
                f,
                "{} has no numeric parameter; can't call as {}{}",
                n,
                n,
                subscripted(k)
            ),
            TypeError::CantUseExhaustedChannel => write!(f, "Can't use an exhausted channel"),
            TypeError::EmptyAlternationsNotAllowed => {
                write!(f, "Empty alternations are not permitted")
            }
            TypeError::RepeatZero => write!(f, "Repeat must be for more than zero occurrences"),
        }
    }
}

impl Error for TypeError {}

pub type TypeCheckResult<T> = Result<T, TypeError>;
