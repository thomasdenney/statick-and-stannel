use super::ast::*;
use super::lexer::{Source, Token, TokenKind};

use std::error::Error;
use std::fmt;

#[derive(Debug)]
pub enum ParserError {
    ExpectedExpressionInIf(Source),
    ExpectedExpressionInWhile(Source),
    ExpectedExpressionInRepeat(Source),
    ExpectedToken(TokenKind),
    UnexpectedToken(Token, TokenKind),
    DisallowedToken(Token),
}

impl fmt::Display for ParserError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            ParserError::ExpectedExpressionInIf(src) => write!(
                f,
                "Expected expression for condition or branch in if on line {}",
                src.line_number
            ),
            ParserError::ExpectedExpressionInWhile(src) => write!(
                f,
                "Expected expression for condition or body in while on line {}",
                src.line_number
            ),
            ParserError::ExpectedExpressionInRepeat(src) => write!(
                f,
                "Expected expression for body of repeat on line {}",
                src.line_number
            ),
            ParserError::ExpectedToken(tok) => write!(f, "Expected {:?} but found EOF", tok),
            ParserError::UnexpectedToken(tok, exp) => write!(
                f,
                "Unexpected {:?} on line {}, expected {:?}",
                tok.kind, tok.source.line_number, exp
            ),
            ParserError::DisallowedToken(tok) => write!(
                f,
                "{:?} at {}, which is not allowed",
                tok.kind, tok.source.line_number
            ),
        }
    }
}

impl Error for ParserError {}

pub type ParserResult<T> = Result<T, ParserError>;

pub fn parse(tokens: &[Token]) -> ParserResult<Program> {
    let iter = tokens.iter();
    let mut parser = Parser { iter };
    parser.parse_program()
}

struct Parser<'a> {
    iter: std::slice::Iter<'a, Token>,
}

impl<'a> Parser<'a> {
    fn parse_program(&mut self) -> ParserResult<Program> {
        let mut program = Program::default();
        program.declarations = self.parse_declaration_list()?;
        Ok(program)
    }

    fn parse_declaration_list(&mut self) -> ParserResult<Vec<Declaration>> {
        let mut declarations = Vec::new();
        while let Some(decl) = self.parse_declaration()? {
            declarations.push(decl);
        }
        Ok(declarations)
    }

    fn parse_declaration(&mut self) -> ParserResult<Option<Declaration>> {
        let name = match self.iter.next() {
            Some(tok) => Parser::token_to_identifier(tok)?,
            None => return Ok(None),
        };
        self.consume(TokenKind::Assign)?;
        let term = Box::new(self.parse_term(true)?);
        let declaration = Declaration { name, term };
        Ok(Some(declaration))
    }

    fn parse_term(&mut self, top_level: bool) -> ParserResult<Term> {
        let expressions = self.parse_expression_list(top_level)?;
        let t_type = None;
        let term = Term {
            expressions,
            t_type,
            ..Term::default()
        };
        Ok(term)
    }

    fn parse_expression_list(&mut self, top_level: bool) -> ParserResult<Vec<Expression>> {
        let mut exprs = Vec::new();
        let mut backtracking_iter = self.iter.clone();
        while let Some(expr) = self.parse_expression()? {
            // we have ident = <new expr list> so we should break out
            if let ExpressionType::NamedTermApp(_, _) = expr.expression {
                let mut iter_copy = self.iter.clone();
                if let Some(tok) = iter_copy.next() {
                    // I.e. we have a new term, so we should break out
                    if tok.kind == TokenKind::Assign {
                        if top_level {
                            break;
                        } else {
                            // Seen as there is only the top level environment, it is an error to
                            // introduce a new definition inside a nested term
                            return Err(ParserError::DisallowedToken(tok.clone()));
                        }
                    }
                }
            }
            exprs.push(expr);
            backtracking_iter = self.iter.clone();
        }
        self.iter = backtracking_iter;
        Ok(exprs)
    }

    fn parse_expression(&mut self) -> ParserResult<Option<Expression>> {
        let backtracking_iter = self.iter.clone();
        if let Some(token) = self.iter.next() {
            let expression = match &token.kind {
                TokenKind::Number(n) => ExpressionType::Number(*n),
                TokenKind::Assign => return Err(ParserError::DisallowedToken(token.clone())),
                TokenKind::Identifier(id) => {
                    let name = id.to_string();
                    let backtracking_iter = self.iter.clone();
                    let n = if self.consume(TokenKind::Underscore).is_ok() {
                        Some(self.consume_number()?)
                    } else {
                        self.iter = backtracking_iter;
                        None
                    };
                    ExpressionType::NamedTermApp(name, n)
                }
                TokenKind::Quote => {
                    if let ExpressionType::NamedTermApp(name, n) =
                        self.parse_expression()?.unwrap().expression
                    {
                        ExpressionType::NamedTermRef(name, n)
                    } else {
                        return Err(ParserError::ExpectedToken(TokenKind::Identifier(
                            "".to_string(),
                        )));
                    }
                }
                TokenKind::OpenParen => {
                    self.iter = backtracking_iter; // Allow the sub-parser to consume (
                    ExpressionType::AnonymousTerm(self.parse_anonymous_term()?)
                }
                TokenKind::OpenSquare => {
                    self.iter = backtracking_iter; // Allow the sub-parser to consume [
                    self.parse_alternation()?
                }
                TokenKind::Offset => {
                    self.iter = backtracking_iter;
                    self.parse_offset()?
                }
                TokenKind::Period => ExpressionType::NamedTermApp(".".to_string(), None),
                TokenKind::If => {
                    let condition = self.parse_anonymous_term()?;
                    self.consume(TokenKind::Then)?;
                    let true_branch = self.parse_anonymous_term()?;
                    self.consume(TokenKind::Else)?;
                    let false_branch = self.parse_anonymous_term()?;

                    ExpressionType::If(condition, true_branch, false_branch)
                }
                TokenKind::While => {
                    let condition = self.parse_anonymous_term()?;
                    self.consume(TokenKind::Do)?;
                    let body = self.parse_anonymous_term()?;
                    ExpressionType::While(condition, body)
                }
                TokenKind::Repeat => {
                    let backtracking_iter = self.iter.clone();
                    if self.consume(TokenKind::Underscore).is_ok() {
                        let n = self.consume_number()?;
                        let body = self.parse_anonymous_term()?;
                        ExpressionType::Repeat(n, body)
                    } else {
                        self.iter = backtracking_iter;
                        let body = self.parse_anonymous_term()?;
                        ExpressionType::Forever(body)
                    }
                }
                TokenKind::CloseSquare => return Ok(None),
                TokenKind::CloseParen => return Ok(None),
                TokenKind::VerticalBar => return Ok(None),
                _ => return Err(ParserError::DisallowedToken(token.clone())),
            };
            let e_type = None;
            let expr = Expression { expression, e_type };
            Ok(Some(expr))
        } else {
            Ok(None)
        }
    }

    fn parse_anonymous_term(&mut self) -> ParserResult<Box<Term>> {
        self.consume(TokenKind::OpenParen)?;
        let term = self.parse_term(false)?;
        self.consume(TokenKind::CloseParen)?;
        Ok(Box::new(term))
    }

    fn parse_offset(&mut self) -> ParserResult<ExpressionType> {
        self.consume(TokenKind::Offset)?;
        let n = self.consume_number()?;
        Ok(ExpressionType::Offset(n))
    }

    fn parse_alternation(&mut self) -> ParserResult<ExpressionType> {
        self.consume(TokenKind::OpenSquare)?;
        let mut list = Vec::new();
        while let Some(branch) = self.parse_alternation_arm()? {
            list.push(branch);
            // Peek ahead, and check that the next token is a |
            let backtracking_iter = self.iter.clone();
            if let Some(token) = self.iter.next() {
                if token.kind != TokenKind::VerticalBar {
                    self.iter = backtracking_iter;
                    break;
                }
            } else {
                return Err(ParserError::ExpectedToken(TokenKind::VerticalBar));
            }
        }
        self.consume(TokenKind::CloseSquare)?;
        Ok(ExpressionType::Alternation(list))
    }

    fn parse_alternation_arm(&mut self) -> ParserResult<Option<AlternationArm>> {
        let backtracking_iter = self.iter.clone();
        let offset = match self.parse_offset() {
            Ok(ExpressionType::Offset(offset)) => offset,
            _ => {
                // In the event of failure we return to the start to allow another parser to
                // attempt parsing that construct (e.g. most likely ])
                self.iter = backtracking_iter;
                return Ok(None);
            }
        };
        self.consume(TokenKind::Arrow)?;
        let term = Box::new(self.parse_term(false)?);
        let a_type = None;
        let arm = AlternationArm {
            offset,
            term,
            a_type,
        };
        Ok(Some(arm))
    }

    fn consume(&mut self, kind: TokenKind) -> ParserResult<Token> {
        match self.iter.next() {
            Some(tok) => {
                if tok.kind == kind {
                    Ok(tok.clone())
                } else {
                    Err(ParserError::UnexpectedToken(tok.clone(), kind))
                }
            }
            None => Err(ParserError::ExpectedToken(kind)),
        }
    }

    fn consume_number(&mut self) -> ParserResult<u16> {
        match self.iter.next() {
            Some(tok) => {
                if let TokenKind::Number(n) = tok.kind {
                    Ok(n)
                } else {
                    Err(ParserError::ExpectedToken(TokenKind::Number(0)))
                }
            }
            None => Err(ParserError::ExpectedToken(TokenKind::Number(0))),
        }
    }

    fn token_to_identifier(token: &Token) -> ParserResult<String> {
        match &token.kind {
            TokenKind::Identifier(id) => Ok(id.to_string()),
            _ => Err(ParserError::UnexpectedToken(
                token.clone(),
                TokenKind::Identifier("".to_string()),
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::lexer::lex;
    use super::*;

    #[test]
    fn parse_empty_program() -> ParserResult<()> {
        let program = parse(&Vec::new())?;
        assert_eq!(program.declarations.len(), 0);
        Ok(())
    }

    #[test]
    fn parse_simple_decl() -> ParserResult<()> {
        let tokens = lex("main = something").unwrap();
        let program = parse(&tokens)?;
        assert_eq!(program.declarations.len(), 1);
        let main = &program.declarations[0];
        assert_eq!(main.name, "main");
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 1);
        assert_eq!(
            main_exprs[0].expression,
            ExpressionType::NamedTermApp("something".to_string(), None)
        );
        Ok(())
    }

    #[test]
    fn parse_simple_program() -> ParserResult<()> {
        let tokens = lex("
            main = 1 2 'hello apply
            hello = swap
            thingy = ('main)
            alternation = [ @0 -> hello | @7 -> other ]
            logic = if (true) then ( thenTrue ) else ( thenFalse )
            makeProc = 0 1 'alternation proc_2
            makeSimplerProc = 'makeProc proc")
        .unwrap();

        let program = parse(&tokens)?;

        assert_eq!(program.declarations.len(), 7);

        let main = &program.declarations[0];
        assert_eq!(main.name, "main");
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 4);
        assert_eq!(ExpressionType::Number(1), main_exprs[0].expression);
        assert_eq!(ExpressionType::Number(2), main_exprs[1].expression);
        assert_eq!(
            ExpressionType::NamedTermRef("hello".to_string(), None),
            main_exprs[2].expression
        );
        assert_eq!(
            ExpressionType::NamedTermApp("apply".to_string(), None),
            main_exprs[3].expression
        );

        let hello = &program.declarations[1];
        assert_eq!(hello.name, "hello");
        let hello_exprs = &hello.term.expressions;
        assert_eq!(hello_exprs.len(), 1);
        assert_eq!(
            ExpressionType::NamedTermApp("swap".to_string(), None),
            hello_exprs[0].expression
        );

        let thingy = &program.declarations[2];
        assert_eq!(thingy.name, "thingy");
        let thingy_exprs = &thingy.term.expressions;
        assert_eq!(thingy_exprs.len(), 1);
        if let ExpressionType::AnonymousTerm(t) = &thingy_exprs[0].expression {
            assert_eq!(t.expressions.len(), 1);
        } else {
            panic!("Not an anonymous term");
        }

        let alternation = &program.declarations[3];
        assert_eq!(alternation.name, "alternation");
        let alternation_exprs = &alternation.term.expressions;
        assert_eq!(alternation_exprs.len(), 1);
        if let ExpressionType::Alternation(arms) = &alternation_exprs[0].expression {
            assert_eq!(arms.len(), 2);
            assert_eq!(arms[0].offset, 0);
            assert_eq!(arms[0].term.expressions.len(), 1);
            assert_eq!(
                ExpressionType::NamedTermApp("hello".to_string(), None),
                arms[0].term.expressions[0].expression
            );
            assert_eq!(arms[1].offset, 7);
            assert_eq!(arms[1].term.expressions.len(), 1);
            assert_eq!(
                ExpressionType::NamedTermApp("other".to_string(), None),
                arms[1].term.expressions[0].expression
            );
        } else {
            panic!("not an alternation");
        }

        let logic = &program.declarations[4];
        assert_eq!(logic.name, "logic");
        let logic_exprs = &logic.term.expressions;
        assert_eq!(logic_exprs.len(), 1);
        if let ExpressionType::If(_, _, _) = logic_exprs[0].expression {
            // Not a super interesting caes to cover
        } else {
            panic!("Not an if branch");
        }

        let make_proc = &program.declarations[5];
        assert_eq!(make_proc.name, "makeProc");
        let make_proc_exprs = &make_proc.term.expressions;
        assert_eq!(make_proc_exprs.len(), 4);
        assert_eq!(ExpressionType::Number(0), make_proc_exprs[0].expression);
        assert_eq!(ExpressionType::Number(1), make_proc_exprs[1].expression);
        assert_eq!(
            ExpressionType::NamedTermRef("alternation".to_string(), None),
            make_proc_exprs[2].expression
        );
        assert_eq!(
            ExpressionType::NamedTermApp("proc".to_string(), Some(2)),
            make_proc_exprs[3].expression
        );

        let make_simpler_proc = &program.declarations[6];
        assert_eq!(make_simpler_proc.name, "makeSimplerProc");
        let make_simpler_proc_exprs = &make_simpler_proc.term.expressions;
        assert_eq!(make_simpler_proc_exprs.len(), 2);
        assert_eq!(
            ExpressionType::NamedTermRef("makeProc".to_string(), None),
            make_simpler_proc_exprs[0].expression
        );
        assert_eq!(
            ExpressionType::NamedTermApp("proc".to_string(), None),
            make_simpler_proc_exprs[1].expression
        );

        Ok(())
    }

    #[test]
    fn parse_the_empty_alternation() {
        let tokens = lex("main = []").unwrap();
        let program = parse(&tokens).unwrap();
        let main = &program.declarations[0];
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 1);
        if let ExpressionType::Alternation(arms) = &main_exprs[0].expression {
            assert!(arms.is_empty());
        } else {
            panic!("{:?} is not an alternation", main_exprs[0]);
        }
    }

    #[test]
    fn parse_while_loop() {
        let tokens = lex("main = while (true) do ()").unwrap();
        let program = parse(&tokens).unwrap();
        let main = &program.declarations[0];
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 1);
        if let ExpressionType::While(_, _) = &main_exprs[0].expression {
        } else {
            panic!("not a while loop");
        }
    }

    #[test]
    fn parse_repeat() {
        let tokens = lex("main = repeat ()").unwrap();
        let program = parse(&tokens).unwrap();
        let main = &program.declarations[0];
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 1);
        if let ExpressionType::Forever(_) = &main_exprs[0].expression {
        } else {
            panic!("not a forever");
        }
    }

    #[test]
    fn parse_parameterised_repeat() {
        let tokens = lex("main = repeat_16 ()").unwrap();
        let program = parse(&tokens).unwrap();
        let main = &program.declarations[0];
        let main_exprs = &main.term.expressions;
        assert_eq!(main_exprs.len(), 1);
        if let ExpressionType::Repeat(n, _) = &main_exprs[0].expression {
            assert_eq!(*n, 16);
        } else {
            panic!("not a forever");
        }
    }
}
