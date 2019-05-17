use super::ast::{
    AlternationArm, AstVisitor, Declaration, Expression, ExpressionType, MutAstVisitor, Program,
    Term,
};

use std::collections::{HashMap, HashSet};
use std::ops::Deref;

mod constraint;
mod constraint_set;
mod mgu;
mod stack;
mod stack_constraint;
mod subscript;
mod type_alloc;
mod type_error;
mod type_fmt;
mod type_impl;
mod unifier;

pub use constraint::{Constraint, TypeConstraints};
pub use constraint_set::ConstraintSet;
pub use stack::Stack;
pub use stack_constraint::{StackConstraint, StackConstraints};
pub use subscript::subscripted;
pub use type_alloc::TypeAllocator;
pub use type_error::{TypeCheckResult, TypeError};
pub use type_fmt::TypeFmt;
pub use type_impl::{ChannelUse, ChannelVariable, ChannelVariableOffset, Direction, Type};
pub use unifier::{ApplyUnifierStep, Unifier, UnifierStep};

pub fn type_check(program: &mut Program) -> TypeCheckResult<()> {
    TypeChecker::default().check(program)
}

#[derive(Default)]
struct TypeChecker {
    environment: HashMap<String, Type>,
    alloc: TypeAllocator,
}

impl TypeChecker {
    fn check(&mut self, program: &mut Program) -> TypeCheckResult<()> {
        self.elaborate_standard_library()?;
        self.check_for_duplicate_names(program)?;
        self.annotate_declarations_with_generic_type(program)?;
        let topo_order = self.sort_definitions_topologically(program)?;
        self.annotate(program, topo_order)?;
        self.check_inferred_types_match(program)?;
        self.check_main_takes_empty_stack()?;
        Ok(())
    }

    fn elaborate_standard_library(&mut self) -> TypeCheckResult<()> {
        self.add_func("true", vec![], vec![Type::Boolean])?;
        self.add_func("false", vec![], vec![Type::Boolean])?;

        {
            let a = self.alloc.generic_type();
            let b = self.alloc.generic_type();
            self.add_func("swap", vec![a.clone(), b.clone()], vec![b, a])?;
        }

        {
            let a = self
                .alloc
                .generic_type_with_constraints(vec![Constraint::Duplicable].into_iter());
            self.add_func("dup", vec![a.clone()], vec![a.clone(), a])?;
        }

        {
            let a = self
                .alloc
                .generic_type_with_constraints(vec![Constraint::Droppable].into_iter());
            self.add_func("drop", vec![a], vec![])?;
        }

        {
            // TODO: Check that this is the correct way round
            let a = self.alloc.generic_type();
            let b = self.alloc.generic_type();
            let c = self.alloc.generic_type();
            self.add_func("tuck", vec![a.clone(), b.clone(), c.clone()], vec![b, c, a])?;
        }

        {
            // TODO: Check that this is the correct way round
            let a = self.alloc.generic_type();
            let b = self.alloc.generic_type();
            let c = self.alloc.generic_type();
            self.add_func("rot", vec![a.clone(), b.clone(), c.clone()], vec![c, a, b])?;
        }

        {
            let a = self
                .alloc
                .generic_type_with_constraints(vec![Constraint::IntLike].into_iter());
            self.add_func("toInt", vec![a.clone()], vec![a, Type::Integer])?;
        }

        self.add_func(".", vec![], vec![])?;

        {
            // if :: S * (S -> a bool) * (a -> b) * (a -> b) -> b
            // We create a diferent stack because the condition function can have side effects,
            // but the top of its stack must be a bool.
            let original_stack = self.alloc.type_stack(StackConstraints::default()); // S
            let new_stack = self.alloc.type_stack(StackConstraints::default()); // a
            let result = self.alloc.type_stack(StackConstraints::default()); // b
            let condition_result =
                Stack::Stack(Box::new(new_stack.clone()), Box::new(Type::Boolean)); // a bool
            let condition_func_t =
                Type::Function(Box::new(original_stack.clone()), Box::new(condition_result)); // S -> a bool
            let true_branch_t =
                Type::Function(Box::new(new_stack.clone()), Box::new(result.clone())); // a -> b
            let false_branch_t =
                Type::Function(Box::new(new_stack.clone()), Box::new(result.clone())); // a -> b

            let input_t =
                Stack::Stack(Box::new(original_stack.clone()), Box::new(condition_func_t));
            let input_t = Stack::Stack(Box::new(input_t), Box::new(true_branch_t));
            let input_t = Stack::Stack(Box::new(input_t), Box::new(false_branch_t));

            let if_t = Type::Function(Box::new(input_t), Box::new(result));
            self.add_to_environment("if", if_t, true)?;
        }

        {
            // while :: S * (S -> S * bool) -> (S -> S) -> S
            let s = self.alloc.type_stack(StackConstraints::default());
            let condition_t = self
                .alloc
                .function_type(s.clone(), vec![], vec![Type::Boolean]);
            let body_t = self.alloc.function_type(s.clone(), vec![], vec![]);
            let while_t = self
                .alloc
                .function_type(s, vec![condition_t, body_t], vec![]);
            self.add_to_environment("while", while_t, false)?;
        }

        {
            // forever :: S * (S -> S) -> ⊥
            let s = self.alloc.type_stack(StackConstraints::default());
            let body_t = self.alloc.function_type(s.clone(), vec![], vec![]);
            let input = Stack::Stack(Box::new(s), Box::new(body_t));
            let output = Stack::Bottom;
            let forever_t = Type::Function(Box::new(input), Box::new(output));
            self.add_to_environment("forever", forever_t, false)?;
        }

        self.add_func("+", vec![Type::Integer, Type::Integer], vec![Type::Integer])?;
        self.add_func("-", vec![Type::Integer, Type::Integer], vec![Type::Integer])?;
        self.add_func(">", vec![Type::Integer, Type::Integer], vec![Type::Boolean])?;
        self.add_func(
            ">=",
            vec![Type::Integer, Type::Integer],
            vec![Type::Boolean],
        )?;
        self.add_func("<", vec![Type::Integer, Type::Integer], vec![Type::Boolean])?;
        self.add_func(
            "<=",
            vec![Type::Integer, Type::Integer],
            vec![Type::Boolean],
        )?;
        self.add_func(
            "==",
            vec![Type::Integer, Type::Integer],
            vec![Type::Boolean],
        )?;
        self.add_func(
            "!=",
            vec![Type::Integer, Type::Integer],
            vec![Type::Boolean],
        )?;
        self.add_func(
            "and",
            vec![Type::Boolean, Type::Boolean],
            vec![Type::Boolean],
        )?;
        self.add_func(
            "or",
            vec![Type::Boolean, Type::Boolean],
            vec![Type::Boolean],
        )?;
        self.add_func("not", vec![Type::Boolean], vec![Type::Boolean])?;

        let apply_type = self.alloc.apply_type();
        self.add_to_environment("apply", apply_type, true)?;

        Ok(())
    }

    fn check_for_duplicate_names(&self, program: &Program) -> TypeCheckResult<()> {
        let mut names = HashSet::new();
        for decl in &program.declarations {
            if names.contains(&decl.name) {
                return Err(TypeError::DuplicateName(decl.name.to_string()));
            }
            names.insert(decl.name.to_string());
        }
        Ok(())
    }

    fn annotate_declarations_with_generic_type(
        &mut self,
        program: &mut Program,
    ) -> TypeCheckResult<()> {
        for decl in &program.declarations {
            let mut constraints = StackConstraints::default();
            if decl.name == "main" {
                constraints.insert(StackConstraint::NoConsumableOrDroppableTypes);
            }
            let input_t = self.alloc.type_stack(constraints.clone());
            constraints.insert(StackConstraint::AllowBottom);
            let output_t = self.alloc.type_stack(constraints);
            let func_t = Type::Function(Box::new(input_t), Box::new(output_t));
            self.add_to_environment(&decl.name, func_t, true)?;
        }
        Ok(())
    }

    fn sort_definitions_topologically<'a>(
        &self,
        program: &'a Program,
    ) -> TypeCheckResult<Vec<usize>> {
        struct Visitor<'a, 'b> {
            order: Vec<String>,
            visited: HashSet<String>,
            program: &'a Program,
            declarations: HashMap<String, usize>,
            environment: &'b HashMap<String, Type>,
        }

        impl<'a, 'b> Visitor<'a, 'b> {
            fn visit_name(&mut self, name: &str, _k: Option<u16>) -> TypeCheckResult<()> {
                match self.declarations.get(name) {
                    Some(idx) => self.visit_declaration(&self.program.declarations[*idx]),
                    None => {
                        // Check if it is in the standard library
                        if self.environment.contains_key(name)
                            // Standard library functions that can be parameterised with numbers
                            // See |get_environment_type|
                            || name == "chan"
                            || name == "proc"
                            || name == "?"
                            || name == "!"
                            || name == "del"
                        {
                            Ok(())
                        } else {
                            Err(TypeError::UnknownName(name.to_string()))
                        }
                    }
                }
            }
        }

        impl<'a, 'b> AstVisitor<TypeError> for Visitor<'a, 'b> {
            fn visit_declaration(&mut self, decl: &Declaration) -> TypeCheckResult<()> {
                if !self.visited.contains(&decl.name) {
                    self.visited.insert(decl.name.to_string());
                    self.visit_term(&decl.term)?;
                    self.order.push(decl.name.to_string());
                }
                Ok(())
            }

            fn visit_named_term_ref(&mut self, name: &str, k: Option<u16>) -> TypeCheckResult<()> {
                self.visit_name(name, k)
            }

            fn visit_named_term_app(&mut self, name: &str, k: Option<u16>) -> TypeCheckResult<()> {
                self.visit_name(name, k)
            }
        }

        let order = Vec::new();
        let visited = HashSet::new();
        let mut declarations = HashMap::new();
        for (i, decl) in program.declarations.iter().enumerate() {
            declarations.insert(decl.name.to_string(), i);
        }
        let environment = &self.environment;

        let mut visitor = Visitor {
            order,
            visited,
            program,
            declarations,
            environment,
        };
        visitor.visit_program(program)?;

        let Visitor {
            order: order_names,
            declarations,
            ..
        } = visitor;

        let mut order = Vec::new();
        for order_name in order_names {
            order.push(declarations[&order_name]);
        }

        Ok(order)
    }

    fn annotate<'a>(
        &'a mut self,
        program: &mut Program,
        topo_order: Vec<usize>,
    ) -> TypeCheckResult<()> {
        struct Visitor<'a> {
            checker: &'a mut TypeChecker,
        }

        impl<'a> Visitor<'a> {
            fn visit_program_topologically(
                &mut self,
                program: &mut Program,
                topo_order: Vec<usize>,
            ) -> TypeCheckResult<()> {
                // Visit declarations in the order found in the previous stage
                for i in topo_order {
                    self.visit_declaration(&mut program.declarations[i])?;
                    let name = program.declarations[i].name.to_string();
                    let t = program.declarations[i]
                        .term
                        .t_type
                        .as_ref()
                        .unwrap()
                        .clone();
                    self.checker.add_to_environment(&name, t, false)?;
                }
                Ok(())
            }
        }

        impl<'a> MutAstVisitor<TypeError> for Visitor<'a> {
            fn visit_term(&mut self, term: &mut Term) -> TypeCheckResult<()> {
                let s = self.checker.alloc.type_stack(StackConstraints::default());
                let mut t = Type::Function(Box::new(s.clone()), Box::new(s));
                let mut unifier = Unifier::default();

                for mut expr in &mut term.expressions {
                    self.visit_expression(&mut expr)?;
                    let e_type = expr.e_type.as_ref().unwrap();
                    let (new_t, u) = self.checker.type_after_application(&t, &e_type)?;
                    new_t.check_valid_expression_type()?;
                    t = new_t;
                    unifier.compose(u);
                }

                // All expressions that appear within this term get updated with their final
                // concrete term for the function. Note that this may still be in term of type
                // variables, so the concrete term wouldn't be known until propagated down from the
                // start of the program. The language was design so that even programs that use
                // parametric polymorphism only need a single compilation of each function ---
                // there is never any need to monomorphise functions.
                for mut expr in &mut term.expressions {
                    expr.e_type = Some(unifier.apply(expr.e_type.as_ref().unwrap()));
                }

                term.t_type = Some(t);

                Ok(())
            }

            fn visit_expression(&mut self, expr: &mut Expression) -> TypeCheckResult<()> {
                match &mut expr.expression {
                    ExpressionType::Number(_) => {
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        expr.e_type = Some(self.checker.alloc.function_type(
                            s,
                            vec![],
                            vec![Type::Integer],
                        ));
                    }
                    ExpressionType::Offset(k) => {
                        expr.e_type = Some(self.checker.alloc.offset_type(*k));
                    }
                    ExpressionType::NamedTermApp(n, k) => {
                        let t = self
                            .checker
                            .get_environment_type(&n, *k)?
                            .deep_clone(&mut self.checker.alloc);
                        expr.e_type = Some(t);
                    }
                    ExpressionType::NamedTermRef(n, k) => {
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let t = self
                            .checker
                            .get_environment_type(&n, *k)?
                            .deep_clone(&mut self.checker.alloc);
                        let push_type_id = self.checker.alloc.function_type(s, vec![], vec![t]);
                        expr.e_type = Some(push_type_id);
                    }
                    ExpressionType::AnonymousTerm(t) => {
                        self.visit_term(t)?;
                        let f_type = t.t_type.as_ref().unwrap();
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let push_type_id =
                            self.checker
                                .alloc
                                .function_type(s, vec![], vec![f_type.clone()]);
                        expr.e_type = Some(push_type_id);
                    }
                    ExpressionType::If(c, t, f) => {
                        self.visit_term(c)?;
                        self.visit_term(t)?;
                        self.visit_term(f)?;
                        let c_type = c.t_type.clone().unwrap();
                        let t_type = t.t_type.clone().unwrap();
                        let f_type = f.t_type.clone().unwrap();
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let if_input_t = self.checker.alloc.function_type(
                            s,
                            vec![],
                            vec![c_type, t_type, f_type],
                        );
                        let if_t = self
                            .checker
                            .get_environment_type("if", None)?
                            .deep_clone(&mut self.checker.alloc);
                        let (result_t, _) =
                            self.checker.type_after_application(&if_input_t, &if_t)?;
                        expr.e_type = Some(result_t);
                    }
                    ExpressionType::While(c, b) => {
                        self.visit_term(c)?;
                        self.visit_term(b)?;
                        let c_type = c.t_type.clone().unwrap();
                        let b_type = b.t_type.clone().unwrap();
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let while_input_t =
                            self.checker
                                .alloc
                                .function_type(s, vec![], vec![c_type, b_type]);
                        let while_t = self
                            .checker
                            .get_environment_type("while", None)?
                            .deep_clone(&mut self.checker.alloc);
                        let (result_t, _) = self
                            .checker
                            .type_after_application(&while_input_t, &while_t)?;
                        expr.e_type = Some(result_t);
                    }
                    ExpressionType::Forever(b) => {
                        self.visit_term(b)?;
                        let b_type = b.t_type.clone().unwrap();
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let forever_input_t =
                            self.checker.alloc.function_type(s, vec![], vec![b_type]);
                        let forever_ft = self.checker.get_environment_type("forever", None)?;
                        let (forever_t, _) = self
                            .checker
                            .type_after_application(&forever_input_t, &forever_ft)?;
                        expr.e_type = Some(forever_t);
                    }
                    ExpressionType::Repeat(k, b) => {
                        if *k == 0 {
                            return Err(TypeError::RepeatZero);
                        }
                        let repeat_t = self.checker.alloc.repeat_type();
                        self.visit_term(b)?;
                        let b_type = b.t_type.clone().unwrap();
                        // Firstly check that one iteration type checks
                        let s = self.checker.alloc.type_stack(StackConstraints::default());
                        let repeat_in_s =
                            Stack::Stack(Box::new(s.clone()), Box::new(b_type.clone()));
                        let repeat_in = Type::Function(Box::new(s), Box::new(repeat_in_s));
                        let _repeat_t =
                            self.checker.type_after_application(&repeat_in, &repeat_t)?;
                        // Secondly check the final type of the stack after k iterations
                        let f_type = b_type.clone();
                        let mut b_type = b_type;
                        let k = *k;
                        for _ in 1..k {
                            let second = f_type.deep_clone(&mut self.checker.alloc);
                            let (new_b_type, _) =
                                self.checker.type_after_application(&b_type, &second)?;
                            b_type = new_b_type;
                        }
                        let (in_stack, out_stack) = if let Type::Function(i, o) = b_type {
                            (i.deref().clone(), o.deref().clone())
                        } else {
                            panic!("Type of body of repeat should be a function");
                        };
                        let s = if let Stack::Stack(s, _) = in_stack {
                            s.deref().clone()
                        } else {
                            panic!();
                        };
                        let new_s = if let Stack::Stack(new_s, _) = out_stack {
                            new_s.deref().clone()
                        } else {
                            panic!();
                        };
                        expr.e_type = Some(Type::Function(Box::new(s), Box::new(new_s)));
                    }
                    ExpressionType::Alternation(arms) => {
                        if arms.is_empty() {
                            return Err(TypeError::EmptyAlternationsNotAllowed);
                        } else {
                            self.visit_arm(&mut arms[0])?;
                            let mut t = arms[0].a_type.as_ref().unwrap().clone();
                            for arm in arms.iter_mut().skip(1) {
                                self.visit_arm(arm)?;
                                t = mgu::of_types(&t, arm.a_type.as_ref().unwrap())?.apply(&t);
                            }
                            expr.e_type = Some(t);
                        }
                    }
                };
                Ok(())
            }

            fn visit_arm(&mut self, arm: &mut AlternationArm) -> TypeCheckResult<()> {
                let v = self.checker.alloc.next_channel_var_counter();
                let (t, rx, _tx) = self
                    .checker
                    .alloc
                    .generic_channel_type(ChannelUse::Variable(v, 1));
                let out_rx = Type::Channel(
                    ChannelUse::Variable(v, 0),
                    Direction::Rx,
                    Box::new(t.clone()),
                );
                let mut channel_read_inputs = vec![rx];
                for _ in 0..arm.offset {
                    channel_read_inputs.push(self.checker.alloc.generic_type());
                }
                let mut channel_read_output = channel_read_inputs.clone();
                channel_read_output[0] = out_rx;
                channel_read_output.push(t);
                let s = self.checker.alloc.type_stack(StackConstraints::default());
                let channel_read_type =
                    self.checker
                        .alloc
                        .function_type(s, channel_read_inputs, channel_read_output);
                self.visit_term(&mut arm.term)?;
                let term_type = &arm.term.t_type.as_ref().unwrap().clone();
                let (a_type, _) = self
                    .checker
                    .type_after_application(&channel_read_type, &term_type)?;
                arm.a_type = Some(a_type);
                Ok(())
            }
        }

        let mut visitor = Visitor { checker: self };
        visitor.visit_program_topologically(program, topo_order)?;

        Ok(())
    }

    fn add_to_environment(
        &mut self,
        name: &str,
        t: Type,
        skip_validation: bool,
    ) -> TypeCheckResult<()> {
        let t = if self.environment.contains_key(name) {
            let existing = self.environment[name].clone();
            mgu::of_types(&t, &existing)?.apply(&t)
        } else {
            t
        };
        if !skip_validation {
            t.check_valid_function_type()?;
        }
        self.environment.insert(name.to_string(), t);
        Ok(())
    }

    fn add_func(&mut self, name: &str, input: Vec<Type>, output: Vec<Type>) -> TypeCheckResult<()> {
        let s = self.alloc.type_stack(StackConstraints::default());
        let t = self.alloc.function_type(s, input, output);
        self.add_to_environment(name, t, false)
    }

    fn get_environment_type(&mut self, name: &str, k: Option<u16>) -> TypeCheckResult<Type> {
        match self.environment.get(name) {
            Some(t) => {
                if let Some(k) = k {
                    Err(TypeError::NameHasNoParameter(name.to_string(), k))
                } else {
                    Ok(t.clone())
                }
            }
            None => match name {
                "proc" => Ok(self.alloc.proc_type(k)),
                "chan" => Ok(self.alloc.chan_type(k)),
                "?" => Ok(self.alloc.receive_type(k.unwrap_or(0))),
                "!" => Ok(self.alloc.send_type(k.unwrap_or(0))),
                "del" => Ok(self.alloc.del_type(k.unwrap_or(0))),
                _ => Err(TypeError::UnknownName(name.to_string())),
            },
        }
    }

    fn type_after_application(
        &mut self,
        lhs: &Type,
        rhs: &Type,
    ) -> TypeCheckResult<(Type, Unifier)> {
        if let Type::Function(left_input, left_output) = lhs {
            if let Type::Function(right_input, right_output) = rhs {
                // Done to verify consumption properties
                let unifier = mgu::of_stacks(left_output, right_input)?;
                let rhs = unifier.apply(rhs);
                struct VisitSubTypes {}
                impl VisitSubTypes {
                    fn visit_stack(&self, stack: &Stack) -> TypeCheckResult<()> {
                        match stack {
                            Stack::Bottom | Stack::Generic(_, _) => Ok(()),
                            Stack::Stack(s, t) => {
                                if let Type::Function(_, _) = t.deref() {
                                    t.check_valid_expression_type()?;
                                }
                                self.visit_stack(s)
                            }
                        }
                    }

                    fn visit_type(&self, t: &Type) -> TypeCheckResult<()> {
                        match t {
                            Type::Function(i, _) => self.visit_stack(i),
                            _ => Ok(()),
                        }
                    }
                }
                VisitSubTypes {}.visit_type(&rhs)?;

                let t = Type::Function(left_input.clone(), right_output.clone());
                Ok((unifier.apply(&t), unifier))
            } else {
                panic!("RHS should always be a function type.");
            }
        } else {
            panic!("Left hand side should always have function type.");
        }
    }

    fn check_main_takes_empty_stack(&self) -> TypeCheckResult<()> {
        let t = match self.environment.get("main") {
            Some(t) => t.clone(),
            None => return Err(TypeError::UndefinedMain),
        };
        if let Type::Function(i, _) = &t {
            if let Stack::Generic(_, _) = i.deref() {
                return Ok(());
            }
        }
        Err(TypeError::BadMain(t))
    }

    fn check_inferred_types_match(&mut self, program: &Program) -> TypeCheckResult<()> {
        struct Visitor<'a> {
            checker: &'a mut TypeChecker,
        }

        impl<'a> Visitor<'a> {
            fn check_types(&mut self, actual: &Type, inferred: &Type) -> TypeCheckResult<()> {
                // Deep clone in case of recursive function
                let inferred = inferred.deep_clone(&mut self.checker.alloc);
                let _u = mgu::of_types(actual, &inferred);
                Ok(())
            }
        }

        impl<'a> AstVisitor<TypeError> for Visitor<'a> {
            fn visit_expression(&mut self, expr: &Expression) -> TypeCheckResult<()> {
                use ExpressionType::*;
                match &expr.expression {
                    Alternation(arms) => self.visit_alternation(arms),
                    AnonymousTerm(term) => self.visit_anonymous_term(term),
                    If(c, t, f) => self.visit_if(c, t, f),
                    While(c, b) => self.visit_while(c, b),
                    Forever(b) => self.visit_forever(b),
                    Repeat(k, b) => self.visit_repeat(*k, b),
                    Number(n) => self.visit_number(*n),
                    Offset(o) => self.visit_offset(*o),
                    NamedTermApp(n, _) => {
                        let t_clone = if let Some(t) = self.checker.environment.get(n) {
                            t.clone()
                        } else {
                            // Ignore standard library functions
                            return Ok(());
                        };
                        self.check_types(&t_clone, expr.e_type.as_ref().unwrap())
                    }
                    NamedTermRef(n, _) => {
                        let t_clone = if let Some(t) = self.checker.environment.get(n) {
                            t.clone()
                        } else {
                            // Ignore standard library functions
                            return Ok(());
                        };
                        let inferred = if let Type::Function(_, o) = expr.e_type.as_ref().unwrap() {
                            if let Stack::Stack(_, t) = o.deref() {
                                t.clone()
                            } else {
                                panic!("Doesn't put a function on stack");
                            }
                        } else {
                            panic!("Expression not a function");
                        };
                        self.check_types(&t_clone, &inferred)
                    }
                }
            }
        }

        let mut visitor = Visitor { checker: self };
        visitor.visit_program(program)
    }
}

#[cfg(test)]
mod test;
