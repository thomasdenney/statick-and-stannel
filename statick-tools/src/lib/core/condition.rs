use std::mem::transmute;

// NOTE: It could be worthwhile having specific binary encodings here to simplify the silicon
// implementation. Following the ARM approach, the least significant bit can be flipped to negate
// any function.
//
// NOTE: There flags can model 16 possible states, but in reality not all of these will occur (so
// long as each instruction always clears the flags or sets all of them). For example, it is never
// possible for the zero flag and the sign flag to be true together. However, assuming 16 states,
// there are 2^16 boolean functions, which correspond to conditions. I think it is interesting
// (although probably not important) that we only care about so few of those functions.
//
// Model each function as binary decision tree, where each level corresponds to a single variable.
// The binary tree has 16 leaves, each labelled with 0 or 1 for the output of the function. This
// gives a simple 16-bit encoding of all the possible functions.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum Condition {
    ZeroEqual = 0,
    NotZeroNotEqual = 1,
    Negative = 2,
    NonNegative = 3,
    UnsignedGreater = 4,        // Intel: above
    UnsignedLessOrEqual = 5,    // Intel: below or equal
    UnsignedGreaterOrEqual = 6, // Intel: above or equal
    UnsignedLess = 7,           // Intel: below
    SignedGreater = 8,
    SignedLessOrEqual = 9,
    SignedGreaterOrEqual = 10,
    SignedLess = 11,
    // TODO: Maybe remove the below. I'm currently including them on the basis that the ARM
    // architecture includes them, so I'm not certain that they aren't useful. My only other
    // justification is it ensures that I fully use the four bits I have available to me.
    Overflow = 12,
    NoOverflow = 13,
    // These have obvious benefits for simplifying encoding, so they'll probably stay in. A 'never'
    // branch encodes a NOP, which could be useful in the architecture.
    Never = 14,
    Always = 15,
}

impl Condition {
    pub fn decode(raw: u8) -> Condition {
        unsafe { transmute(raw) }
    }

    pub fn invert(self) -> Condition {
        Condition::decode((self as u8) ^ 1)
    }
}
