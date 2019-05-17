use super::{
    ApplyUnifierStep, ChannelVariable, Constraint, StackConstraint, StackConstraints, Type, TypeAllocator,
    TypeCheckResult, TypeConstraints, TypeError, TypeFmt, UnifierStep,
};
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::ops::Deref;

#[derive(Clone, Eq, Hash, PartialEq)]
pub enum Stack {
    Bottom,
    Generic(usize, StackConstraints),
    Stack(Box<Stack>, Box<Type>),
}

impl Stack {
    pub fn contains_generic_type_at_top_level(&self, n: usize) -> bool {
        match self {
            Stack::Bottom => false,
            Stack::Generic(_, _) => false,
            Stack::Stack(s, t) => {
                if let Type::Generic(m, _) = t.deref() {
                    if *m == n {
                        return true;
                    }
                }
                s.contains_generic_type_at_top_level(n)
            }
        }
    }

    pub fn contains_generic_stack_at_top_level(&self, n: usize) -> bool {
        match self {
            Stack::Bottom => false,
            Stack::Generic(m, _) => *m == n,
            Stack::Stack(s, _) => s.contains_generic_stack_at_top_level(n),
        }
    }

    pub fn contains(&self, a: &Type) -> bool {
        match self {
            Stack::Bottom => false,
            Stack::Generic(_, _) => false,
            Stack::Stack(s, t) => t.contains(a) || s.contains(a),
        }
    }

    pub fn contains_stack(&self, a: &Stack) -> bool {
        if a == self {
            true
        } else {
            match self {
                Stack::Bottom => false,
                Stack::Generic(_, _) => false,
                Stack::Stack(b, t) => b.contains_stack(a) || t.contains_stack(a),
            }
        }
    }

    pub fn contains_consumed_types(&self) -> bool {
        match self {
            Stack::Bottom => false,
            Stack::Generic(_, _) => false,
            Stack::Stack(b, t) => {
                t.has_constraint(Constraint::MustConsume) || b.contains_consumed_types()
            }
        }
    }

    pub fn satisfies_stack_constraint(&self, c: StackConstraint) -> bool {
        match self {
            Stack::Bottom => true,
            Stack::Generic(_, _) => true,
            Stack::Stack(b, t) => match c {
                StackConstraint::NoConsumableOrDroppableTypes => {
                    !t.has_constraint(Constraint::MustConsume)
                        && t.has_constraint(Constraint::Droppable)
                        && b.satisfies_stack_constraint(c)
                }
                StackConstraint::AllowBottom => b.satisfies_stack_constraint(c),
                StackConstraint::MustBeBase => false,
            },
        }
    }

    pub fn add_constraints(&mut self, c: StackConstraints) {
        match self {
            Stack::Bottom => {} // TODO: Test if this is correct
            Stack::Generic(_, cs) => cs.union(&c),
            Stack::Stack(b, _) => b.add_constraints(c),
        }
    }

    pub fn get_base_stack(&self) -> Stack {
        let mut s = self.clone();
        while let Stack::Stack(new_s, _) = s {
            s = *new_s;
        }
        s
    }

    // TODO: By calling the other method during unification, I think this method is redundant
    pub fn check_consumed_types_are_consumed(&self, right: &Stack) -> TypeCheckResult<()> {
        struct Visitor<'a> {
            unconsumed_types: HashSet<Type>,
            right: &'a Stack,
        };
        impl<'a> Visitor<'a> {
            fn visit_stack(&mut self, stack: &Stack) {
                match stack {
                    Stack::Generic(_, _) | Stack::Bottom => {}
                    Stack::Stack(s, t) => {
                        self.visit_stack(s);
                        self.visit_type(t);
                    }
                }
            }

            fn visit_type(&mut self, t: &Type) {
                // Importantly, there is no need to recurse down into types here
                if t.has_constraint(Constraint::MustConsume) && self.right.contains(t) {
                    self.unconsumed_types.insert(t.clone());
                }
            }
        }
        let mut visitor = Visitor {
            unconsumed_types: HashSet::new(),
            right,
        };
        visitor.visit_stack(self);
        if visitor.unconsumed_types.is_empty() {
            Ok(())
        } else {
            Err(TypeError::ConsumedTypesWerentConsumed(
                self.clone(),
                right.clone(),
                visitor.unconsumed_types,
            ))
        }
    }

    pub fn collect_channel_variables(&self, vars: &mut HashSet<ChannelVariable>) {
        match self {
            Stack::Stack(b, t) => {
                b.collect_channel_variables(vars);
                t.collect_channel_variables(vars);
            }
            Stack::Bottom | Stack::Generic(_, _) => {}
        }
    }

    pub fn deep_clone(&self, alloc: &mut TypeAllocator) -> Stack {
        // The implementation of this method is a hack: it creates a new function type, clones
        // that, and returns the stack.
        let in_s = alloc.type_stack(StackConstraints::default());
        let f_t = Type::Function(Box::new(in_s), Box::new(self.clone()));
        if let Type::Function(_, deep_clone) = f_t.deep_clone(alloc) {
            deep_clone.deref().clone()
        } else {
            panic!("Type of function after deep clone did not match");
        }
    }
}

impl ApplyUnifierStep for Stack {
    fn apply_unifier_step(&self, step: &UnifierStep) -> Self {
        match self {
            Stack::Bottom => Stack::Bottom,
            Stack::Generic(m, _) => {
                if let UnifierStep::Stack(n, new_s) = step {
                    if *m == *n {
                        new_s.clone()
                    } else {
                        self.clone()
                    }
                } else {
                    self.clone()
                }
            }
            Stack::Stack(b, t) => {
                let new_b = b.apply_unifier_step(step);
                let new_t = t.apply_unifier_step(step);
                Stack::Stack(Box::new(new_b), Box::new(new_t))
            }
        }
    }
}

impl fmt::Debug for Stack {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_debug(f)
    }
}
impl fmt::Display for Stack {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_display(f)
    }
}

impl TypeFmt for Stack {
    fn collect_vars(&self, generics: &mut Vec<usize>, stacks: &mut Vec<usize>, counters: &mut Vec<usize>) {
        match self {
            Stack::Bottom => {}
            Stack::Generic(n, _) => stacks.push(*n),
            Stack::Stack(b, t) => {
                b.collect_vars(generics, stacks, counters);
                t.collect_vars(generics, stacks, counters);
            }
        }
    }

    fn collect_constraints(&self, constraint_map: &mut HashMap<usize, TypeConstraints>) {
        match self {
            Stack::Bottom => {}
            Stack::Stack(b, t) => {
                t.collect_constraints(constraint_map);
                b.collect_constraints(constraint_map);
            }
            Stack::Generic(_, _) => {}
        }
    }

    fn collect_stack_constraints(&self, constraint_map: &mut HashMap<usize, StackConstraints>) {
        match self {
            Stack::Bottom => {}
            Stack::Stack(b, t) => {
                t.collect_stack_constraints(constraint_map);
                b.collect_stack_constraints(constraint_map);
            }
            Stack::Generic(n, cs) => {
                constraint_map.insert(*n, cs.clone());
            }
        }
    }

    fn fmt_with_generics_and_stacks(
        &self,
        f: &mut fmt::Formatter,
        generics: &HashMap<usize, String>,
        stacks: &HashMap<usize, String>,
        counters: &HashMap<usize, usize>,
        top_level: bool,
        constraint_map: &HashMap<usize, TypeConstraints>,
        stack_constraints: &HashMap<usize, StackConstraints>,
        generics_order: &[usize],
        stack_order: &[usize],
    ) -> fmt::Result {
        match self {
            Stack::Bottom => write!(f, "⊥"),
            Stack::Generic(n, _) => write!(f, "{}", stacks[n]),
            Stack::Stack(b, t) => {
                b.fmt_with_generics_and_stacks(
                    f,
                    generics,
                    stacks,
                    counters,
                    top_level,
                    constraint_map,
                    stack_constraints,
                    generics_order,
                    stack_order,
                )?;
                write!(f, " × ")?;
                t.fmt_with_generics_and_stacks(
                    f,
                    generics,
                    stacks,
                    counters,
                    false,
                    constraint_map,
                    stack_constraints,
                    generics_order,
                    stack_order,
                )
            }
        }
    }
}
