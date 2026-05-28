use koji::lcg::{LCG, RNGTrait};

pub trait RandomSource<T> {
    fn draw(self: @T) -> (u32, T);
}

pub impl LCGRandomSource of RandomSource<LCG> {
    fn draw(self: @LCG) -> (u32, LCG) {
        let v = self.value();
        (v, self.next())
    }
}

/// Map raw RNG output into `[0, bound)`.
pub fn bounded(raw: u32, bound: u32) -> u32 {
    assert(bound > 0, 'bound must be > 0');
    raw % bound
}
