use core::option::OptionTrait;
use koji::midi::types::{
    Midi, Message, Modes, ArpPattern, VelocityCurve, NoteOn, NoteOff, SetTempo, TimeSignature,
    ControlChange, PitchWheel, AfterTouch, PolyTouch, Direction, PitchClass
};
use koji::math::{Time, time_add, time_sub, time_mul_by_factor, linear_interpolate, min_u8};

trait VelocityCurveTrait {
    /// =========== VelocityCurve MANIPULATION ===========
    /// Instantiate a VelocityCurve.
    fn new() -> VelocityCurve;
    /// Append a breakpoint time/value pair in a VelocityCurve object.
    fn set_breakpoint_pair(self: @VelocityCurve, time: Time, value: u8) -> VelocityCurve;
    /// =========== GLOBAL MANIPULATION ===========
    /// Stretch or shrink time values by a specified factor.
    fn scale_times(self: @VelocityCurve, numerator: u32, denominator: u32) -> VelocityCurve;
    /// Apply a factor to all levels in a VelocityCurve object.
    fn scale_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve;
    /// Add an offset to all levels in a VelocityCurve object.
    fn offset_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve;
    /// =========== GETTERS ===========
    /// Get the time value at the last index of the curve
    fn lasttime(self: @VelocityCurve) -> Time;
    /// Get the velocity level at a given time in the curve.
    fn getlevelattime(self: @VelocityCurve, time: Time) -> Option<u8>;
}

impl VelocityCurveImpl of VelocityCurveTrait {
    fn new() -> VelocityCurve {
        let empty_times: Array<Time> = array![];
        let empty_levels: Array<u8> = array![];
        VelocityCurve { times: empty_times.span(), levels: empty_levels.span() }
    }

    fn set_breakpoint_pair(self: @VelocityCurve, time: Time, value: u8) -> VelocityCurve {
        let mut new_times = array![];
        let mut new_levels = array![];

        // Copy existing data
        let mut times_span = *self.times;
        let mut levels_span = *self.levels;

        while let Option::Some(current_time) = times_span.pop_front() {
            new_times.append(*current_time);
        };

        while let Option::Some(current_level) = levels_span.pop_front() {
            new_levels.append(*current_level);
        };

        // Add new breakpoint
        new_times.append(time);
        new_levels.append(value);

        VelocityCurve { times: new_times.span(), levels: new_levels.span() }
    }

    fn scale_times(self: @VelocityCurve, numerator: u32, denominator: u32) -> VelocityCurve {
        let mut new_times = array![];
        let mut new_levels = array![];

        let mut times_span = *self.times;
        let mut levels_span = *self.levels;

        while let Option::Some(current_time) = times_span.pop_front() {
            let scaled_time = time_mul_by_factor(*current_time, numerator, denominator);
            new_times.append(scaled_time);
        };

        while let Option::Some(current_level) = levels_span.pop_front() {
            new_levels.append(*current_level);
        };

        VelocityCurve { times: new_times.span(), levels: new_levels.span() }
    }

    fn scale_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve {
        let mut new_times = array![];
        let mut new_levels = array![];

        let mut times_span = *self.times;
        let mut levels_span = *self.levels;

        while let Option::Some(current_time) = times_span.pop_front() {
            new_times.append(*current_time);
        };

        while let Option::Some(current_level) = levels_span.pop_front() {
            let scaled_level = min_u8(*current_level * factor, 127);
            new_levels.append(scaled_level);
        };

        VelocityCurve { times: new_times.span(), levels: new_levels.span() }
    }

    fn offset_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve {
        let mut new_times = array![];
        let mut new_levels = array![];

        let mut times_span = *self.times;
        let mut levels_span = *self.levels;

        while let Option::Some(current_time) = times_span.pop_front() {
            new_times.append(*current_time);
        };

        while let Option::Some(current_level) = levels_span.pop_front() {
            let offset_level = min_u8(*current_level + factor, 127);
            new_levels.append(offset_level);
        };

        VelocityCurve { times: new_times.span(), levels: new_levels.span() }
    }

    fn lasttime(self: @VelocityCurve) -> Time {
        let times = *self.times;
        if times.len() == 0 {
            0
        } else {
            *times.at(times.len() - 1)
        }
    }

    fn getlevelattime(self: @VelocityCurve, time: Time) -> Option<u8> {
        let times = *self.times;
        let levels = *self.levels;
        
        if times.len() == 0 {
            return Option::None;
        }

        // Simple implementation: return the level of the first breakpoint at or after the given time
        let mut i = 0;
        while i < times.len() {
            if *times.at(i) >= time {
                return Option::Some(*levels.at(i));
            }
            i += 1;
        };

        // If no breakpoint found at or after the time, return the last level
        Option::Some(*levels.at(levels.len() - 1))
    }
}

