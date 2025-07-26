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
    /// Add or subtract to time values by a specified offset.
    fn offset_times(self: @VelocityCurve, offset: Time) -> VelocityCurve;
    /// Stretch or shrink levels by a specified factor.
    fn scale_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve;
    /// Add or subtract to levels by a specified offset.
    fn offset_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve;
    /// =========== ANALYSIS ===========
    /// Get the last time value for the breakpoint
    fn lasttime(self: @VelocityCurve) -> Time;
    /// Get the maximum levels for the breakpoint
    fn maxlevel(self: @VelocityCurve) -> u8;
    /// Get the linearly interpolated at a specified time index
    fn getlevelattime(self: @VelocityCurve, timeindex: Time) -> Option<u8>;
}

impl VelocityCurveImpl of VelocityCurveTrait {
    fn new() -> VelocityCurve {
        let empty_times: Array<Time> = array![];
        let empty_levels: Array<u8> = array![];
        VelocityCurve { times: empty_times.span(), levels: empty_levels.span() }
    }
    
    fn set_breakpoint_pair(self: @VelocityCurve, time: Time, value: u8) -> VelocityCurve {
        let mut vct = self.times.clone();
        let mut vcl = self.levels.clone();

        let mut vctimes = ArrayTrait::<Time>::new();
        let mut vclevels = ArrayTrait::<u8>::new();

        loop {
            match vct.pop_front() {
                Option::Some(currtime) => { vctimes.append(*currtime); },
                Option::None(_) => {
                    vctimes.append(time);
                    break;
                }
            };
        };

        loop {
            match vcl.pop_front() {
                Option::Some(currlevel) => { vclevels.append(*currlevel); },
                Option::None(_) => {
                    vclevels.append(value);
                    break;
                }
            };
        };

        VelocityCurve { times: vctimes.span(), levels: vclevels.span() }
    }

    fn scale_times(self: @VelocityCurve, numerator: u32, denominator: u32) -> VelocityCurve {
        let mut vct = self.times.clone();
        let mut vctimes = ArrayTrait::<Time>::new();

        loop {
            match vct.pop_front() {
                Option::Some(currtime) => { 
                    let scaled_time = time_mul_by_factor(*currtime, numerator, denominator);
                    vctimes.append(scaled_time); 
                },
                Option::None(_) => { break; }
            };
        };

        VelocityCurve { times: vctimes.span(), levels: *self.levels }
    }

    fn offset_times(self: @VelocityCurve, offset: Time) -> VelocityCurve {
        let mut vct = self.times.clone();
        let mut vctimes = ArrayTrait::<Time>::new();

        loop {
            match vct.pop_front() {
                Option::Some(currtime) => { 
                    let offset_time = time_add(*currtime, offset);
                    vctimes.append(offset_time); 
                },
                Option::None(_) => { break; }
            };
        };

        VelocityCurve { times: vctimes.span(), levels: *self.levels }
    }

    fn scale_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve {
        let mut vcl = self.levels.clone();
        let mut vclevels = ArrayTrait::<u8>::new();

        loop {
            match vcl.pop_front() {
                Option::Some(currlevel) => { 
                    let scaled_level = min_u8(*currlevel * factor, 127);
                    vclevels.append(scaled_level); 
                },
                Option::None(_) => { break; }
            };
        };

        VelocityCurve { times: *self.times, levels: vclevels.span() }
    }

    fn offset_levels(self: @VelocityCurve, factor: u8) -> VelocityCurve {
        let mut vcl = self.levels.clone();
        let mut vclevels = ArrayTrait::<u8>::new();

        loop {
            match vcl.pop_front() {
                Option::Some(currlevel) => { 
                    let offset_level = min_u8(*currlevel + factor, 127);
                    vclevels.append(offset_level); 
                },
                Option::None(_) => { break; }
            };
        };

        VelocityCurve { times: *self.times, levels: vclevels.span() }
    }

    fn lasttime(self: @VelocityCurve) -> Time {
        let times = *self.times;
        if times.len() == 0 {
            return 0;
        }
        *times.at(times.len() - 1)
    }

    fn maxlevel(self: @VelocityCurve) -> u8 {
        let mut vcl = self.levels.clone();
        let mut max_level: u8 = 0;

        loop {
            match vcl.pop_front() {
                Option::Some(currlevel) => { 
                    if *currlevel > max_level {
                        max_level = *currlevel;
                    }
                },
                Option::None(_) => { break; }
            };
        };

        max_level
    }

    fn getlevelattime(self: @VelocityCurve, timeindex: Time) -> Option<u8> {
        let times = *self.times;
        let levels = *self.levels;
        
        if times.len() == 0 || times.len() != levels.len() {
            return Option::None(());
        }
        
        // Find the interpolation points
        let mut i = 0;
        loop {
            if i >= times.len() - 1 {
                break;
            }
            
            let t1 = *times.at(i);
            let t2 = *times.at(i + 1);
            
            if timeindex >= t1 && timeindex <= t2 {
                let v1: u64 = (*levels.at(i)).into();
                let v2: u64 = (*levels.at(i + 1)).into();
                
                let interpolated = linear_interpolate(t1, v1, t2, v2, timeindex);
                return Option::Some(interpolated.try_into().unwrap());
            }
            
            i += 1;
        };
        
        Option::None(())
    }
}

