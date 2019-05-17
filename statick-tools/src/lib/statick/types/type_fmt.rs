use std::collections::HashMap;
use std::fmt;

use super::{StackConstraints, TypeConstraints};

#[derive(Eq, PartialEq)]
pub enum Name {
    Greek,
    Original,
}

pub trait TypeFmt {
    fn collect_vars(
        &self,
        generics: &mut Vec<usize>,
        stacks: &mut Vec<usize>,
        counters: &mut Vec<usize>,
    );
    fn collect_constraints(&self, constraint_map: &mut HashMap<usize, TypeConstraints>);
    fn collect_stack_constraints(&self, constraint_map: &mut HashMap<usize, StackConstraints>);

    #[allow(clippy::too_many_arguments)] // There are a lot of look up tables that are needed elsewhere
    fn fmt_with_generics_and_stacks(
        &self,
        f: &mut fmt::Formatter,
        generics: &HashMap<usize, String>,
        stacks: &HashMap<usize, String>,
        counters: &HashMap<usize, usize>,
        top_level: bool,
        constraint_map: &HashMap<usize, TypeConstraints>,
        stack_constraint_map: &HashMap<usize, StackConstraints>,
        generic_order: &[usize],
        stack_order: &[usize],
    ) -> fmt::Result;

    fn fmt_with_mode(&self, f: &mut fmt::Formatter, mode: Name) -> fmt::Result {
        let mut generics = vec![];
        let mut stacks = vec![];
        let mut counters = vec![];
        self.collect_vars(&mut generics, &mut stacks, &mut counters);
        let mut constraints = HashMap::new();
        self.collect_constraints(&mut constraints);
        let mut stack_constraints = HashMap::new();
        self.collect_stack_constraints(&mut stack_constraints);
        let (generic_map, stack_map, counter_map) = name_vars(mode, &generics, &stacks, &counters);
        self.fmt_with_generics_and_stacks(
            f,
            &generic_map,
            &stack_map,
            &counter_map,
            true,
            &constraints,
            &stack_constraints,
            &generics,
            &stacks,
        )
    }

    fn fmt_debug(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_with_mode(f, Name::Original)
    }

    fn fmt_display(&self, f: &mut fmt::Formatter) -> fmt::Result {
        self.fmt_with_mode(f, Name::Greek)
    }
}

fn name_vars(
    mode: Name,
    generics: &[usize],
    stacks: &[usize],
    counters: &[usize],
) -> (
    HashMap<usize, String>,
    HashMap<usize, String>,
    HashMap<usize, usize>,
) {
    let mut generic_map = HashMap::new();
    for g in generics {
        if !generic_map.contains_key(g) {
            if mode == Name::Greek {
                if generic_map.len() < 25 {
                    // 945 is alpha
                    generic_map.insert(
                        *g,
                        std::char::from_u32(945 + generic_map.len() as u32)
                            .unwrap()
                            .to_string(),
                    );
                } else {
                    generic_map.insert(*g, format!("G{}", generic_map.len()));
                }
            } else {
                generic_map.insert(*g, format!("G{}", g));
            }
        }
    }

    let mut stack_map = HashMap::new();
    for stack in stacks {
        if !stack_map.contains_key(stack) {
            if mode == Name::Greek {
                if stack_map.is_empty() {
                    stack_map.insert(*stack, "S".to_string());
                } else if stack_map.len() == 1 {
                    stack_map.insert(*stack, "S'".to_string());
                } else {
                    stack_map.insert(*stack, format!("S{}", stack_map.len()));
                }
            } else {
                stack_map.insert(*stack, format!("S{}", stack));
            }
        }
    }

    let mut counter_map = HashMap::new();
    for counter in counters {
        if !counter_map.contains_key(counter) {
            counter_map.insert(*counter, counter_map.len());
        }
    }
    (generic_map, stack_map, counter_map)
}
