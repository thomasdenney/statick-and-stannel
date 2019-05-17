use super::Condition;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Flags {
    pub zero: bool,
    pub overflow: bool,
    pub sign: bool,
    pub carry: bool,
}

impl Flags {
    pub fn decode(raw: u8) -> Flags {
        let zero = raw & (1 << 3) != 0;
        let overflow = raw & (1 << 2) != 0;
        let sign = raw & (1 << 1) != 0;
        let carry = raw & 1 != 0;
        Flags {
            zero,
            overflow,
            sign,
            carry,
        }
    }

    pub fn encode(self) -> u8 {
        (self.zero as u8) << 3
            | (self.overflow as u8) << 2
            | (self.sign as u8) << 1
            | (self.carry as u8)
    }

    /// Based on Computer Architecture notes describing the x86 architecture and the ARM Architecture
    /// reference manual
    pub fn matches_condition(self, condition: Condition) -> bool {
        match condition {
            Condition::ZeroEqual => self.zero,
            Condition::NotZeroNotEqual => !self.zero,
            Condition::Negative => self.sign,
            Condition::NonNegative => !self.sign,
            Condition::UnsignedGreater => !self.carry && !self.zero,
            Condition::UnsignedLessOrEqual => self.carry || self.zero,
            Condition::UnsignedGreaterOrEqual => !self.carry,
            Condition::UnsignedLess => self.carry,
            Condition::SignedGreater => !(self.sign ^ self.overflow) && !self.zero,
            Condition::SignedLessOrEqual => (self.sign ^ self.overflow) || self.zero,
            Condition::SignedGreaterOrEqual => !(self.sign ^ self.overflow),
            Condition::SignedLess => self.sign ^ self.overflow,
            Condition::Overflow => self.overflow,
            Condition::NoOverflow => !self.overflow,
            Condition::Never => false,
            Condition::Always => true,
        }
    }
}

#[cfg(test)]
mod flags_tests {
    use super::Flags;

    #[test]
    fn flags_encode_and_decode_match() {
        for i in 0..16 {
            let zero = i & 1 > 0;
            let overflow = i & 2 > 0;
            let sign = i & 4 > 0;
            let carry = i & 8 > 0;
            let f = Flags {
                zero,
                overflow,
                sign,
                carry,
            };
            assert_eq!(f, Flags::decode(f.encode()));
        }
    }
}
