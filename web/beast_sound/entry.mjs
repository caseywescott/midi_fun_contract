// Bundle entry for the simulator page: the same engine the @koji/beast-sound package ships.
import * as Eng from '../../offchain/beast-sound/src/engine.js';
import { engine, engineV2, poseidonHashMany, ORNAMENT_NAMES } from '../../offchain/beast-sound/src/index.js';
import { selector } from '../../offchain/beast-sound/src/chain.js';

window.BeastSound = { ...Eng, engine, engineV2, ORNAMENT_NAMES, poseidonHashMany, selector };
