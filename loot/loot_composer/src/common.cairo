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
