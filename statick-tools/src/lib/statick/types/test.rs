use std::ops::Deref;

use super::super::ast::Program;
use super::super::lexer::lex;
use super::super::parser::parse;
use super::{
    type_check, ChannelUse, Constraint, Direction, Stack, Type, TypeCheckResult, TypeError,
};

// In these tests we can just allow the lexer/parser to panic on fail
fn lex_and_parse(src: &str) -> Program {
    let tokens = lex(src).unwrap();
    parse(&tokens).unwrap()
}

#[test]
fn no_main_fails_to_type_check() {
    let mut program = lex_and_parse("");
    assert_eq!(
        type_check(&mut program).unwrap_err(),
        TypeError::UndefinedMain
    );
}

#[test]
fn duplicated_names_produces_error() {
    let mut program = lex_and_parse(
        "main = swap
        main = dup",
    );
    let res = type_check(&mut program);
    assert_eq!(
        res.unwrap_err(),
        TypeError::DuplicateName("main".to_string())
    );
}

#[test]
fn undefined_name_produces_error() {
    let mut program = lex_and_parse("main = something");
    let res = type_check(&mut program);
    assert_eq!(
        res.unwrap_err(),
        TypeError::UnknownName("something".to_string())
    );
}

#[test]
fn push_bool_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = true");
    type_check(&mut program)
}

#[test]
fn push_int_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 1");
    type_check(&mut program)
}

#[test]
fn push_offset_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 0 @0");
    type_check(&mut program)
}

#[test]
fn addition_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 1 2 +");
    type_check(&mut program)
}

#[test]
fn push_offset_for_bad_offset_fails() {
    let mut program = lex_and_parse("main = @0");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn boolean_call_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 'true apply");
    type_check(&mut program)
}

#[test]
fn anonymous_call_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 0 (1+) apply");
    type_check(&mut program)
}

#[test]
fn if_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = if (true) then (0) else (1)");
    type_check(&mut program)
}

#[test]
fn if_in_another_fn_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = true fn
            fn = if () then (0) else (1)",
    );
    type_check(&mut program)
}

#[test]
fn dup_apply_doesnt_unify() {
    let mut program = lex_and_parse("main = dup apply");
    let res = type_check(&mut program);
    if let TypeError::NonUnifiableStacks(_, _) = res.unwrap_err() {
    } else {
        panic!("Shouldn't be able to unify types because of self recursion");
    }
}

#[test]
fn can_drop_fn() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = (.) drop");
    type_check(&mut program)?;
    let mut program = lex_and_parse("main = 'fn drop fn = .");
    type_check(&mut program)
}

#[test]
fn really_basic_rec() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = 0 rec
            rec = if (@0 0 ==) then () else (1 - rec)",
    );
    type_check(&mut program)
}

#[test]
fn fib() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
            "main = 0 fib
            fib = if (@0 0 ==) then () else (if (@0 1 ==) then () else (@0 1 - fib swap 2 - fib +))",
        );
    type_check(&mut program)
}

#[test]
fn infinite_loop_fails() {
    let mut program = lex_and_parse("main = main");
    let res = type_check(&mut program);
    assert!(res.is_err());
}

#[test]
fn unbounded_recursion_fails() {
    let mut program = lex_and_parse("main = 0 main");
    let res = type_check(&mut program);
    assert!(res.is_err());
}

#[test]
fn empty_alternation_is_err() {
    let mut program = lex_and_parse("main = []");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn chan_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan 'other proc_1 repeat (? drop)
        other = repeat (1 !)",
    );
    type_check(&mut program)
}

#[test]
fn two_channel_alternation_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan 'p1 proc_1 chan 'p2 proc_1 repeat ([ @0 -> drop | @1 -> drop])
        p1 = repeat (0 !)
        p2 = repeat (true !)",
    );
    dbg!(&program);
    type_check(&mut program)
}

#[test]
fn cant_del_unused_channel() {
    let mut program = lex_and_parse("main = chan_1 del drop");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn unused_channel_doesnt_type_check() {
    let mut program = lex_and_parse("main = chan chan chan [ @1 -> () | @5 -> () ]");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn empty_process_creation() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = () proc");
    type_check(&mut program)
}
#[test]
fn process_creation_needs_right_number_of_args() {
    let mut program = lex_and_parse("main = (+ 1) proc");
    assert!(type_check(&mut program).is_err());
    let mut program = lex_and_parse("main = 1 () proc_1");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn proc_consumes_a_chan() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = chan_1 (1 ! drop) proc_1 ? drop del");
    type_check(&mut program)
}

#[test]
fn if_function_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 0 if (@0 0 ==) then (1 +) else (2 +)");
    type_check(&mut program)
}

#[test]
fn apply_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = ((0) apply) fn
            fn = apply",
    );
    type_check(&mut program)
}

#[test]
fn while_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = while (true) do ()");
    type_check(&mut program)
}

#[test]
fn dup_dup_requires_duplicable_type() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = 0 dupDup
            dupDup = dup dup",
    );
    type_check(&mut program)?;
    let dup_dup_t = program.declarations[1].term.t_type.as_ref().unwrap();
    if let Type::Function(i, _) = dup_dup_t.deref() {
        if let Stack::Stack(_, a) = i.deref() {
            if let Type::Generic(_, cs) = a.deref() {
                assert!(cs.contains(Constraint::Duplicable));
            } else {
                panic!("Expected generic type in {}", dup_dup_t);
            }
        } else {
            panic!("Expected non base stack in {}", dup_dup_t);
        }
    } else {
        panic!("Expected function in {}", dup_dup_t);
    }
    Ok(())
}

#[test]
fn dup_drop_requires_type_classes() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = 0 dupDrop
            dupDrop = dup drop",
    );
    type_check(&mut program)?;
    let dup_drop_t = program.declarations[1].term.t_type.as_ref().unwrap();
    if let Type::Function(i, _) = dup_drop_t.deref() {
        if let Stack::Stack(_, a) = i.deref() {
            if let Type::Generic(_, cs) = a.deref() {
                assert!(cs.contains(Constraint::Droppable));
                assert!(cs.contains(Constraint::Duplicable));
            } else {
                panic!("Expected generic type in {}", dup_drop_t);
            }
        } else {
            panic!("Expected non base stack in {}", dup_drop_t);
        }
    } else {
        panic!("Expected function in {}", dup_drop_t);
    }
    Ok(())
}

#[test]
fn use_once_cant_be_dropped() {
    let mut program = lex_and_parse("main = 0 chan_1 swap swap drop");
    assert!(type_check(&mut program).is_err())
}

#[test]
fn use_once_cant_be_dupped() {
    let mut program = lex_and_parse("main = chan_1 dup");
    assert!(type_check(&mut program).is_err())
}

#[test]
fn cant_create_a_process_that_doesnt_use_channel() {
    let mut program = lex_and_parse("main = chan_1 'other proc_1
                                    other = () apply -- this is the shortest way to write an empty func");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn send_receive_once_type_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = myMakeOnce 'sender proc_1 ? drop del
         myMakeOnce = chan_1
         sender = 10 ! drop",
    );
    type_check(&mut program)
}

#[test]
fn must_do_something_with_use_once_chan() {
    let mut program = lex_and_parse(
        "main = chan_1 'sender proc_1
         sender = 10 !_1 chan_1",
    );
    assert!(type_check(&mut program).is_err());
}

#[test]
fn cant_call_function_with_number() {
    let mut program = lex_and_parse("main = 0 dup_2");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn repeat_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 0 repeat (1 +)");
    type_check(&mut program)
}

#[test]
fn cant_use_repeat_to_hide_forever_chan() {
    let mut program = lex_and_parse(
        "main = chan 'other proc_1 repeat ()
        other = 1 !",
    );
    assert!(type_check(&mut program).is_err());
}

#[test]
fn cant_pass_a_channel_to_a_process_that_doesnt_use_it() {
    let mut program = lex_and_parse(
        "main = chan_1 'sender proc_1 ?
            sender = 1",
    );
    assert!(type_check(&mut program).is_err());
}

#[test]
fn can_drop_used_channel() {
    let mut program = lex_and_parse(
        "main = chan_1 'sender proc_1 ? drop drop
        sender = 10 ! drop",
    );
    let res = type_check(&mut program);
    assert!(res.is_ok());
}

#[test]
fn cant_drop_unused_channel() {
    let mut program = lex_and_parse("main = chan drop");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn fn_that_sends_twice_is_generic() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = .
        sender = 1 ! 2 !
        senderDrop = sender drop",
    );
    type_check(&mut program)?;
    let sender = &program.declarations[1];
    assert_eq!("sender", sender.name);
    let sender_t = sender.term.t_type.as_ref().unwrap();
    let mut good = false;
    if let Type::Function(i, o) = sender_t {
        if let Stack::Stack(_, t1) = i.deref() {
            if let Stack::Stack(_, t2) = o.deref() {
                if let Type::Channel(u1, d1, c1) = t1.deref() {
                    if let Type::Channel(u2, d2, c2) = t2.deref() {
                        assert_eq!(c1, c2);
                        assert_eq!(d1, d2);
                        if let ChannelUse::Variable(n1, o1) = u1 {
                            assert_eq!(*o1, 2);
                            if let ChannelUse::Variable(n2, o2) = u2 {
                                assert_eq!(*n1, *n2);
                                assert_eq!(*o2, 0);
                                good = true;
                            }
                        }
                    }
                }
            }
        }
    }
    if !good {
        panic!("{} is not as expected", sender_t);
    }

    let sender_drop = &program.declarations[2];
    assert_eq!("senderDrop", sender_drop.name);
    let sender_drop_t = sender_drop.term.t_type.as_ref().unwrap();
    good = false;
    if let Type::Function(i, o) = sender_drop_t {
        if let Stack::Stack(_, t) = i.deref() {
            if let Stack::Generic(_, _) = o.deref() {
                if let Type::Channel(u, d, _) = t.deref() {
                    assert_eq!(*u, ChannelUse::Constant(2));
                    assert_eq!(*d, Direction::Tx);
                    good = true;
                }
            }
        }
    }
    if !good {
        panic!("{} is not as expected", sender_drop_t);
    }
    Ok(())
}

#[test]
fn fn_that_uses_channel_in_repeat_types_channel_as_forever() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan 'sender proc_1 repeat (? drop)
        sender = repeat (1 !)",
    );
    type_check(&mut program)?;
    let sender = &program.declarations[1];
    assert_eq!(sender.name, "sender");
    let sender_t = &sender.term.t_type.as_ref().unwrap();
    if let Type::Function(i, _) = sender_t {
        if let Stack::Stack(_, t) = i.deref() {
            if let Type::Channel(u, d, c) = t.deref() {
                assert_eq!(&Type::Integer, c.deref());
                assert_eq!(&ChannelUse::Infinity, u);
                assert_eq!(&Direction::Tx, d);
            } else {
                panic!("not a channel");
            }
        } else {
            panic!("not a stack");
        }
    } else {
        panic!("not a function");
    }
    Ok(())
}

#[test]
fn fn_that_uses_channel_in_while_types_channel_as_forever() -> TypeCheckResult<()> {
    // The type system can't infer that the while 'true will never terminate, and as it could
    // terminate it is required that the forever channels are used afterwards. The language
    // semantics would therefore prefer that forever was used instead.
    let mut program = lex_and_parse(
        "main = chan 'sender proc_1 while (true) do (? drop) repeat (? drop)
        sender = while (true) do (1 !) repeat (1 !)",
    );
    type_check(&mut program)?;
    let sender = &program.declarations[1];
    assert_eq!(sender.name, "sender");
    let sender_t = &sender.term.t_type.as_ref().unwrap();
    if let Type::Function(i, _) = sender_t {
        if let Stack::Stack(_, t) = i.deref() {
            if let Type::Channel(u, d, c) = t.deref() {
                assert_eq!(&Type::Integer, c.deref());
                assert_eq!(&ChannelUse::Infinity, u);
                assert_eq!(&Direction::Tx, d);
            } else {
                panic!("not a channel");
            }
        } else {
            panic!("not a stack");
        }
    } else {
        panic!("not a function");
    }
    Ok(())
}

#[test]
fn cant_put_stuff_after_repeat() {
    let mut program = lex_and_parse(
        "main = .
        other = repeat (.) repeat (.)",
    );
    assert!(type_check(&mut program).is_err());
}

#[test]
fn cant_subscript_own_fns() {
    let mut program = lex_and_parse(
        "main = other_1
        other = .",
    );
    assert!(type_check(&mut program).is_err());
}

#[test]
fn subscript_channel_ops() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan_1 'sender proc_1 2 ?_1 + del_1 drop
        sender = 10 !_1 drop",
    );
    type_check(&mut program)
}

#[test]
fn repeat_once_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 2 repeat_1 (swap 1 + swap)");
    type_check(&mut program)
}

#[test]
fn repeat_twice_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 2 repeat_2 (swap 2 + swap)");
    type_check(&mut program)
}

#[test]
fn repeat_many_times_checks() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 2 repeat_10 (swap 2 + swap)");
    type_check(&mut program)
}

#[test]
fn repeat_duplication() -> TypeCheckResult<()> {
    let mut program = lex_and_parse("main = 0 repeat_9 (swap dup 1 + tuck)");
    type_check(&mut program)?;
    let main_t = program.declarations[0].term.t_type.clone().unwrap();
    let mut out_s = if let Type::Function(_, o) = main_t {
        o.deref().clone()
    } else {
        panic!();
    };
    let mut k = 0;
    while let Stack::Stack(b, t) = out_s {
        assert_eq!(&Type::Integer, t.deref());
        out_s = b.deref().clone();
        k = k + 1;
    }
    assert_eq!(k, 10);
    Ok(())
}

#[test]
fn repeat_with_channels() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan_3 'sender proc_1 repeat_3 (swap ? drop swap) del
        sender = repeat_3 (swap 4 ! swap) drop",
    );
    type_check(&mut program)
}

#[test]
fn int_like_conversions() {
    let mut program = lex_and_parse("main = true toInt");
    assert!(type_check(&mut program).is_ok());
    let mut program = lex_and_parse("main = 0 toInt");
    assert!(type_check(&mut program).is_ok());
    let mut program = lex_and_parse("main = repeat_1 (toInt swap)");
    assert!(type_check(&mut program).is_ok());
    let mut program = lex_and_parse("main = (10) toInt");
    assert!(type_check(&mut program).is_err());
}

#[test]
fn alternation_with_two_finite_channels() -> TypeCheckResult<()> {
    let mut program = lex_and_parse(
        "main = chan_1 'sender1 proc_1
            chan_1 'sender2 proc_1
            [@0 -> ?_2 + | @1 -> ?_1 +]
            rot del del
    sender1 = 7 ! drop
    sender2 = 8 ! drop",
    );
    type_check(&mut program)
}

#[test]
fn cant_use_offset_to_clone_a_chan() {
    let mut program = lex_and_parse("main = chan_1 @1");
    let res = type_check(&mut program);
    assert!(res.is_err());
    if let TypeError::MissingConstraints(_,_,cs) = res.unwrap_err() {
        assert!(cs.contains(Constraint::Duplicable));
    } else {
        panic!("Didn't have expected error");
    }
}
