// Shared engine instance for the library layers (engine v1, Poseidon from poseidon_lite).
import { poseidonHashMany } from '../../src/poseidon_lite.js';
import { createCoreEngine } from '../../src/engine.js';

export const engine = createCoreEngine({ poseidonHashMany });
