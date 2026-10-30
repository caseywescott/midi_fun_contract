//! `opaque`: hides a compile-time constant from the compiler.

/// Returns `x`. The compiler emits a second copy of a loop entered with constant state (a zero
/// counter, an empty array, a flag) specialized to it; entering it with `opaque(..)` of that state
/// keeps one copy (CASM size), at the cost of one call per loop entry.
#[inline(never)]
pub fn opaque<T, +Drop<T>>(x: T) -> T {
    x
}
