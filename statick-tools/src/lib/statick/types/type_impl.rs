use super::{
    subscripted, ApplyUnifierStep, Constraint, Stack, StackConstraints, TypeAllocator,
    TypeCheckResult, TypeConstraints, TypeError, TypeFmt, UnifierStep,
};
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::ops::Deref;

pub type ChannelVariable = usize;
pub type ChannelVariableOffset = usize;

#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub enum ChannelUse {
    Infinity,
    Constant(ChannelVariableOffset),
    Variable(ChannelVariable, ChannelVariableOffset),
}

#[derive(Copy, Clone, Debug, Eq, Hash, PartialEq)]
pub enum Direction {
    Rx,
    Tx,
}

#[derive(Clone, Eq, Hash, PartialEq)]
pub enum Type {
    Boolean,
    Integer,
    Counter(usize),
    Void,
    Channel(ChannelUse, Direction, Box<Type>),
    Generic(usize, TypeConstraints),
    Function(Box<Stack>, Box<Stack>),
}

impl Type {
    pub fn has_constraint(&self, constraint: Constraint) -> bool {
        use ChannelUse::*;
        use Constraint::*;
        use Type::*;
        match self {
            Boolean | Integer | Void | Function(_, _) => match constraint {
                MustConsume => false,
                Droppable | Duplicable => true,
                IntLike => self == &Boolean || self == &Integer,
            },
            Counter(_) => constraint == IntLike,
            Channel(chan_use, dir, _) => match chan_use {
                Infinity | Variable(_, _) => false,
                Constant(k) => match constraint {
                    IntLike => false,
                    MustConsume => *k > 0,
                    Duplicable => false,
                    Droppable => *k == 0 && *dir == Direction::Rx, // The sender is deleted with del
                },
            },
            Generic(_, cs) => cs.contains(constraint),
        }
    }

    pub fn check_valid_expression_type(&self) -> TypeCheckResult<()> {
        if let Type::Function(i, o) = self {
            i.check_consumed_types_are_consumed(o)?;
            Ok(())
        } else {
            Err(TypeError::NotAFunction(self.clone()))
        }
    }

    /** Validates that a type stack appears in the left-most position on the left hand side of the
     * function type if and only if it appears in the left-most position on the right hand side of
     * the function type*/
    pub fn check_valid_function_type(&self) -> TypeCheckResult<()> {
        if let Type::Function(i, o) = self {
            if i.contains_stack(&o.get_base_stack()) || *o.deref() == Stack::Bottom {
                return Ok(());
            } else {
                Err(TypeError::InputOutputStacksDontMatch(self.clone()))
            }
        } else {
            Err(TypeError::NotAFunction(self.clone()))
        }
    }

    pub fn contains(&self, a: &Type) -> bool {
        if self == a {
            true
        } else {
            match self {
                // This case would only be true if they were all equal
                Type::Generic(_, _)
                | Type::Boolean
                | Type::Integer
                | Type::Void
                | Type::Counter(_) => false,
                Type::Channel(_, _, c) => c.contains(a),
                Type::Function(i, o) => i.contains(a) || o.contains(a),
            }
        }
    }

    pub fn contains_stack(&self, s: &Stack) -> bool {
        match self {
            Type::Boolean | Type::Integer | Type::Void | Type::Generic(_, _) | Type::Counter(_) => {
                false
            }
            Type::Channel(_, _, t) => t.contains_stack(s),
            Type::Function(i, o) => i.contains_stack(s) || o.contains_stack(s),
        }
    }

    pub fn collect_channel_variables(&self, vars: &mut HashSet<ChannelVariable>) {
        match self {
            Type::Channel(ChannelUse::Variable(n, _), _, t) => {
                vars.insert(*n);
                t.collect_channel_variables(vars);
            }
            Type::Channel(_, _, t) => {
                t.collect_channel_variables(vars);
            }
            Type::Function(i, o) => {
                i.collect_channel_variables(vars);
                o.collect_channel_variables(vars);
            }
            Type::Integer | Type::Boolean | Type::Void | Type::Generic(_, _) | Type::Counter(_) => {
            }
        }
    }

    /**
     * Collects all the variables in this type (if there are none, returns the
     * original type), creates copies of the type variables, then clones the structure
     * in full, but replaces old type variables with new type variables.
     *
     * This copy can the be used for unification and application.
     */
    pub fn deep_clone(&self, alloc: &mut TypeAllocator) -> Type {
        let mut constraints = HashMap::new();
        self.collect_constraints(&mut constraints);
        let mut stack_constraints = HashMap::new();
        self.collect_stack_constraints(&mut stack_constraints);
        let mut generics = vec![];
        let mut stacks = vec![];
        let mut _counters = vec![];
        self.collect_vars(&mut generics, &mut stacks, &mut _counters);
        let mut generic_map = HashMap::new();
        for g in generics {
            let f = alloc.next_generic_type_counter();
            generic_map.insert(g, Type::Generic(f, constraints[&g].clone()));
        }
        let mut stack_map = HashMap::new();
        for s in stacks {
            let c = if let Some(c) = stack_constraints.get(&s) {
                c.clone()
            } else {
                StackConstraints::default()
            };
            // Rust is introducing inner_deref in a future version that will simplify this code
            stack_map.insert(s, alloc.type_stack(c));
        }
        let mut channel_variables = HashSet::new();
        self.collect_channel_variables(&mut channel_variables);
        let mut channel_variable_map = HashMap::new();
        for v in channel_variables {
            let n = alloc.next_channel_var_counter();
            channel_variable_map.insert(v, n);
        }
        struct TypeVisitor {
            generic_map: HashMap<usize, Type>,
            stack_map: HashMap<usize, Stack>,
            channel_variable_map: HashMap<ChannelVariable, ChannelVariable>,
        };
        impl TypeVisitor {
            fn deep_copy_type(&mut self, t: &Type) -> Type {
                match t {
                    Type::Boolean | Type::Integer | Type::Void | Type::Counter(_) => t.clone(),
                    Type::Channel(u, d, c) => Type::Channel(
                        self.deep_copy_channel_use(u),
                        *d,
                        Box::new(self.deep_copy_type(c)),
                    ),
                    Type::Generic(n, _) => self.generic_map[&n].clone(),
                    Type::Function(i, o) => {
                        let new_i = self.deep_copy_stack(&i);
                        let new_o = self.deep_copy_stack(&o);
                        Type::Function(Box::new(new_i), Box::new(new_o))
                    }
                }
            }

            fn deep_copy_stack(&mut self, s: &Stack) -> Stack {
                match s {
                    Stack::Bottom => Stack::Bottom,
                    Stack::Generic(n, _) => self.stack_map[&n].clone(),
                    Stack::Stack(s, t) => {
                        let new_t = self.deep_copy_type(&t);
                        let new_s = self.deep_copy_stack(&s);
                        Stack::Stack(Box::new(new_s), Box::new(new_t))
                    }
                }
            }

            fn deep_copy_channel_use(&mut self, u: &ChannelUse) -> ChannelUse {
                match u {
                    ChannelUse::Constant(_) | ChannelUse::Infinity => *u,
                    ChannelUse::Variable(n, o) => {
                        ChannelUse::Variable(self.channel_variable_map[n], *o)
                    }
                }
            }
        }
        let mut visitor = TypeVisitor {
            generic_map,
            stack_map,
            channel_variable_map,
        };
        visitor.deep_copy_type(self)
    }
}

impl TypeFmt for Type {
    fn collect_vars(
        &self,
        generics: &mut Vec<usize>,
        stacks: &mut Vec<usize>,
        counters: &mut Vec<usize>,
    ) {
        match self {
            Type::Integer | Type::Boolean | Type::Void => {}
            Type::Counter(n) => counters.push(*n),
            Type::Generic(n, _) => generics.push(*n),
            Type::Channel(_, _, c) => c.collect_vars(generics, stacks, counters),
            Type::Function(i, o) => {
                i.collect_vars(generics, stacks, counters);
                o.collect_vars(generics, stacks, counters);
            }
        }
    }

    fn collect_constraints(&self, constraint_map: &mut HashMap<usize, TypeConstraints>) {
        match self {
            Type::Generic(n, cs) => {
                constraint_map.insert(*n, cs.clone());
            }
            Type::Channel(_, _, c) => c.collect_constraints(constraint_map),
            Type::Function(i, o) => {
                i.collect_constraints(constraint_map);
                o.collect_constraints(constraint_map);
            }
            Type::Integer | Type::Boolean | Type::Void | Type::Counter(_) => {}
        }
    }

    fn collect_stack_constraints(&self, constraint_map: &mut HashMap<usize, StackConstraints>) {
        match self {
            Type::Channel(_, _, c) => c.collect_stack_constraints(constraint_map),
            Type::Function(i, o) => {
                i.collect_stack_constraints(constraint_map);
                o.collect_stack_constraints(constraint_map);
            }
            Type::Generic(_, _) | Type::Integer | Type::Boolean | Type::Void | Type::Counter(_) => {
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
        stack_constraint_map: &HashMap<usize, StackConstraints>,
        generics_order: &[usize],
        stack_order: &[usize],
    ) -> fmt::Result {
        match self {
            Type::Void => write!(f, "void"),
            Type::Integer => write!(f, "int"),
            Type::Boolean => write!(f, "bool"),
            Type::Counter(n) => write!(f, "counter{}", subscripted(counters[n])),
            Type::Generic(n, _) => write!(f, "{}", generics[n]),
            Type::Channel(chan_use, direction, c) => {
                match direction {
                    Direction::Rx => write!(f, "Rx")?,
                    Direction::Tx => write!(f, "Tx")?,
                };
                match chan_use {
                    ChannelUse::Infinity => {}
                    ChannelUse::Constant(k) => {
                        write!(f, "({})", *k)?;
                    }
                    ChannelUse::Variable(name, ops) => {
                        write!(f, "(n{}", subscripted(*name))?;
                        if *ops > 0 {
                            write!(f, "+{}", *ops)?;
                        }
                        write!(f, ")")?;
                    }
                }
                write!(f, " ")?;
                c.fmt_with_generics_and_stacks(
                    f,
                    generics,
                    stacks,
                    counters,
                    false,
                    constraint_map,
                    stack_constraint_map,
                    generics_order,
                    stack_order,
                )
            }
            Type::Function(i, o) => {
                // Print the list of generic variables. This will always be non-empty because
                // there will always be a generic stack variable at the front of the stack
                if !top_level {
                    write!(f, "(")?;
                }
                write!(f, "∀ ")?;
                let mut printed_stacks = HashSet::new();
                for s in stack_order {
                    if (i.contains_generic_stack_at_top_level(*s)
                        || o.contains_generic_stack_at_top_level(*s))
                        && !printed_stacks.contains(s)
                    {
                        write!(f, "{}", stacks[s])?;
                        if let Some(c) = stack_constraint_map.get(s) {
                            if !c.is_empty() {
                                write!(f, " : {}", c)?;
                            }
                        }
                        write!(f, " . ")?;
                        printed_stacks.insert(*s);
                    }
                }
                let mut printed_generics = HashSet::new();
                for g in generics_order {
                    if (i.contains_generic_type_at_top_level(*g)
                        || o.contains_generic_type_at_top_level(*g))
                        && !printed_generics.contains(g)
                    {
                        write!(f, "{}", generics[g])?;
                        let constraints = &constraint_map[g];
                        if !constraints.is_empty() {
                            write!(f, " : {}", constraints)?;
                        }
                        write!(f, " . ")?;
                        printed_generics.insert(*g);
                    }
                }
                i.fmt_with_generics_and_stacks(
                    f,
                    generics,
                    stacks,
                    counters,
                    false,
                    constraint_map,
                    stack_constraint_map,
                    generics_order,
                    stack_order,
                )?;
                write!(f, " → ")?;
                o.fmt_with_generics_and_stacks(
                    f,
                    generics,
                    stacks,
                    counters,
                    false,
                    constraint_map,
                    stack_constraint_map,
                    generics_order,
                    stack_order,
                )?;
                if top_level {
                    Ok(())
                } else {
                    write!(f, ")")
                }
            }
        }
    }
}

impl ApplyUnifierStep for Type {
    fn apply_unifier_step(&self, step: &UnifierStep) -> Self {
        match self {
            Type::Channel(chan_use, dir, c) => {
                // The unifier step could change the inner type, so we apply that first
                let new_c = c.apply_unifier_step(step);
                // Then deal with if it is a channel unifier
                let new_u = if let UnifierStep::Channel(replace_n, replacement) = step {
                    match chan_use {
                        // These cannot be replaced
                        ChannelUse::Infinity | ChannelUse::Constant(_) => *chan_use,
                        ChannelUse::Variable(name, ops) => {
                            if *name == *replace_n {
                                match replacement {
                                    ChannelUse::Infinity => ChannelUse::Infinity,
                                    ChannelUse::Constant(k) => ChannelUse::Constant(*k + *ops),
                                    ChannelUse::Variable(new_n, new_ops) => {
                                        ChannelUse::Variable(*new_n, *ops + *new_ops)
                                    }
                                }
                            } else {
                                *chan_use
                            }
                        }
                    }
                } else {
                    *chan_use
                };
                // The direction never changes during unification
                Type::Channel(new_u, *dir, Box::new(new_c))
            }
            Type::Generic(m, _) => {
                if let UnifierStep::Type(n, new_t) = step {
                    if *m == *n {
                        new_t.clone()
                    } else {
                        self.clone()
                    }
                } else {
                    self.clone()
                }
            }
            Type::Function(i, o) => {
                let new_i = i.apply_unifier_step(step);
                let new_o = o.apply_unifier_step(step);
                Type::Function(Box::new(new_i), Box::new(new_o))
            }
            Type::Integer | Type::Boolean | Type::Void | Type::Counter(_) => self.clone(),
        }
    }
}

impl fmt::Debug for Type {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_debug(f)
    }
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_display(f)
    }
}
