#[macro_export]
// #[cfg(test)]
macro_rules! push {
    ($all:expr, $e:expr) => {{
        let is = Instruction::encode_push($e);
        let es: Result<Vec<u8>, _> = is.iter().map(|i| i.encode()).collect();
        let mut es = es?;
        $all.append(&mut es);
    }};
}

#[macro_export]
// #[cfg(test)]
macro_rules! compile_vec {
    ($is:expr, $($e:expr),*) => {
        {
            $(
                match $e.encode() {
                    Ok(i) => $is.push(i),
                    Err(msg) => return Err(msg)
                }
            )*
        }
    }
}

#[macro_export]
// #[cfg(test)]
macro_rules! compile {
    ($($e:expr),*) => {
        {
            let mut vec = Vec::new();
            $(
                match $e.encode() {
                    Ok(i) => vec.push(i),
                    Err(msg) => return Err(msg)
                }
            )*
            vec
        }
    }
}

#[macro_export]
// #[cfg(test)]
macro_rules! halt {
    ($e:expr) => {
        $e.push(Instruction::Process(ProcessOp::End).encode()?)
    };
}
