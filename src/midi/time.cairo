use koji::math::{Time, round_to_nearest_nth_time};

fn round_to_nearest_nth(time: Time, grid_resolution: usize) -> Time {
    round_to_nearest_nth_time(time, grid_resolution.into())
}
