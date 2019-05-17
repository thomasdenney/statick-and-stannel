use super::types::{subscripted, Type};

use std::fmt;
use std::ops::DerefMut;

#[derive(Debug, Default)]
pub struct Program {
    pub declarations: Vec<Declaration>,
}

impl fmt::Display for Program {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        for decl in &self.declarations {
            writeln!(f, "{}", decl)?;
        }
        Ok(())
    }
}

#[derive(Debug)]
pub struct Declaration {
    pub name: String,
    pub term: Box<Term>,
    // Type is derived from the term's type
}

impl fmt::Display for Declaration {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{} = {}", self.name, self.term)
    }
}

#[derive(Eq, Debug, Default, PartialEq)]
pub struct Term {
    pub expressions: Vec<Expression>,
    pub t_type: Option<Type>,
    pub is_run: bool,
    pub is_function: bool,
    pub label: Option<String>,
}

impl fmt::Display for Term {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        if !self.expressions.is_empty() {
            write!(f, "{}", self.expressions[0])?;
            for expr in &self.expressions[1..] {
                write!(f, " {}", expr)?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct Expression {
    pub expression: ExpressionType,
    pub e_type: Option<Type>,
}

impl fmt::Display for Expression {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.expression)
    }
}

#[derive(Debug, Eq, PartialEq)]
pub enum ExpressionType {
    // Numbers are effectively functions, but I don't want 2^16 functions in the standard library
    Number(u16),
    Alternation(Vec<AlternationArm>),
    AnonymousTerm(Box<Term>),
    NamedTermApp(String, Option<u16>),
    NamedTermRef(String, Option<u16>),
    If(Box<Term>, Box<Term>, Box<Term>),
    While(Box<Term>, Box<Term>),
    Forever(Box<Term>),
    Repeat(u16, Box<Term>),
    Offset(u16),
}

impl fmt::Display for ExpressionType {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        use ExpressionType::*;
        match self {
            Number(n) => write!(f, "{}", n),
            Alternation(arms) => {
                write!(f, "[")?;
                if !arms.is_empty() {
                    write!(f, " {}", arms[0])?;
                    for arm in &arms[1..] {
                        write!(f, " | {}", arm)?;
                    }
                }
                write!(f, " ]")
            }
            AnonymousTerm(t) => write!(f, "({})", t),
            NamedTermApp(n, k) | NamedTermRef(n, k) => {
                if let ExpressionType::NamedTermRef(_, _) = self {
                    write!(f, "'")?;
                }
                if let Some(k) = k {
                    write!(f, "{}{}", n, subscripted(*k))
                } else {
                    write!(f, "{}", n)
                }
            }
            If(condition, true_branch, false_branch) => write!(
                f,
                "if {} then {} else {}",
                condition, true_branch, false_branch
            ),
            While(condition, body) => write!(f, "while {} do {}", condition, body),
            Forever(body) => write!(f, "repeat {}", body),
            Repeat(k, body) => write!(f, "repeat{} {}", subscripted(*k), body),
            Offset(x) => write!(f, "@{}", x),
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct AlternationArm {
    pub offset: u16,
    pub term: Box<Term>,
    pub a_type: Option<Type>,
}

impl fmt::Display for AlternationArm {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "@{} -> {}", self.offset, self.term)
    }
}

pub trait AstVisitor<T> {
    fn visit_program(&mut self, program: &Program) -> Result<(), T> {
        for decl in &program.declarations {
            self.visit_declaration(&decl)?;
        }
        Ok(())
    }

    fn visit_declaration(&mut self, decl: &Declaration) -> Result<(), T> {
        self.visit_term(&decl.term)
    }

    fn visit_term(&mut self, term: &Term) -> Result<(), T> {
        for expr in &term.expressions {
            self.visit_expression(&expr)?;
        }
        Ok(())
    }

    fn visit_expression(&mut self, expr: &Expression) -> Result<(), T> {
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
            NamedTermApp(n, k) => self.visit_named_term_app(n, *k),
            NamedTermRef(n, k) => self.visit_named_term_ref(n, *k),
        }
    }

    fn visit_anonymous_term(&mut self, term: &Term) -> Result<(), T> {
        self.visit_term(term)
    }

    fn visit_alternation(&mut self, arms: &[AlternationArm]) -> Result<(), T> {
        for arm in arms {
            self.visit_arm(&arm)?
        }
        Ok(())
    }

    fn visit_if(&mut self, c: &Term, t: &Term, f: &Term) -> Result<(), T> {
        self.visit_term(&c)?;
        self.visit_term(&t)?;
        self.visit_term(&f)
    }

    fn visit_while(&mut self, c: &Term, b: &Term) -> Result<(), T> {
        self.visit_term(&c)?;
        self.visit_term(&b)
    }

    fn visit_forever(&mut self, b: &Term) -> Result<(), T> {
        self.visit_term(b)
    }

    fn visit_repeat(&mut self, _k: u16, b: &Term) -> Result<(), T> {
        self.visit_term(b)
    }

    fn visit_number(&mut self, _n: u16) -> Result<(), T> {
        Ok(())
    }

    fn visit_offset(&mut self, _n: u16) -> Result<(), T> {
        Ok(())
    }

    fn visit_named_term_app(&mut self, _n: &str, _k: Option<u16>) -> Result<(), T> {
        Ok(())
    }
    fn visit_named_term_ref(&mut self, _n: &str, _k: Option<u16>) -> Result<(), T> {
        Ok(())
    }

    fn visit_arm(&mut self, arm: &AlternationArm) -> Result<(), T> {
        self.visit_term(&arm.term)
    }
}

pub trait MutAstVisitor<T> {
    fn visit_program(&mut self, program: &mut Program) -> Result<(), T> {
        for mut decl in &mut program.declarations {
            self.visit_declaration(&mut decl)?;
        }
        Ok(())
    }

    fn visit_declaration(&mut self, decl: &mut Declaration) -> Result<(), T> {
        self.visit_term(&mut decl.term)
    }

    fn visit_term(&mut self, term: &mut Term) -> Result<(), T> {
        for mut expr in &mut term.expressions {
            self.visit_expression(&mut expr)?;
        }
        Ok(())
    }

    fn visit_expression(&mut self, expr: &mut Expression) -> Result<(), T> {
        use ExpressionType::*;
        match &mut expr.expression {
            Alternation(arms) => self.visit_alternation(arms),
            AnonymousTerm(term) => self.visit_anonymous_term(term.deref_mut()),
            If(c, t, f) => self.visit_if(c.deref_mut(), t.deref_mut(), f.deref_mut()),
            While(c, b) => self.visit_while(c.deref_mut(), b.deref_mut()),
            Forever(b) => self.visit_forever(b.deref_mut()),
            Repeat(k, b) => self.visit_repeat(*k, b),
            Number(n) => self.visit_number(*n),
            Offset(o) => self.visit_offset(*o),
            NamedTermApp(n, k) => self.visit_named_term_app(n, *k),
            NamedTermRef(n, k) => self.visit_named_term_ref(n, *k),
        }
    }

    fn visit_anonymous_term(&mut self, term: &mut Term) -> Result<(), T> {
        self.visit_term(term)
    }

    fn visit_alternation(&mut self, arms: &mut Vec<AlternationArm>) -> Result<(), T> {
        for mut arm in arms {
            self.visit_arm(&mut arm)?
        }
        Ok(())
    }

    fn visit_if(
        &mut self,
        c: &mut Term,
        t: &mut Term,
        f: &mut Term,
    ) -> Result<(), T> {
        self.visit_term(c)?;
        self.visit_term(t)?;
        self.visit_term(f)
    }

    fn visit_while(&mut self, c: &mut Term, b: &mut Term) -> Result<(), T> {
        self.visit_term(c)?;
        self.visit_term(b)
    }

    fn visit_repeat(&mut self, _k: u16, b: &mut Term) -> Result<(), T> {
        self.visit_term(b)
    }

    fn visit_forever(&mut self, b: &mut Term) -> Result<(), T> {
        self.visit_term(b)
    }

    fn visit_number(&mut self, _n: u16) -> Result<(), T> {
        Ok(())
    }

    fn visit_offset(&mut self, _n: u16) -> Result<(), T> {
        Ok(())
    }

    fn visit_named_term_app(&mut self, _n: &str, _k: Option<u16>) -> Result<(), T> {
        Ok(())
    }
    fn visit_named_term_ref(&mut self, _n: &str, _k: Option<u16>) -> Result<(), T> {
        Ok(())
    }

    fn visit_arm(&mut self, arm: &mut AlternationArm) -> Result<(), T> {
        self.visit_term(&mut arm.term)
    }
}
