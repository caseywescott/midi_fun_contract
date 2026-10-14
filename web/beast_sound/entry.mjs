// Bundle entry for the simulator page: the same engine the beast-sound package ships.
import * as Eng from '../../offchain/beast-sound/src/engine.js';
import { engine, poseidonHashMany } from '../../offchain/beast-sound/src/index.js';
import { selector } from '../../offchain/beast-sound/src/chain.js';
import { PATCHES, PATCH_BY_ID, PATCH_FAMILIES, ENSEMBLES, createKit, chipDrum } from './patches.js';

window.BeastSound = { ...Eng, engine, poseidonHashMany, selector, PATCHES, PATCH_BY_ID, PATCH_FAMILIES, ENSEMBLES, createKit, chipDrum };
