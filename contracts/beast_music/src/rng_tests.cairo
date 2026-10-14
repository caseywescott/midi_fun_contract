//! The random source over the LCG (`LCGRandomSource::draw`) and `bounded`.

use crate::lcg::LCG;
use crate::rng::{LCGRandomSource, bounded};

#[test]
#[available_gas(1000000000000)]
fn test_bounded_basic() {
    assert(bounded(10, 3) == 1, 'bounded 10%3 wrong');
    assert(bounded(0, 7) == 0, 'bounded 0%7 wrong');
    assert(bounded(100, 100) == 0, 'bounded 100%100 wrong');
    assert(bounded(99, 100) == 99, 'bounded 99%100 wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_lcg_random_source_draw() {
    let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };
    // value() = (5*1+3)%16 = 8; next state = 8
    let (v, new_lcg) = LCGRandomSource::draw(@lcg);
    assert(v == 8, 'draw value wrong');
    assert(new_lcg.state == 8, 'draw new state wrong');
}

#[test]
#[available_gas(1000000000000)]
fn test_lcg_random_source_chain() {
    let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };
    let (v0, lcg1) = LCGRandomSource::draw(@lcg);
    let (v1, _lcg2) = LCGRandomSource::draw(@lcg1);
    // From test_lcg_sequence we know sequence is 8, 11, ...
    assert(v0 == 8, 'chain v0 wrong');
    assert(v1 == 11, 'chain v1 wrong');
}
