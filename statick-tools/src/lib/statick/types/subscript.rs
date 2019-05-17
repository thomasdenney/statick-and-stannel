use std::string::ToString;

pub fn subscripted<T: ToString>(n: T) -> String {
    n.to_string().chars().fold(String::new(), |mut s, c| {
        if c >= '0' && c <= '9' {
            // https://en.wikipedia.org/wiki/Unicode_subscripts_and_superscripts
            let lut = vec![
                // '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹',
                '₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉',
            ];
            s.push(lut[(c as usize) - ('0' as usize)]);
        } else {
            s.push(c);
        }
        s
    })
}
