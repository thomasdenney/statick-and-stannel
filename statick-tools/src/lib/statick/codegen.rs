use super::ast::*;
use crate::{Condition, FunctionOp, Instruction, Op, ProcessOp, StackOp};

use std::cell::{RefCell, RefMut};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;
use std::ops::Deref;

mod optimizer;

#[derive(Debug)]
pub enum CodegenError {}
pub type CodegenResult<T> = Result<T, CodegenError>;

impl fmt::Display for CodegenError {
    fn fmt(&self, _f: &mut fmt::Formatter) -> fmt::Result {
        Ok(())
    }
}

pub fn codegen(program: Program) -> CodegenResult<String> {
    Ok(CodeGenerator::flatten(&codegen_blocks(program)?))
}

// This function is just used for testing
fn codegen_blocks(program: Program) -> CodegenResult<Vec<Block>> {
    CodeGenerator::new(program).codegen()
}

#[derive(Default)]
struct CodeGenerator {
    declarations: HashMap<String, RefCell<Declaration>>,
    label_counter: RefCell<LabelCounter>,
}

impl CodeGenerator {
    fn new(program: Program) -> CodeGenerator {
        let mut declarations = HashMap::new();
        for decl in program.declarations {
            declarations.insert(decl.name.to_string(), RefCell::new(decl));
        }
        CodeGenerator {
            declarations,
            ..CodeGenerator::default()
        }
    }

    fn codegen(&mut self) -> CodegenResult<Vec<Block>> {
        self.optimise_ast()?;
        self.label_terms()?;
        let blocks = self.assemble_program()?;
        let mut blocks = self.collapse_adjacent_blocks(blocks)?;
        for block in &mut blocks {
            block.tokens = optimizer::peephole(&block.tokens);
        }
        Ok(blocks)
    }

    /**
     * NOTE: This compiler is not intended to produce optimal code! In conjunction with the
     * peephole optimiser in the assembler it will produce code that is *very* similar to the
     * higher-level Statick, but there are certain concepts that could certainly be more efficient.
     */
    fn optimise_ast(&mut self) -> CodegenResult<()> {
        self.rename_quoted_standard_library_functions()?;
        Ok(())
    }

    fn rename_quoted_standard_library_functions(&mut self) -> CodegenResult<()> {
        struct Visitor<'a> {
            new_declarations: HashMap<String, RefCell<Declaration>>,
            declarations: &'a HashMap<String, RefCell<Declaration>>,
        }
        impl<'a> AstVisitor<CodegenError> for Visitor<'a> {
            fn visit_named_term_ref(&mut self, name: &str, k: Option<u16>) -> CodegenResult<()> {
                if !self.declarations.contains_key(name) {
                    // Then it is a standard library function
                    let new_name = CodeGenerator::name_for_quoted_term(name, k);
                    let e = ExpressionType::NamedTermApp(name.to_string(), k);
                    // Don't need to perform type checking here
                    let e = Expression {
                        expression: e,
                        e_type: None,
                    };
                    let t = Term {
                        expressions: vec![e],
                        ..Term::default()
                    };
                    let d = Declaration {
                        name: new_name.to_string(),
                        term: Box::new(t),
                    };
                    self.new_declarations
                        .insert(new_name.to_string(), RefCell::new(d));
                }
                Ok(())
            }
        }

        let mut visitor = Visitor {
            new_declarations: HashMap::new(),
            declarations: &self.declarations,
        };
        for decl in self.declarations.values() {
            visitor.visit_term(&decl.borrow().term)?;
        }
        let new_decls = visitor.new_declarations;
        self.declarations.extend(new_decls);
        Ok(())
    }

    fn name_for_quoted_term(name: &str, k: Option<u16>) -> String {
        match k {
            Some(k) => format!("'{}_{}", name, k),
            None => format!("'{}_0", name),
        }
    }

    fn label_terms(&mut self) -> CodegenResult<()> {
        struct Visitor<'a> {
            counter: RefMut<'a, LabelCounter>,
        }

        impl<'a> MutAstVisitor<CodegenError> for Visitor<'a> {
            fn visit_declaration(&mut self, decl: &mut Declaration) -> CodegenResult<()> {
                decl.term.label = Some(format!("f_{}", decl.name));
                self.visit_term(&mut decl.term)
            }

            fn visit_term(&mut self, term: &mut Term) -> CodegenResult<()> {
                if term.label.is_none() {
                    term.label = Some(self.counter.next());
                }
                for expr in &mut term.expressions {
                    self.visit_expression(expr)?;
                }
                Ok(())
            }
        }

        let mut visitor = Visitor {
            counter: self.label_counter.borrow_mut(),
        };
        for decl in self.declarations.values() {
            visitor.visit_declaration(&mut decl.borrow_mut())?;
        }

        Ok(())
    }

    fn assemble_program(&self) -> CodegenResult<Vec<Block>> {
        let mut all_blocks = vec![];
        all_blocks.extend(self.assemble_declaration(&self.declarations["main"].borrow())?);
        for (name, decl) in &self.declarations {
            if name != "main" {
                all_blocks.extend(self.assemble_declaration(&decl.borrow())?);
            }
        }

        struct Visitor<'a> {
            blocks: Vec<Block>,
            gen: &'a CodeGenerator,
        }

        impl<'a> AstVisitor<CodegenError> for Visitor<'a> {
            fn visit_anonymous_term(&mut self, term: &Term) -> CodegenResult<()> {
                let (new_blocks, _) = (self.gen.assemble_term(term, true, &None, &None, &None))?;
                self.blocks.extend(new_blocks);
                Ok(())
            }
        }

        let mut vis = Visitor {
            blocks: vec![],
            gen: self,
        };
        for decl in self.declarations.values() {
            vis.visit_declaration(&decl.borrow())?;
        }
        all_blocks.extend(vis.blocks);
        Ok(all_blocks)
    }

    fn flatten(blocks: &[Block]) -> String {
        let mut result = String::new();
        for block in blocks {
            result.push_str(&format!("{}", block));
        }
        result
    }

    fn assemble_declaration(&self, decl: &Declaration) -> CodegenResult<Vec<Block>> {
        let (mut blocks, _) = self.assemble_term(decl.term.deref(), true, &None, &None, &None)?;
        blocks[0].comment = Some(match decl.term.t_type.as_ref() {
            None => decl.name.to_string(),
            Some(t) => format!("{} :: {}", decl.name, t),
        });
        Ok(blocks)
    }

    fn assemble_term(
        &self,
        term: &Term,
        as_function: bool,
        exit_label: &Option<String>,
        true_label: &Option<String>,
        false_label: &Option<String>,
    ) -> CodegenResult<(Vec<Block>, bool)> {
        let mut blocks = Vec::new();
        let mut block = Block::default();
        block.label = term.label.clone();
        blocks.push(block);

        let mut assembled_as_conditional = false;

        for (i, expr) in term.expressions.iter().enumerate() {
            let is_last = i == term.expressions.len() - 1;
            let as_function = is_last && as_function;
            let exit_label = if is_last { &exit_label } else { &None };
            let true_label = if is_last { true_label } else { &None };
            let false_label = if is_last { false_label } else { &None };
            let (new_blocks, used_conditionals) =
                self.assemble_expression(&expr, as_function, exit_label, true_label, false_label)?;
            blocks.extend(new_blocks);
            assembled_as_conditional = used_conditionals;
        }

        if term.expressions.is_empty() {
            let mut block = Block::default();
            CodeGenerator::extend_with_exit(&mut block, as_function, exit_label);
            blocks.push(block)
        }

        Ok((blocks, assembled_as_conditional))
    }

    fn assemble_expression(
        &self,
        expr: &Expression,
        as_function: bool,
        exit_label: &Option<String>,
        true_label: &Option<String>,
        false_label: &Option<String>,
    ) -> CodegenResult<(Vec<Block>, bool)> {
        use Condition::*;
        use ExpressionType::*;
        use FunctionOp::*;
        use Instruction::*;
        use Op::*;
        use ProcessOp::*;
        use StackOp::*;

        let mut block = Block::default();

        match &expr.expression {
            Number(n) => {
                block.push(Token::N(*n));
            }
            Offset(n) => {
                block.push(Token::N(*n));
                block.push(Token::I(ReadLocal));
            }
            NamedTermRef(name, k) => {
                block.push(Token::L(format!(
                    "f_{}",
                    match self.declarations.get(name) {
                        None => CodeGenerator::name_for_quoted_term(name, *k),
                        Some(n) => n.borrow().name.to_string(),
                    }
                )));
            }
            NamedTermApp(name, k) => {
                let k = match k {
                    Some(k) => *k,
                    None => 0,
                };
                match name.as_ref() {
                    "true" => block.push(Token::N(1)),
                    "false" => block.push(Token::N(0)),
                    "apply" => block.push(Token::I(Function(Call))),
                    "swap" => block.push(Token::I(Stack(Swap))),
                    "dup" => block.push(Token::I(Stack(Dup))),
                    "drop" => block.push(Token::I(Stack(Drop))),
                    "tuck" => block.push(Token::I(Stack(Tuck))),
                    "rot" => block.push(Token::I(Stack(Rot))),
                    "chan" => {
                        block.push(Token::I(Process(CreateChannel)));
                        block.push(Token::I(Stack(Dup)));
                    }
                    "proc" => {
                        block.push(Token::N(k));
                        block.push(Token::I(Process(Start)));
                    }
                    "?" => {
                        if k > 0 {
                            block.push(Token::N(k));
                            block.push(Token::I(ReadLocal));
                        }
                        block.push(Token::I(Process(Receive)));
                        if k > 0 {
                            block.push(Token::I(Stack(Swap)));
                            block.push(Token::I(Stack(Drop)));
                        }
                    }
                    "!" => {
                        if k > 0 {
                            block.push(Token::N(k));
                            block.push(Token::I(ReadLocal));
                            block.push(Token::I(Stack(Swap)));
                        }
                        block.push(Token::I(Process(Send)));
                        if k > 0 {
                            block.push(Token::I(Stack(Drop)))
                        }
                    }
                    "del" => {
                        if k > 0 {
                            block.push(Token::N(k));
                            block.push(Token::I(ReadLocal));
                        }
                        block.push(Token::I(Process(DestroyChannel)));
                    }
                    "not" => {
                        block.push(Token::I(ArithmeticOrLogic(LogicalNot)));
                        // This is to ensure only the least significant bit is used
                        block.push(Token::N(1));
                        block.push(Token::I(ArithmeticOrLogic(LogicalAnd)));
                    }
                    "and" => block.push(Token::I(ArithmeticOrLogic(LogicalAnd))),
                    "or" => block.push(Token::I(ArithmeticOrLogic(LogicalOr))),
                    "+" => block.push(Token::I(ArithmeticOrLogic(Add))),
                    "-" => block.push(Token::I(ArithmeticOrLogic(Sub))),
                    "." => {}
                    "toInt" => block.push(Token::I(Stack(Dup))),
                    "==" | "!=" | "<=" | ">=" | "<" | ">" => {
                        let cond = match name.as_ref() {
                            "==" => ZeroEqual,
                            "!=" => NotZeroNotEqual,
                            ">=" => UnsignedGreaterOrEqual,
                            "<=" => UnsignedLessOrEqual,
                            "<" => UnsignedLess,
                            ">" => UnsignedGreater,
                            _ => panic!("Unknown condition function {}", name),
                        };
                        let mut cmp_block = Block::default();
                        cmp_block.push(Token::I(ArithmeticOrLogic(Compare)));
                        if let Some(true_label) = true_label {
                            cmp_block.push(Token::L(true_label.to_string()));
                            cmp_block.push(Token::I(Jump(cond)));
                            return Ok((vec![cmp_block], true));
                        } else if let Some(false_label) = false_label {
                            cmp_block.push(Token::L(false_label.to_string()));
                            cmp_block.push(Token::I(Jump(cond.invert())));
                            return Ok((vec![cmp_block], true));
                        } else {
                            let true_label = self.fresh_label();
                            cmp_block.push(Token::I(ArithmeticOrLogic(Compare)));

                            cmp_block.push(Token::N(0));
                            CodeGenerator::extend_with_exit(
                                &mut cmp_block,
                                as_function,
                                exit_label,
                            );
                            let mut true_block = Block::default();
                            true_block.label = Some(true_label);
                            true_block.push(Token::N(1));
                            CodeGenerator::extend_with_exit(
                                &mut true_block,
                                as_function,
                                exit_label,
                            );
                            return Ok((vec![cmp_block, true_block], false));
                        }
                    }
                    _ => {
                        block.push(Token::L(format!("f_{}", name)));
                        block.push(Token::I(Function(Call)));
                    }
                }
            }
            Forever(block) => {
                return self.assemble_term(block, false, &block.label, &None, &None);
            }
            Repeat(n, body) => {
                let mut blocks = vec![];

                let check_label = self.fresh_label();
                let mut start_block = Block::default();
                start_block.push(Token::N(0));
                blocks.push(start_block);
                let (body_blocks, _) =
                    self.assemble_term(body, false, &Some(check_label.to_string()), &None, &None)?;
                blocks.extend(body_blocks);

                let mut check_block = Block::default();
                check_block.label = Some(check_label);
                check_block.push(Token::N(1));
                check_block.push(Token::I(ArithmeticOrLogic(Add)));
                check_block.push(Token::I(Stack(Dup)));
                check_block.push(Token::N(*n));
                check_block.push(Token::I(ArithmeticOrLogic(Compare)));
                check_block.push(Token::L(body.label.clone().unwrap()));
                check_block.push(Token::I(Jump(NotZeroNotEqual)));
                check_block.push(Token::I(Stack(Drop)));
                CodeGenerator::extend_with_exit(&mut check_block, as_function, exit_label);
                blocks.push(check_block);
                return Ok((blocks, false));
            }
            If(condition, true_branch, false_branch) => {
                let needs_fresh_exit_label = exit_label.is_none() && !as_function;
                let exit_label = if needs_fresh_exit_label {
                    Some(self.fresh_label())
                } else {
                    exit_label.clone()
                };
                let mut blocks = vec![];
                let jump_label = Some(self.fresh_label());
                let (condition_blocks, no_need_for_jump_block) =
                    self.assemble_term(condition, false, &jump_label, &None, &false_branch.label)?;
                blocks.extend(condition_blocks);

                if !no_need_for_jump_block {
                    let mut jump_block = Block::default();
                    jump_block.label = jump_label;
                    jump_block.push(Token::N(0));
                    jump_block.push(Token::I(ArithmeticOrLogic(Compare)));
                    jump_block
                        .tokens
                        .push(Token::L(false_branch.label.clone().unwrap()));
                    jump_block.push(Token::I(Jump(ZeroEqual)));
                    blocks.push(jump_block);
                }

                let (true_blocks, _) =
                    self.assemble_term(true_branch, as_function, &exit_label, &None, &None)?;
                blocks.extend(true_blocks);
                let (false_blocks, _) =
                    self.assemble_term(false_branch, as_function, &exit_label, &None, &None)?;
                blocks.extend(false_blocks);

                if needs_fresh_exit_label {
                    let mut exit_block = Block::default();
                    exit_block.label = exit_label;
                    blocks.push(exit_block);
                }

                return Ok((blocks, false));
            }
            While(condition, body) => {
                // Compiles so that only a single conditional branch is required each iteration
                let mut blocks = vec![];
                let mut init_jump = Block::default();
                init_jump.push(Token::L(condition.label.clone().unwrap()));
                init_jump.push(Token::I(Jump(Always)));
                blocks.push(init_jump);

                let check_label = Some(self.fresh_label());
                let (condition_blocks, _) =
                    self.assemble_term(body, false, &condition.label, &None, &None)?;
                blocks.extend(condition_blocks);
                let (check_blocks, no_need_for_check_block) =
                    self.assemble_term(condition, false, &check_label, &body.label, &None)?;
                blocks.extend(check_blocks);

                if !no_need_for_check_block {
                    let mut check_block = Block::default();
                    check_block.label = check_label;
                    check_block.push(Token::N(0));
                    check_block.push(Token::I(ArithmeticOrLogic(Compare)));
                    check_block.push(Token::L(body.label.clone().unwrap()));
                    check_block.push(Token::I(Jump(NotZeroNotEqual)));
                    blocks.push(check_block);
                }

                let mut end_block = Block::default();
                CodeGenerator::extend_with_exit(&mut end_block, as_function, exit_label);
                blocks.push(end_block);
                return Ok((blocks, false));
            }
            Alternation(arms) => {
                let mut alt_initialisation = Block::default();
                alt_initialisation.push(Token::I(Process(AlternationStart)));

                for arm in arms {
                    alt_initialisation.push(Token::N(arm.offset));
                    alt_initialisation.push(Token::I(ReadLocal));
                    alt_initialisation.push(Token::I(Process(EnableChannel)));
                }

                alt_initialisation.push(Token::I(Process(AlternationWait)));

                for arm in arms {
                    alt_initialisation.push(Token::L(arm.term.label.clone().unwrap()));
                    alt_initialisation.push(Token::N(arm.offset + 1));
                    alt_initialisation.push(Token::I(ReadLocal));
                    alt_initialisation.push(Token::I(Process(DisableChannel)));
                }

                alt_initialisation.push(Token::I(Process(AlternationEnd)));

                let mut blocks = vec![alt_initialisation];

                let needs_fresh_exit_label = exit_label.is_none() && !as_function;
                let exit_label = if needs_fresh_exit_label {
                    Some(self.fresh_label())
                } else {
                    exit_label.clone()
                };

                for arm in arms {
                    let (new_blocks, _) =
                        self.assemble_term(&arm.term, as_function, &exit_label, &None, &None)?;
                    blocks.extend(new_blocks);
                }

                return Ok((blocks, false));
            }
            AnonymousTerm(t) => block.push(Token::L(t.label.clone().unwrap())),
        }
        CodeGenerator::extend_with_exit(&mut block, as_function, exit_label);

        Ok((vec![block], false))
    }

    fn extend_with_exit(block: &mut Block, as_function: bool, exit_label: &Option<String>) {
        use Condition::*;
        use FunctionOp::*;
        use Instruction::*;
        if as_function {
            block.push(Token::I(Function(Return)));
        } else if let Some(exit_label) = exit_label {
            block.push(Token::L(exit_label.to_string()));
            block.push(Token::I(Jump(Always)))
        }
    }

    fn fresh_label(&self) -> String {
        self.label_counter.borrow_mut().next()
    }

    fn collapse_adjacent_blocks(&self, blocks: Vec<Block>) -> CodegenResult<Vec<Block>> {
        // TODO: Make this generic
        #[derive(Debug)]
        enum Entry {
            Value(String),
            Index(usize),
        };
        #[derive(Default, Debug)]
        struct UnionFind {
            table: Vec<Entry>,
            mapping: HashMap<String, usize>,
        };
        impl UnionFind {
            fn add(&mut self, s: &str) {
                if !self.mapping.contains_key(s) {
                    self.mapping.insert(s.to_string(), self.table.len());
                    self.table.push(Entry::Value(s.to_string()));
                }
            }

            fn find(&mut self, s: &str) -> String {
                let mut to_update = VecDeque::default();
                let mut i = self.mapping[s];
                while let Entry::Index(new_i) = &self.table[i] {
                    to_update.push_back(i);
                    i = *new_i;
                }
                while let Some(j) = to_update.pop_front() {
                    self.table[j] = Entry::Index(i)
                }
                self.mapping.insert(s.to_string(), i);
                if let Entry::Value(s) = &self.table[i] {
                    s.to_string()
                } else {
                    panic!("Should have been a string");
                }
            }

            fn union(&mut self, s1: &str, s2: &str) {
                let i1 = self.mapping[s1];
                let i2 = self.mapping[s2];
                if i1 != i2 {
                    self.table[i2] = Entry::Index(i1);
                }
            }
        }

        // An earlier pass determines if functions are ever referred to; they aren't compiled
        let mut used_labels = HashSet::new();
        for block in &blocks {
            for tok in &block.tokens {
                if let Token::L(l) = tok {
                    used_labels.insert(l.to_string());
                }
            }
        }

        // Firstly collapse blocks without labels
        let mut collapsed_blocks = vec![];
        for block in blocks {
            if collapsed_blocks.is_empty()
                || (block.label.is_some() && used_labels.contains(block.label.as_ref().unwrap()))
            {
                collapsed_blocks.push(block);
            } else {
                let i = collapsed_blocks.len() - 1;
                collapsed_blocks[i].tokens.extend(block.tokens);
            }
        }

        // Union any blocks that immediately jump somewhere else
        let mut block_sets = UnionFind::default();
        for (i, block) in collapsed_blocks.iter().enumerate() {
            block_sets.add(block.label.as_ref().unwrap());
            if block.tokens.len() >= 2 {
                if let Token::L(l) = &block.tokens[0] {
                    if let Token::I(Instruction::Jump(Condition::Always)) = &block.tokens[1] {
                        block_sets.add(l); // Won't be inserted if already present
                        block_sets.union(block.label.as_ref().unwrap(), l);
                    }
                }
            } else if block.tokens.len() == 0 && i < collapsed_blocks.len() - 1 {
                block_sets.add(collapsed_blocks[i + 1].label.as_ref().unwrap());
                block_sets.union(
                    block.label.as_ref().unwrap(),
                    collapsed_blocks[i + 1].label.as_ref().unwrap(),
                );
            }
        }

        let mut max_lens = vec![];

        // Remove any jumps to the next block
        for (i, block) in collapsed_blocks.iter().enumerate() {
            let mut new_cap = block.tokens.len();
            if i < collapsed_blocks.len() - 1 && block.tokens.len() > 1 {
                for j in 1..block.tokens.len() {
                    if let Token::L(l) = &block.tokens[j - 1] {
                        if let Token::I(Instruction::Jump(Condition::Always)) = &block.tokens[j] {
                            if block_sets.find(l)
                                == block_sets.find(collapsed_blocks[i + 1].label.as_ref().unwrap())
                                && block_sets.find(l)
                                    != block_sets.find(block.label.as_ref().unwrap())
                            {
                                new_cap = j - 1;
                                break;
                            }
                        }
                    }
                    if let Token::I(Instruction::Function(FunctionOp::Return)) = &block.tokens[j] {
                        new_cap = j + 1;
                    }
                }
            }
            max_lens.push(new_cap);
        }

        let mut new_blocks = vec![];
        for (i, block) in collapsed_blocks.iter().enumerate() {
            let mut new_block = Block::default();
            new_block.comment = block.comment.clone();
            new_block.label = Some(block_sets.find(block.label.as_ref().unwrap()));
            for (j, tok) in block.tokens.iter().enumerate() {
                if j < max_lens[i] {
                    if let Token::L(l) = tok {
                        new_block.push(Token::L(block_sets.find(l)));
                    } else {
                        new_block.push(tok.clone());
                    }
                } else {
                    break;
                }
            }
            if new_block.tokens.len() > 0 {
                new_blocks.push(new_block);
            }
        }

        Ok(new_blocks)
    }
}

#[derive(Default)]
struct LabelCounter {
    counter: usize,
}

impl LabelCounter {
    pub fn next(&mut self) -> String {
        let n = self.counter;
        self.counter += 1;
        format!("l_{}", n) // Safe because names can't include _ in Statick
    }
}

#[derive(Default, Debug, Eq, PartialEq)]
struct Block {
    comment: Option<String>,
    label: Option<String>,
    tokens: Vec<Token>,
}

impl Block {
    fn push(&mut self, token: Token) {
        self.tokens.push(token);
    }
}

impl fmt::Display for Block {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        if let Some(comment) = &self.comment {
            writeln!(f, "# {}", comment)?;
        }
        if let Some(label) = &self.label {
            writeln!(f, "{}:", label)?;
        }
        for token in &self.tokens {
            writeln!(f, "  {}", token)?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Token {
    N(u16),
    L(String),
    I(Instruction),
}

impl fmt::Display for Token {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Token::N(n) => write!(f, "{}", n),
            Token::L(s) => write!(f, "{}", s),
            Token::I(i) => write!(f, "{}", i),
        }
    }
}

#[cfg(test)]
mod test;
