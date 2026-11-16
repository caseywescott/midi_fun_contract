//! Helpers shared by the Loot engines (offchain/loot-sound/src/loot_editions.js): mulberry32 `rng`,
//! the `mix` hash, and the lab's purchase seed.

use core::num::traits::{OverflowingAdd, WideMul, WrappingMul};

const TWO32: u64 = 0x100000000;
const NZ_TWO32: NonZero<u64> = 0x100000000;

// ── panic-free u32 arithmetic (CASM size: no overflow or division-by-zero panic paths at the call
// sites; the hashes below wrap by definition) ──

/// `a + b` mod 2^32.
#[inline(never)]
pub fn wadd(a: u32, b: u32) -> u32 {
    let (x, _) = OverflowingAdd::overflowing_add(a, b);
    x
}

/// `a * b` mod 2^32.
#[inline(never)]
pub fn wmul(a: u32, b: u32) -> u32 {
    lo32(WideMul::wide_mul(a, b))
}

/// The low 32 bits of `w`.
#[inline(never)]
pub fn lo32(w: u64) -> u32 {
    let (_, r) = DivRem::div_rem(w, NZ_TWO32);
    match r.try_into() {
        Option::Some(x) => x,
        Option::None => 0,
    }
}

/// A felt known to be a u32 (a value the engines keep in range), as one, without a panic path (0 if
/// it were not).
#[inline(always)]
pub fn u32_of(x: felt252) -> u32 {
    match x.try_into() {
        Option::Some(v) => v,
        Option::None => 0,
    }
}

/// `t >> k` for a power of two `p` = 2^k.
#[inline(always)]
pub fn shr(t: u32, p: NonZero<u32>) -> u32 {
    let (q, _) = DivRem::div_rem(t, p);
    q
}

/// Returns `x`, hiding a constant from the compiler (one copy of a loop entered with constant state).
#[inline(never)]
pub fn opaque<T, +Drop<T>>(x: T) -> T {
    x
}

/// mulberry32, as loot_editions.js `rng(seed)`.
#[derive(Copy, Drop)]
pub struct Rng {
    pub a: u32,
}

#[generate_trait]
pub impl RngImpl of RngTrait {
    fn new(seed: u32) -> Rng {
        Rng { a: seed }
    }

    /// The next 32-bit output (`f()`).
    #[inline(never)]
    fn next(ref self: Rng) -> u32 {
        self.a = wadd(self.a, 0x6d2b79f5);
        let t = self.a;
        let t = wmul(t ^ shr(t, 0x8000), t | 1);
        let t = t ^ wadd(t, wmul(t ^ shr(t, 0x80), t | 61));
        t ^ shr(t, 0x4000)
    }

    /// `f.int(n)`: floor(f() * n / 2^32), 0..n.
    #[inline(never)]
    fn int(ref self: Rng, n: u32) -> u32 {
        let (q, _) = DivRem::div_rem(WideMul::wide_mul(self.next(), n), NZ_TWO32);
        match q.try_into() {
            Option::Some(x) => x,
            Option::None => 0,
        }
    }

    /// `f.pick(xs)`.
    fn pick<T, +Copy<T>, +Drop<T>>(ref self: Rng, xs: Span<T>) -> T {
        *xs.at(self.int(xs.len()))
    }
}

/// Item `i` of a table of u32s packed 7 to a felt252 (item i at bit 32 * (i % 7) of felt i / 7).
#[inline(never)]
pub fn at32(data: Span<felt252>, i: u32) -> u32 {
    let (q, r) = DivRem::div_rem(i, 7);
    let w: u256 = match data.get(q) {
        Option::Some(x) => (*x.unbox()).into(),
        Option::None => 0,
    };
    let (hi, s) = DivRem::div_rem(r, 4);
    let h = if hi == 0 {
        w.low
    } else {
        w.high
    };
    let p: NonZero<u128> = if s == 0 {
        1
    } else if s == 1 {
        0x100000000
    } else if s == 2 {
        0x10000000000000000
    } else {
        0x1000000000000000000000000
    };
    let (x, _) = DivRem::div_rem(h, p);
    let (_, x) = DivRem::div_rem(x, 0x100000000);
    match x.try_into() {
        Option::Some(v) => v,
        Option::None => 0,
    }
}

/// loot_editions.js `mix(h, x)`: imul(h ^ x, 0x9e3779b1), xor its top 17 bits down.
#[inline(never)]
pub fn mix(h: u32, x: u32) -> u32 {
    let m = wmul(h ^ x, 0x9e3779b1);
    m ^ shr(m, 0x8000)
}

/// The low 32 bits of a 64-bit seed xor its high 32 (loot_editions.js `fold`).
#[inline(never)]
pub fn fold64(seed: u64) -> u32 {
    let (hi, lo) = DivRem::div_rem(seed, NZ_TWO32);
    lo32(lo) ^ lo32(hi)
}

/// The lab's purchase seed for purchase number `n` (loot-lab.mjs `purchaseSeed`, splitmix64).
pub fn purchase_seed(n: u64) -> u64 {
    let mut x: u64 = n.wrapping_mul(0x9e3779b97f4a7c15);
    x = x ^ (x / 0x40000000);
    x = x.wrapping_mul(0xbf58476d1ce4e5b9);
    x = x ^ (x / 0x8000000);
    x = x.wrapping_mul(0x94d049bb133111eb);
    x ^ (x / 0x80000000)
}

/// The harp glissando's channel and step (loot_editions.js GLISS_CHANNEL, GLISS_STEP).
pub const GLISS_CHANNEL: u8 = 6;
pub const GLISS_STEP: u32 = 60;

/// A track's glissando (loot_editions.js `glissPlan`): which of its four places, upward or not, an
/// octave higher or not.
#[derive(Copy, Drop, PartialEq, Debug)]
pub struct GlissPlan {
    pub spot: u32,
    pub up: bool,
    pub high: bool,
}

/// `glissPlan(draw20, seed, weights)`: none when draw20 < 9 (9 in 20).
pub fn gliss_plan(draw20: u32, seed: u32, weights: Span<u32>) -> Option<GlissPlan> {
    if draw20 < 9 {
        return Option::None;
    }
    let spot = *weights.at(seed % weights.len());
    let mut sh: u32 = opaque(1);
    let mut k = 16 + spot;
    while k != 0 {
        sh *= 2;
        k -= 1;
    }
    let up = (seed / sh) % 2 == 1;
    let high = (seed / 0x100) % 3 == 0;
    Option::Some(GlissPlan { spot, up, high })
}

/// One glissando note (loot_editions.js `glissando`): start tick, length, scale degree (signed,
/// relative to the tonic), velocity.
#[derive(Copy, Drop, PartialEq, Debug)]
pub struct GlissNote {
    pub t: u32,
    pub len: u32,
    pub d: i32,
    pub v: u8,
}

/// `glissando(plan, end, span, seed, last, bpm)`: floor(glissSpan(span, bpm) / 60) steps ending at
/// `end`; pass `last = end + 480` for the source's default.
pub fn glissando(
    plan: GlissPlan, end: u32, span: u32, seed: u32, last: u32, bpm: u32,
) -> Array<GlissNote> {
    // glissSpan: shorter at speed (from 120 BPM half the span, from 160 three eighths), each note
    // ringing half the span at most then
    let (eighths, ring) = if bpm >= 160 {
        (3, 0)
    } else if bpm >= 120 {
        (4, 0)
    } else {
        (8, 360)
    };
    let span = span * eighths / 8;
    let ring = if ring == 0 && span / 2 < 360 {
        span / 2
    } else {
        360
    };
    let n = span / GLISS_STEP;
    let n_i: i32 = n.try_into().unwrap();
    let low: i32 = 1 - n_i / 2 + if plan.high {
        7
    } else {
        0
    };
    let mut out = opaque(array![]);
    let mut k: u32 = opaque(0);
    while k != n {
        let t = end - (n - k) * GLISS_STEP;
        let len = if last - t < ring {
            last - t
        } else {
            ring
        };
        let k_i: i32 = k.try_into().unwrap();
        let d = if plan.up {
            low + k_i
        } else {
            low + n_i - 1 - k_i
        };
        // Math.round((51 + mix % 24) * 0.85): (x * 85 + 50) / 100 (checked for every x in 51..74)
        let x: u32 = 51 + mix(seed, k) % 24;
        let v: u8 = ((x * 85 + 50) / 100).try_into().unwrap();
        out.append(GlissNote { t, len, d, v });
        k += 1;
    }
    out
}
