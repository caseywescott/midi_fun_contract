use core::array::ArrayTrait;

#[derive(Copy, Drop)]
struct LCG {
    state: u32,
    multiplier: u32,
    increment: u32,
    modulus: u32,
}

trait RNGTrait {
    fn value(self: @LCG) -> u32;
    fn next(self: @LCG) -> LCG;
    fn getlist(self: @LCG, size: u32) -> Span<u32>; //returns the next n-size values
}

impl LCGImpl of RNGTrait {
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

#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use super::{LCG, LCGImpl, RNGTrait};

    #[test]
    #[available_gas(1000000000000)]
    fn test_lcg_basic_functionality() {
        let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };

        // Test value calculation: (5 * 1 + 3) % 16 = 8
        assert(lcg.value() == 8, 'Value calculation failed');

        // Test next state
        let next_lcg = lcg.next();
        assert(next_lcg.state == 8, 'Next state calculation failed');
        assert(next_lcg.multiplier == lcg.multiplier, 'Multiplier should not change');
        assert(next_lcg.increment == lcg.increment, 'Increment should not change');
        assert(next_lcg.modulus == lcg.modulus, 'Modulus should not change');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_lcg_sequence() {
        let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };

        // Generate sequence manually to verify
        let mut current = lcg;
        let mut values: Array<u32> = ArrayTrait::new();

        // First value: (5 * 1 + 3) % 16 = 8
        values.append(current.value());
        current = current.next();

        // Second value: (5 * 8 + 3) % 16 = 43 % 16 = 11
        values.append(current.value());
        current = current.next();

        // Third value: (5 * 11 + 3) % 16 = 58 % 16 = 10
        values.append(current.value());

        let expected_values = array![8, 11, 10];
        let span = values.span();
        let expected_span = expected_values.span();

        // Verify each value
        assert(span[0] == expected_span[0], 'First value mismatch');
        assert(span[1] == expected_span[1], 'Second value mismatch');
        assert(span[2] == expected_span[2], 'Third value mismatch');
    }

    #[test]
    #[available_gas(1000000000000)]
    fn test_lcg_getlist() {
        let lcg = LCG { state: 1, multiplier: 5, increment: 3, modulus: 16 };

        let result = lcg.getlist(5);

        // Expected sequence: 8, 11, 10, 5, 12
        let expected = array![8, 11, 10, 5, 12];
        let expected_span = expected.span();

        assert(result.len() == 5, 'Wrong list length');
        assert(result[0] == expected_span[0], 'First value wrong');
        assert(result[1] == expected_span[1], 'Second value wrong');
        assert(result[2] == expected_span[2], 'Third value wrong');
        assert(result[3] == expected_span[3], 'Fourth value wrong');
        assert(result[4] == expected_span[4], 'Fifth value wrong');
    }
}
