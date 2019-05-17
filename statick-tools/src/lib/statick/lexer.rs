extern crate regex;

use regex::Regex;
use std::error::Error;
use std::fmt;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TokenKind {
    Number(u16),
    Assign,
    Identifier(String),
    OpenParen,
    CloseParen,
    OpenSquare,
    CloseSquare,
    VerticalBar,
    Arrow,
    Offset,
    Quote,
    Underscore,
    If,
    Then,
    Else,
    While,
    Do,
    Repeat,
    Period,
}

/** Currently I only support programs containing one file. */
#[derive(Clone, Copy, Debug)]
pub struct Source {
    pub line_number: usize,
    pub line_offset: usize,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub kind: TokenKind,
    pub source: Source,
}

#[derive(Debug)]
pub struct ErrorToken {
    pub text: String,
    pub source: Source,
}

#[derive(Debug)]
pub struct LexerError {
    pub error_tokens: Vec<ErrorToken>,
}

impl fmt::Display for LexerError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        if !self.error_tokens.is_empty() {
            if self.error_tokens.len() == 1 {
                writeln!(f, "Found one unknown token:")?;
            } else {
                writeln!(f, "Found {} unknown tokens:", self.error_tokens.len())?;
            }
            for token in &self.error_tokens {
                writeln!(f, "Line {}: {}", token.source.line_number, token.text)?;
            }
        }
        Ok(())
    }
}

impl Error for LexerError {}

pub fn lex(src: &str) -> Result<Vec<Token>, LexerError> {
    let mut tokens = Vec::new();
    let mut error_tokens = Vec::new();

    let number_regex = Regex::new(r"^[0-9]+").unwrap();
    let special_char_regex =
        Regex::new(r"^(\(|\)|\[|\]|\||'|@|\->|\-\-|_|\+|\-|<=|>=|>|<|==|!=|\?|!|=|\.)").unwrap();
    let identifier_regex = Regex::new(r"^[A-Za-z][A-Za-z0-9]+").unwrap();
    let whitespace_regex = Regex::new(r"^[\s]+").unwrap();

    for (i, line) in src.lines().enumerate() {
        let line_number = i + 1;
        let mut line_offset = 0;
        // Consume leading whitespace
        if let Some(m) = whitespace_regex.find(&line[line_offset..]) {
            line_offset += m.end();
        }
        while line_offset != line.len() {
            let slice = &line[line_offset..];
            if let Some(m) = special_char_regex.find(slice) {
                let matching_str = &slice[m.start()..m.end()];
                let kind = match matching_str {
                    "=" => TokenKind::Assign,
                    "(" => TokenKind::OpenParen,
                    ")" => TokenKind::CloseParen,
                    "[" => TokenKind::OpenSquare,
                    "]" => TokenKind::CloseSquare,
                    "|" => TokenKind::VerticalBar,
                    "->" => TokenKind::Arrow,
                    "'" => TokenKind::Quote,
                    "@" => TokenKind::Offset,
                    "_" => TokenKind::Underscore,
                    "+" => TokenKind::Identifier("+".to_string()),
                    "-" => TokenKind::Identifier("-".to_string()),
                    "<" => TokenKind::Identifier("<".to_string()),
                    ">" => TokenKind::Identifier(">".to_string()),
                    "<=" => TokenKind::Identifier("<=".to_string()),
                    ">=" => TokenKind::Identifier(">=".to_string()),
                    "==" => TokenKind::Identifier("==".to_string()),
                    "!=" => TokenKind::Identifier("!=".to_string()),
                    "?" => TokenKind::Identifier("?".to_string()),
                    "!" => TokenKind::Identifier("!".to_string()),
                    "." => TokenKind::Period,
                    "--" => {
                        // The rest of this line is a comment
                        break;
                    }
                    _ => {
                        panic!("Regular expression and match statements don't match");
                    }
                };
                let source = Source {
                    line_number,
                    line_offset,
                };
                let token = Token { source, kind };
                tokens.push(token);
                line_offset += m.end();
            } else if let Some(m) = identifier_regex.find(slice) {
                let matching_str = &slice[m.start()..m.end()];
                let kind = match matching_str {
                    "if" => TokenKind::If,
                    "then" => TokenKind::Then,
                    "else" => TokenKind::Else,
                    "while" => TokenKind::While,
                    "do" => TokenKind::Do,
                    "repeat" => TokenKind::Repeat,
                    _ => TokenKind::Identifier(matching_str.to_string()),
                };
                let source = Source {
                    line_number,
                    line_offset,
                };
                let token = Token { source, kind };
                tokens.push(token);
                line_offset += m.end();
            } else if let Some(m) = number_regex.find(slice) {
                let matching_str = &slice[m.start()..m.end()];
                let source = Source {
                    line_number,
                    line_offset,
                };
                if let Ok(n) = matching_str.parse::<u16>() {
                    let kind = TokenKind::Number(n);
                    let token = Token { source, kind };
                    tokens.push(token);
                } else {
                    let text = matching_str.to_string();
                    error_tokens.push(ErrorToken { text, source });
                }
                line_offset += m.end();
            } else if let Some(m) = whitespace_regex.find(&line[line_offset..]) {
                line_offset += m.end();
            } else {
                panic!("Error at {}", slice);
            }
        }
    }
    if error_tokens.is_empty() {
        Ok(tokens)
    } else {
        Err(LexerError { error_tokens })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenization_yields_error_for_invalid_tokens() {
        let result = lex("-0123 1241234");
        assert!(result.is_err());
        if let Err(lexer_error) = result {
            assert_eq!(lexer_error.error_tokens.len(), 1);
            assert_eq!(lexer_error.error_tokens[0].text, "1241234");
        }
    }

    #[test]
    fn skips_comments() -> Result<(), LexerError> {
        let result = lex("main = hello apply -- The start of the program\nhello = ( )")?;
        assert_eq!(result.len(), 8);
        assert_eq!(result[0].source.line_number, 1);
        assert_eq!(result[0].kind, TokenKind::Identifier("main".to_string()));
        assert_eq!(result[1].kind, TokenKind::Assign);
        assert_eq!(result[2].kind, TokenKind::Identifier("hello".to_string()));
        assert_eq!(result[3].kind, TokenKind::Identifier("apply".to_string()));
        assert_eq!(result[4].source.line_number, 2);
        assert_eq!(result[4].kind, TokenKind::Identifier("hello".to_string()));
        assert_eq!(result[5].kind, TokenKind::Assign);
        assert_eq!(result[6].kind, TokenKind::OpenParen);
        assert_eq!(result[7].kind, TokenKind::CloseParen);
        Ok(())
    }

    #[test]
    fn parses_adjacent_lexemes_correctly() -> Result<(), LexerError> {
        let result = lex("'hi [@0->hello|@1->there](fine)?!+-proc|apply@if<<=>>=!===then else while do repeat.-- End of the line")?;

        assert_eq!(result[0].kind, TokenKind::Quote);
        assert_eq!(result[1].kind, TokenKind::Identifier("hi".to_string()));
        assert_eq!(result[2].kind, TokenKind::OpenSquare);
        assert_eq!(result[3].kind, TokenKind::Offset);
        assert_eq!(result[4].kind, TokenKind::Number(0));

        assert_eq!(result[5].kind, TokenKind::Arrow);
        assert_eq!(result[6].kind, TokenKind::Identifier("hello".to_string()));
        assert_eq!(result[7].kind, TokenKind::VerticalBar);
        assert_eq!(result[8].kind, TokenKind::Offset);
        assert_eq!(result[9].kind, TokenKind::Number(1));

        assert_eq!(result[10].kind, TokenKind::Arrow);
        assert_eq!(result[11].kind, TokenKind::Identifier("there".to_string()));
        assert_eq!(result[12].kind, TokenKind::CloseSquare);
        assert_eq!(result[13].kind, TokenKind::OpenParen);
        assert_eq!(result[14].kind, TokenKind::Identifier("fine".to_string()));

        assert_eq!(result[15].kind, TokenKind::CloseParen);
        assert_eq!(result[16].kind, TokenKind::Identifier("?".to_string()));
        assert_eq!(result[17].kind, TokenKind::Identifier("!".to_string()));
        assert_eq!(result[18].kind, TokenKind::Identifier("+".to_string()));
        assert_eq!(result[19].kind, TokenKind::Identifier("-".to_string()));

        assert_eq!(result[20].kind, TokenKind::Identifier("proc".to_string()));
        assert_eq!(result[21].kind, TokenKind::VerticalBar);
        assert_eq!(result[22].kind, TokenKind::Identifier("apply".to_string()));
        assert_eq!(result[23].kind, TokenKind::Offset);
        assert_eq!(result[24].kind, TokenKind::If);

        assert_eq!(result[25].kind, TokenKind::Identifier("<".to_string()));
        assert_eq!(result[26].kind, TokenKind::Identifier("<=".to_string()));
        assert_eq!(result[27].kind, TokenKind::Identifier(">".to_string()));
        assert_eq!(result[28].kind, TokenKind::Identifier(">=".to_string()));
        assert_eq!(result[29].kind, TokenKind::Identifier("!=".to_string()));
        assert_eq!(result[30].kind, TokenKind::Identifier("==".to_string()));

        assert_eq!(result[31].kind, TokenKind::Then);
        assert_eq!(result[32].kind, TokenKind::Else);
        assert_eq!(result[33].kind, TokenKind::While);
        assert_eq!(result[34].kind, TokenKind::Do);
        assert_eq!(result[35].kind, TokenKind::Repeat);
        assert_eq!(result[36].kind, TokenKind::Period);

        Ok(())
    }

    #[test]
    fn proc_with_underscore() -> Result<(), LexerError> {
        let result = lex("proc_1")?;
        assert_eq!(result[0].kind, TokenKind::Identifier("proc".to_string()));
        assert_eq!(result[1].kind, TokenKind::Underscore);
        assert_eq!(result[2].kind, TokenKind::Number(1));
        Ok(())
    }

    // TODO: Write tests that expose specific error cases in the lexer
}
