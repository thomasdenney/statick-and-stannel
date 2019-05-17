use std::collections::HashSet;
use std::fmt;
use std::hash::{Hash, Hasher};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConstraintSet<T: Clone + Copy + fmt::Debug + Hash + Eq + PartialEq> {
    pub constraints: HashSet<T>,
}

impl<T: Clone + Copy + fmt::Debug + Eq + Hash + PartialEq> ConstraintSet<T> {
    pub fn new(constraints: HashSet<T>) -> ConstraintSet<T> {
        ConstraintSet { constraints }
    }

    pub fn insert(&mut self, constraint: T) {
        self.constraints.insert(constraint);
    }

    pub fn is_empty(&self) -> bool {
        self.constraints.is_empty()
    }

    pub fn contains(&self, constraint: T) -> bool {
        self.constraints.contains(&constraint)
    }

    pub fn union(&mut self, other: &ConstraintSet<T>) {
        for c in &other.constraints {
            self.insert(c.clone())
        }
    }
}

impl<T: Clone + Copy + fmt::Debug + Hash + Eq + PartialEq> Default for ConstraintSet<T> {
    fn default() -> Self {
        ConstraintSet::new(HashSet::new())
    }
}

#[allow(clippy::derive_hash_xor_eq)]
impl<T: Clone + Copy + fmt::Debug + Hash + Eq + PartialEq> Hash for ConstraintSet<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        for c in &self.constraints {
            c.hash(state)
        }
    }
}

impl<T: Clone + Copy + fmt::Debug + fmt::Display + Hash + Eq + PartialEq> fmt::Display
    for ConstraintSet<T>
{
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let mut first = true;
        for c in &self.constraints {
            if !first {
                write!(f, " + ")?;
            }
            first = false;
            write!(f, "{}", c)?;
        }
        Ok(())
    }
}
