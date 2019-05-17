use std::collections::{HashMap, VecDeque};
use std::io;
use std::str::FromStr;

use crate::isa::{Instruction, Op};

pub struct IOLineIteratorWrapper {
    pub lines: io::Lines<io::BufReader<std::fs::File>>,
}

impl Iterator for IOLineIteratorWrapper {
    type Item = String;

    fn next(&mut self) -> Option<Self::Item> {
        match self.lines.next() {
            Some(x) => match x {
                Ok(x) => Some(x),
                Err(_) => None,
            },
            None => None,
        }
    }
}

pub struct Lines<'a> {
    pub iter: std::str::Lines<'a>,
}

impl<'a> Iterator for Lines<'a> {
    type Item = String;

    fn next(&mut self) -> Option<Self::Item> {
        match self.iter.next() {
            Some(x) => Some(x.to_owned()),
            None => None,
        }
    }
}

#[derive(Debug)]
pub enum ParserToken {
    Identifier(String),
    Number(u16),
    Label(String),
}

pub fn lex_str(src: &str) -> Result<Vec<ParserToken>, String> {
    lex(Lines { iter: src.lines() })
}

pub fn lex<I>(line_iter: I) -> Result<Vec<ParserToken>, String>
where
    I: Iterator<Item = String>,
{
    let mut tokens = Vec::new();

    for line in line_iter {
        let line = line;
        let word_iter = line.split_whitespace();
        for word in word_iter {
            if word.starts_with('#') {
                // Skip comments
                break;
            }

            if word.ends_with(':') {
                let label = word.split_at(word.find(':').unwrap()).0;
                tokens.push(ParserToken::Label(label.to_string()));
            } else if let Ok(n) = word.parse::<u16>() {
                tokens.push(ParserToken::Number(n));
            } else {
                tokens.push(ParserToken::Identifier(word.to_string()));
            }
        }
    }

    Ok(tokens)
}

enum Block {
    Instructions(Vec<Instruction>),
    PushLabel(usize),
}

fn create_blocks(tokens: Vec<ParserToken>) -> Vec<Block> {
    enum BlocksWithStrings {
        Instructions(Vec<Instruction>),
        PushLabel(String),
    };

    let mut blocks = Vec::new();
    let mut label_blocks = HashMap::new();

    let mut current_block = Vec::new();

    for token in tokens {
        match token {
            ParserToken::Identifier(word) => match Instruction::from_str(word.as_ref()) {
                Ok(instruction) => current_block.push(instruction),
                Err(_) => {
                    blocks.push(BlocksWithStrings::Instructions(current_block));
                    blocks.push(BlocksWithStrings::PushLabel(word));
                    current_block = Vec::new();
                }
            },
            ParserToken::Label(label) => {
                if !current_block.is_empty() {
                    blocks.push(BlocksWithStrings::Instructions(current_block));
                    current_block = Vec::new();
                }
                label_blocks.insert(label, blocks.len());
            }
            ParserToken::Number(n) => {
                for i in Instruction::encode_push(n) {
                    current_block.push(i);
                }
            }
        }
    }

    if !current_block.is_empty() {
        blocks.push(BlocksWithStrings::Instructions(current_block));
    }

    blocks
        .drain(..)
        .map(|block| match block {
            BlocksWithStrings::Instructions(is) => Block::Instructions(is),
            BlocksWithStrings::PushLabel(s) => Block::PushLabel(label_blocks[&s]),
        })
        .collect()

    // TODO: Merge blocks if there is never a jump to the label separating them, as this will help optimizer
}

fn peephole_optimise(is: Vec<Instruction>) -> Vec<Instruction> {
    // TODO: Implement a peephole optimizer, including support for simplifying additions and get/put operations
    let mut res = Vec::new();
    let mut buffer = VecDeque::new();

    for i in is {
        buffer.push_back(i);

        let mut try_optimise = true;
        while try_optimise {
            let mut did_optimise = false;

            if !buffer.is_empty() {
                let last = buffer.pop_back().unwrap();

                if let Instruction::AddSmall(0) = last {
                    did_optimise = true;
                }

                if !did_optimise {
                    buffer.push_back(last);
                }
            }

            if !did_optimise && buffer.len() >= 2 {
                let last = buffer.pop_back().unwrap();
                let penultimate = buffer.pop_back().unwrap();

                if let Instruction::PushSmall(i) = penultimate {
                    if let Instruction::ArithmeticOrLogic(Op::Add) = last {
                        buffer.push_back(Instruction::AddSmall(i));
                        did_optimise = true;
                    } else if let Instruction::ReadLocal = last {
                        buffer.push_back(Instruction::ReadLocalOffset(i));
                        did_optimise = true;
                    } else if let Instruction::WriteLocal = last {
                        buffer.push_back(Instruction::WriteLocalOffset(i));
                        did_optimise = true;
                    } else if let Instruction::AddSmall(j) = last {
                        let ps = Instruction::encode_push(u16::from(i + j));
                        for p in ps {
                            buffer.push_back(p);
                        }
                        did_optimise = true;
                    }
                }

                if !did_optimise {
                    buffer.push_back(penultimate);
                    buffer.push_back(last);
                }
            }

            try_optimise = did_optimise;
        }
    }

    while !buffer.is_empty() {
        res.push(buffer.pop_front().unwrap())
    }

    res
}

fn flatten_blocks(blocks: Vec<Block>) -> Vec<Instruction> {
    let mut low_index = 0;
    // Collect the initial best case where 1 byte is reserved for each push
    let mut ranges: Vec<_> = blocks
        .iter()
        .map(|block| {
            let res = low_index;
            low_index += match block {
                Block::Instructions(is) => is.len(),
                Block::PushLabel(_label) => 1,
            };
            res
        })
        .collect();
    // Update the best case on the basis of the number of bytes required to encode a push to the label
    let mut done = false;
    while !done {
        low_index = 0;
        done = true;
        ranges = blocks
            .iter()
            .enumerate()
            .map(|(i, block)| {
                let old_low_index = ranges[i];
                let res = low_index;
                done &= old_low_index == low_index;
                low_index += match block {
                    Block::Instructions(is) => is.len(),
                    Block::PushLabel(label) => {
                        Instruction::encode_push(ranges[*label] as u16).len()
                    }
                };
                res
            })
            .collect();
    }

    let mut blocks = blocks; // Allows moves
    let mut result = Vec::new();
    for block in &mut blocks {
        match block {
            Block::Instructions(is) => result.append(is),
            Block::PushLabel(k) => result.append(&mut Instruction::encode_push(ranges[*k] as u16)),
        }
    }
    result
}

pub fn assemble(tokens: Vec<ParserToken>) -> Result<Vec<u8>, String> {
    let mut blocks = create_blocks(tokens);
    blocks = blocks
        .drain(..)
        .map(|block| match block {
            Block::Instructions(is) => Block::Instructions(peephole_optimise(is)),
            Block::PushLabel(k) => Block::PushLabel(k),
        })
        .collect();
    let instructions = flatten_blocks(blocks);
    Ok(instructions.iter().map(|i| i.encode().unwrap()).collect())
}
