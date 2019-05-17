use super::*;

use std::collections::VecDeque;

/**
 * The priamry goal of this compiler is safety rather than speed, but I included a peephole
 * optimiser as a small utility. Separately, in the assembler, there is a bytecode peephole
 * optimiser, but that is specifically for encoding existing instructions with fewer bytes; this is
 * for eliminating them.
 */
pub fn peephole(tokens: &[Token]) -> Vec<Token> {
    use FunctionOp::*;
    use Instruction::*;
    use Op::*;
    use StackOp::*;
    use Token::*;

    dbg!(tokens);

    let mut new_toks = VecDeque::default();

    for tok in tokens {
        let mut did_opt = false;
        match tok {
            I(Stack(Drop)) => match new_toks.back() {
                Some(N(_)) | Some(I(Stack(Dup))) => {
                    new_toks.pop_back();
                    did_opt = true;
                }
                _ => {}
            },
            I(Stack(Swap)) => match new_toks.back() {
                Some(I(Stack(Swap))) => {
                    new_toks.pop_back();
                    did_opt = true;
                }
                _ => {}
            },
            I(ArithmeticOrLogic(o)) => match new_toks.pop_back() {
                Some(N(n1)) => match new_toks.pop_back() {
                    Some(N(n2)) => match o {
                        Add => {
                            new_toks.push_back(N(n1 + n2));
                            did_opt = true
                        }
                        Sub => {
                            new_toks.push_back(N(n2 - n1));
                            did_opt = true
                        }
                        LogicalAnd => {
                            new_toks.push_back(N(n1 & n2));
                            did_opt = true
                        }
                        LogicalOr => {
                            new_toks.push_back(N(n1 | n2));
                            did_opt = true
                        }
                        LogicalXor => {
                            new_toks.push_back(N(n1 ^ n2));
                            did_opt = true
                        }
                        LogicalNot => {
                            new_toks.push_back(N(n2));
                            new_toks.push_back(N(!n1));
                        }
                        _ => {
                            new_toks.push_back(N(n2));
                            new_toks.push_back(N(n1));
                        }
                    },
                    Some(s) => {
                        new_toks.push_back(s);
                        if let LogicalNot = o {
                            new_toks.push_back(N(!n1));
                        } else {
                            new_toks.push_back(N(n1));
                        }
                    }
                    None => new_toks.push_back(N(n1)),
                },
                Some(s) => new_toks.push_back(s),
                None => {}
            },
            I(_) | L(_) | N(_) => {}
        }
        if !did_opt {
            new_toks.push_back(tok.clone());
        }
    }

    dbg!(&new_toks);

    Vec::from(new_toks)
}
