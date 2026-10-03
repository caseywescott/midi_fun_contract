use core::array::ArrayTrait;

/// Linear Congruential Generator (LCG) Implementation
///
/// A Linear Congruential Generator is a simple pseudo-random number generator
/// that uses the formula: next = (multiplier * state + increment) % modulus
///
/// This implementation provides:
/// - Deterministic random number generation
/// - Configurable parameters for different use cases
/// - Methods to get single values or sequences of values
/// - Useful for music composition, procedural generation, and simulations
///
/// The LCG formula ensures that:
/// - Each number depends only on the previous number
/// - The sequence eventually repeats (period depends on modulus)
/// - The distribution is approximately uniform
/// - The generator is fast and memory-efficient
#[derive(Copy, Drop)]
pub struct LCG {
    /// Current state of the generator (the last generated number)
    pub state: u32,
    /// Multiplier in the LCG formula (affects the sequence pattern)
    pub multiplier: u32,
    /// Increment in the LCG formula (adds offset to prevent zero cycles)
    pub increment: u32,
    /// Modulus in the LCG formula (determines the range and period)
    pub modulus: u32,
}

/// Trait defining the interface for random number generation
///
/// This trait provides three main operations:
/// - value(): Get the current random value without advancing the state
/// - next(): Advance to the next state and return the new LCG instance
/// - getlist(): Generate a sequence of random numbers
pub trait RNGTrait {
    /// Returns the current random value without changing the generator state
    ///
    /// This is useful when you want to peek at the current value
    /// or use it multiple times without advancing the sequence
    fn value(self: @LCG) -> u32;

    /// Advances the generator to the next state and returns a new LCG instance
    ///
    /// This method applies the LCG formula: next = (multiplier * state + increment) % modulus
    /// The new instance has the updated state but keeps the same parameters
    fn next(self: @LCG) -> LCG;

    /// Generates a sequence of random numbers and returns them as a Span
    ///
    /// This is useful for generating multiple random values at once,
    /// such as creating sequences for music composition or procedural generation
    ///
    /// Args:
    ///   size: The number of random values to generate
    ///
    /// Returns:
    ///   A Span containing 'size' random numbers
    fn getlist(self: @LCG, size: u32) -> Span<u32>;
}

/// Implementation of the RNGTrait for LCG
///
/// This implementation provides the core functionality of the Linear Congruential Generator
pub impl LCGImpl of RNGTrait {
    /// Returns the current random value by applying the LCG formula
    ///
    /// Formula: (multiplier * state + increment) % modulus
    ///
    /// This calculates the next value in the sequence without actually
    /// updating the generator's internal state
    fn value(self: @LCG) -> u32 {
        // Apply the LCG formula: next = (a * x + c) % m
        // where: a = multiplier, x = state, c = increment, m = modulus
        ((*self.multiplier) * (*self.state) + (*self.increment)) % (*self.modulus)
    }

    /// Advances the generator to the next state and returns a new LCG instance
    ///
    /// This method:
    /// 1. Calculates the next state using the LCG formula
    /// 2. Creates a new LCG instance with the updated state
    /// 3. Preserves all other parameters (multiplier, increment, modulus)
    ///
    /// The new state becomes: (multiplier * current_state + increment) % modulus
    fn next(self: @LCG) -> LCG {
        // Calculate the next state using the LCG formula
        let next_state = ((*self.multiplier) * (*self.state) + (*self.increment)) % (*self.modulus);

        // Create a new LCG instance with the updated state
        // but keep all other parameters the same
        let mut lcg = LCG {
            state: next_state,
            multiplier: *self.multiplier,
            increment: *self.increment,
            modulus: *self.modulus,
        };
        lcg
    }

    /// Generates a sequence of random numbers
    ///
    /// This method:
    /// 1. Creates an array to store the generated values
    /// 2. Iteratively calls value() and next() to generate each number
    /// 3. Returns the complete sequence as a Span
    ///
    /// This is particularly useful for:
    /// - Music composition (generating note sequences)
    /// - Procedural generation (creating patterns)
    /// - Simulations (generating multiple random events)
    fn getlist(self: @LCG, size: u32) -> Span<u32> {
        // Create an array to store the generated random numbers
        let mut outarr: Array<u32> = ArrayTrait::new();

        // Start with the current LCG state
        let mut currlcg = *self;

        // Counter for the loop
        let mut i: u32 = 0;

        // Generate 'size' number of random values
        loop {
            // Check if we've generated enough numbers
            if i >= size {
                break;
            }

            // Get the current random value and add it to our array
            outarr.append(currlcg.value());

            // Advance to the next state for the next iteration
            currlcg = currlcg.next();

            // Increment our counter
            i += 1;
        }

        // Return the array as a Span for efficient access
        outarr.span()
    }
}
