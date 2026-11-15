//! Helpers shared by the Loot engines (offchain/loot-sound/src/loot_editions.js): mulberry32 `rng`,
//! the `mix` hash, and the lab's purchase seed.

use core::num::traits::{WrappingAdd, WrappingMul};

const TWO32: u64 = 0x100000000;

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
        self.a = self.a.wrapping_add(0x6d2b79f5);
        let t = self.a;
        let t = (t ^ (t / 0x8000)).wrapping_mul(t | 1);
        let t = t ^ t.wrapping_add((t ^ (t / 0x80)).wrapping_mul(t | 61));
        t ^ (t / 0x4000)
    }

    /// `f.int(n)`: floor(f() * n / 2^32), 0..n.
    #[inline(never)]
    fn int(ref self: Rng, n: u32) -> u32 {
        let x: u64 = self.next().into();
        ((x * n.into()) / TWO32).try_into().unwrap()
    }

    /// `f.pick(xs)`.
    fn pick<T, +Copy<T>, +Drop<T>>(ref self: Rng, xs: Span<T>) -> T {
        *xs.at(self.int(xs.len()))
    }
}

/// loot_editions.js `mix(h, x)`: imul(h ^ x, 0x9e3779b1), xor its top 17 bits down.
#[inline(never)]
pub fn mix(h: u32, x: u32) -> u32 {
    let m = (h ^ x).wrapping_mul(0x9e3779b1);
    m ^ (m / 0x8000)
}

/// The low 32 bits of a 64-bit seed xor its high 32 (loot_editions.js `fold`).
pub fn fold64(seed: u64) -> u32 {
    let lo: u32 = (seed % TWO32).try_into().unwrap();
    let hi: u32 = (seed / TWO32).try_into().unwrap();
    lo ^ hi
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
    let mut sh: u32 = 1;
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

/// `glissando(plan, end, span, seed, last)`: floor(span / 60) steps ending at `end`; pass
/// `last = end + 480` for the source's default.
pub fn glissando(plan: GlissPlan, end: u32, span: u32, seed: u32, last: u32) -> Array<GlissNote> {
    let n = span / GLISS_STEP;
    let n_i: i32 = n.try_into().unwrap();
    let low: i32 = 1 - n_i / 2 + if plan.high {
        7
    } else {
        0
    };
    let mut out = array![];
    let mut k: u32 = 0;
    while k != n {
        let t = end - (n - k) * GLISS_STEP;
        let len = if last - t < 360 {
            last - t
        } else {
            360
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
