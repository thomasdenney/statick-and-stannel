use super::{
    ChannelUse, Constraint, ConstraintSet, Stack, StackConstraint, StackConstraints, Type,
    TypeCheckResult, TypeError, Unifier, UnifierStep,
};
use std::collections::HashSet;
use std::ops::Deref;

pub fn of_types(a: &Type, b: &Type) -> TypeCheckResult<Unifier> {
    visit_types(a, b, Unifier::default())
}

pub fn of_stacks(a: &Stack, b: &Stack) -> TypeCheckResult<Unifier> {
    visit_stacks(a, b, Unifier::default())
}

fn visit_types(a: &Type, b: &Type, mut unifier: Unifier) -> TypeCheckResult<Unifier> {
    match (a, b) {
        (Type::Channel(u1, d1, c_a), Type::Channel(u2, d2, c_b)) => {
            unifier = visit_channel_use(u1, u2, unifier)?;
            if d1 == d2 {
                visit_types(c_a, c_b, unifier)
            } else {
                Err(TypeError::NonUnifiableTypes(a.clone(), b.clone()))
            }
        }
        (Type::Function(i_a, o_a), Type::Function(i_b, o_b)) => {
            let new_unifier = visit_stacks(o_a, o_b, Unifier::default())?;
            let i_a = new_unifier.apply(i_a.deref());
            let i_b = new_unifier.apply(i_b.deref());
            unifier.compose(new_unifier);
            visit_stacks(&i_a, &i_b, unifier)
        }
        (Type::Generic(n, cs), _) => {
            if !b.contains(a) {
                let step = match b {
                    Type::Generic(b_n, b_cs) => {
                        let mut new_cs = cs.clone();
                        new_cs.union(b_cs);
                        let new_t = Type::Generic(*b_n, new_cs);
                        UnifierStep::Type(*n, new_t)
                    }
                    _ => {
                        let mut missing = HashSet::new();
                        for c in &cs.constraints {
                            if !b.has_constraint(*c) {
                                missing.insert(*c);
                            }
                        }

                        if missing.len() == 1 && missing.contains(&Constraint::Droppable) {
                            if let Type::Channel(ChannelUse::Variable(n, o), _, _) = b {
                                if *o == 0 {
                                    unifier.add(UnifierStep::Channel(*n, ChannelUse::Constant(0)));
                                    return Ok(unifier);
                                } else {
                                    let constraints = ConstraintSet::new(missing);
                                    return Err(TypeError::MissingConstraints(
                                        a.clone(),
                                        b.clone(),
                                        constraints,
                                    ));
                                }
                            } else {
                                let constraints = ConstraintSet::new(missing);
                                return Err(TypeError::MissingConstraints(
                                    a.clone(),
                                    b.clone(),
                                    constraints,
                                ));
                            }
                        }

                        if missing.is_empty() {
                            UnifierStep::Type(*n, b.clone())
                        } else {
                            let constraints = ConstraintSet::new(missing);
                            return Err(TypeError::MissingConstraints(
                                a.clone(),
                                b.clone(),
                                constraints,
                            ));
                        }
                    }
                };
                unifier.add(step);
                Ok(unifier)
            } else if a == b {
                Ok(unifier)
            } else {
                Err(TypeError::NonUnifiableTypes(a.clone(), b.clone()))
            }
        }
        (_, Type::Generic(_, _)) => {
            // Symmetry is achieved by swapping the parameters
            visit_types(b, a, unifier)
        }
        _ => {
            if a == b {
                Ok(unifier)
            } else {
                Err(TypeError::NonUnifiableTypes(a.clone(), b.clone()))
            }
        }
    }
}

fn visit_stacks(a: &Stack, b: &Stack, mut unifier: Unifier) -> TypeCheckResult<Unifier> {
    match (a, b) {
        (Stack::Generic(n, cs), _) => {
            if !b.contains_stack(a) {
                let mut missing = StackConstraints::default();
                for c in &cs.constraints {
                    if !b.satisfies_stack_constraint(*c) {
                        println!("{} doesn't satisfy {}", b, c);
                        missing.insert(*c);
                    }
                }
                if let Stack::Bottom = b {
                    if !cs.constraints.contains(&StackConstraint::AllowBottom) {
                        return Err(TypeError::BottomNotAllowed(a.clone(), b.clone()));
                    }
                    // Doesn't matter if there are missing constraints; we can just union the
                    // constraints.
                    if !missing.is_empty() {
                        panic!("");
                    }
                } else if !missing.is_empty() {
                    return Err(TypeError::MissingStackConstraints(
                        a.clone(),
                        b.clone(),
                        missing,
                    ));
                }
                let mut merge_stack = b.clone();
                merge_stack.add_constraints(cs.clone());
                unifier.add(UnifierStep::Stack(*n, merge_stack));
                Ok(unifier)
            } else if a == b {
                Ok(unifier)
            } else {
                Err(TypeError::NonUnifiableStacks(a.clone(), b.clone()))
            }
        }
        (_, Stack::Generic(_, _)) => visit_stacks(b, a, unifier),
        (Stack::Stack(b_a, t_a), Stack::Stack(b_b, t_b)) => {
            let new_unifier = visit_types(t_a, t_b, Unifier::default())?;
            let b_a = new_unifier.apply(b_a.deref());
            let b_b = new_unifier.apply(b_b.deref());
            unifier.compose(new_unifier);
            visit_stacks(&b_a, &b_b, unifier)
        }
        (Stack::Bottom, Stack::Bottom) => Ok(unifier),
        (Stack::Bottom, _) | (_, Stack::Bottom) => {
            Err(TypeError::NonUnifiableStacks(a.clone(), b.clone()))
        }
    }
}

#[allow(clippy::many_single_char_names)]
fn visit_channel_use(
    a: &ChannelUse,
    b: &ChannelUse,
    mut unifier: Unifier,
) -> TypeCheckResult<Unifier> {
    if a == b {
        return Ok(unifier);
    }
    match (a, b) {
        (ChannelUse::Infinity, ChannelUse::Infinity) => Ok(unifier),
        (ChannelUse::Constant(n1), ChannelUse::Constant(n2)) => {
            if *n1 == *n2 {
                Ok(unifier)
            } else {
                Err(TypeError::NonUnifiableChannelUses(*a, *b))
            }
        }
        (ChannelUse::Variable(n, o), _) => {
            let repl = match b {
                ChannelUse::Infinity => ChannelUse::Infinity,
                ChannelUse::Constant(k) => {
                    if *k >= *o {
                        ChannelUse::Constant(*k - *o)
                    } else {
                        return Err(TypeError::NonUnifiableChannelUses(*a, *b));
                    }
                }
                ChannelUse::Variable(n2, o2) => {
                    if n == n2 {
                        ChannelUse::Infinity
                    } else {
                        ChannelUse::Variable(*n2, *o2)
                    }
                }
            };
            unifier.add(UnifierStep::Channel(*n, repl));
            Ok(unifier)
        }
        (_, ChannelUse::Variable(_, _)) => visit_channel_use(b, a, unifier),
        (ChannelUse::Infinity, ChannelUse::Constant(_))
        | (ChannelUse::Constant(_), ChannelUse::Infinity) => {
            Err(TypeError::NonUnifiableChannelUses(*a, *b))
        }
    }
}
