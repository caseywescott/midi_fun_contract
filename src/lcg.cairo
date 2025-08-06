use core::array::ArrayTrait;

#[derive(Copy, Drop)]
pub struct LCG {
    pub state: u32,
    pub multiplier: u32,
    pub increment: u32,
    pub modulus: u32,
}

pub trait RNGTrait {
    fn value(self: @LCG) -> u32;
    fn next(self: @LCG) -> LCG;
    fn getlist(self: @LCG, size: u32) -> Span<u32>; //returns the next n-size values
}

pub impl LCGImpl of RNGTrait {
    fn value(self: @LCG) -> u32 {
        ((*self.multiplier) * (*self.state) + (*self.increment)) % (*self.modulus)
    }
    fn next(self: @LCG) -> LCG {
        let mut lcg = LCG {
            state: ((*self.multiplier) * (*self.state) + (*self.increment)) % (*self.modulus),
            multiplier: *self.multiplier,
            increment: *self.increment,
            modulus: *self.modulus,
        };
        lcg
    }
    fn getlist(self: @LCG, size: u32) -> Span<u32> {
        let mut outarr: Array<u32> = ArrayTrait::new();
        let mut currlcg = *self;
        let mut i: u32 = 0;
        loop {
            if i >= size {
                break;
            }
            outarr.append(currlcg.value());
            currlcg = currlcg.next();
            i += 1;
        }
        outarr.span()
    }
}
