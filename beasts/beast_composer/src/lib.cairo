/// Canonical typed musical schema and codec (compiler-provided Starknet Store).
pub use beast_composer_inputs as inputs;

#[cfg(test)]
mod articulation_tests;
#[cfg(test)]
mod canon_rules_tests;
pub mod composition;
#[cfg(test)]
mod contrapuntal_tests;

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

#[cfg(test)]
mod normalized_score_tests;
#[cfg(test)]
mod params_pack_tests;

#[cfg(test)]
mod recipe_tests;
pub mod rng;
#[cfg(test)]
mod rng_tests;
#[cfg(test)]
mod score_tests;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod trait_map_tests;
