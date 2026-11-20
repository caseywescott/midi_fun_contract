//! EXPERIMENT (exp/kernel-libcall). `cases`: BeastPureComposer.compose / compose_drift on a fixed
//! matrix, output checked against digests recorded at the baseline (`expected`). `probes`: the
//! cost of the library-call boundary itself, as a function of the bytes passed.
pub mod probes;
#[cfg(test)]
mod cases;
#[cfg(test)]
mod expected;
