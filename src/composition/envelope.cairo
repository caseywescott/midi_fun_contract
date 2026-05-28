/// A single control point on a piecewise-linear envelope.
/// `x` = time (tick, step, or normalized phase 0..1000).
/// `y` = value at that time (weight, lo bound, or hi bound).
#[derive(Copy, Drop)]
pub struct TimePoint {
    pub x: u32,
    pub y: u32,
}

/// Declares the role of `y` in an envelope; attach to a Span<TimePoint> for documentation.
#[derive(Copy, Drop)]
pub enum EnvelopeKind {
    Weight,   // y = tendency weight (arbitrary units)
    LoBound,  // y = low pitch boundary (MIDI note number or semitone offset from root)
    HiBound,  // y = high pitch boundary
}

/// A pair of envelopes bounding the feasible pitch range at each tick.
#[derive(Copy, Drop)]
pub struct PitchRangeEnvelope {
    pub lo: Span<TimePoint>,
    pub hi: Span<TimePoint>,
}

/// Piecewise-linear interpolation at tick `t` over sorted `points`.
/// Clamps to the first/last `y` when `t` is outside the range.
pub fn envelope_at(points: Span<TimePoint>, t: u32) -> u32 {
    let n = points.len();
    assert(n > 0, 'need >= 1 point');
    if t <= *points.at(0).x {
        return *points.at(0).y;
    }
    let last = n - 1;
    if t >= *points.at(last).x {
        return *points.at(last).y;
    }
    let mut i: usize = 0;
    loop {
        if i + 1 >= n {
            break;
        }
        let p0 = *points.at(i);
        let p1 = *points.at(i + 1);
        if t >= p0.x && t < p1.x {
            let dx: u64 = (p1.x - p0.x).into();
            if dx == 0 {
                return p0.y;
            }
            let dt: u64 = (t - p0.x).into();
            // Split ascending / descending to keep arithmetic in u64.
            if p1.y >= p0.y {
                let dy: u64 = (p1.y - p0.y).into();
                let delta: u64 = (dy * dt) / dx;
                return p0.y + delta.try_into().unwrap();
            } else {
                let dy: u64 = (p0.y - p1.y).into();
                let delta: u64 = (dy * dt) / dx;
                return p0.y - delta.try_into().unwrap();
            }
        }
        i += 1;
    };
    *points.at(last).y
}

/// Evaluate `(lo, hi)` at `tick`. Swaps if lo > hi (sanity guard).
pub fn range_at(env: @PitchRangeEnvelope, tick: u32) -> (u32, u32) {
    let lo = envelope_at(*env.lo, tick);
    let hi = envelope_at(*env.hi, tick);
    if lo > hi {
        return (hi, lo);
    }
    (lo, hi)
}
