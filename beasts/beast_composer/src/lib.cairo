/// Shared canonical musical datatypes and codec; runtime interpretation is separate.
pub use beast_composer_inputs as inputs;

#[cfg(test)]
mod articulation_tests;
#[cfg(test)]
mod canon_rules_tests;
pub mod composition;
#[cfg(test)]
mod contrapuntal_tests;
#[cfg(test)]
mod editions_tests;
#[cfg(test)]
mod genesis_tests;
pub mod lcg;
#[cfg(test)]
mod lcg_tests;
#[cfg(test)]
mod melodic_canon_tests;
pub mod modes;
#[cfg(test)]
mod name_track_tests;
pub mod opaque;
#[cfg(test)]
mod params_pack_tests;
pub mod rng;
#[cfg(test)]
mod rng_tests;
#[cfg(test)]
mod score_tests;
#[cfg(test)]
mod song_inputs_tests;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod trait_map_tests;
