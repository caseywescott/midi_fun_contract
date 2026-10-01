// Types for @koji/beast-sound.

/** Static traits; identical to Beasts V3 `PackableBeast` (and decodable from its token ID). */
export interface Beast {
  id: number;          // species: 1–75 genesis, 76+ community
  prefix: number;      // 0 (Genesis) or 1–69
  suffix: number;      // 0 (Genesis) or 1–18
  level: number;
  health: number;
  shiny: 0 | 1;
  animated: 0 | 1;
  tier: number;        // 1–5
  beast_type: 0 | 1 | 2; // Magic, Hunter, Brute
}

/** Live stats; anything omitted is treated as "no history". */
export interface LiveStats {
  adventurers_killed?: number;   // Beasts NFT get_adventurers_killed
  scars?: number;                // Summit revival_count (+ Death Mountain collects − 1)
  summit_held_seconds?: number;  // Summit summit_held_seconds
  rank?: number;                 // get_beast_rank; 0 = Genesis
  species_count?: number;        // get_species_count
}

export interface NoteEvent {
  time: number;      // ticks at 480 per quarter note
  duration: number;  // ticks
  pitch: number;     // MIDI key
  velocity: number;
  voice: number;     // 0 = leader; the countersubject is the highest voice when present
  section: number;   // 0 = A, 1 = B, …
  role: 'canon' | 'countersubject';
}

export interface Song {
  engineVersion: number;
  name: string;
  beast: Beast;
  live: Required<LiveStats>;
  tokenId: bigint;          // Beasts V3 116-bit token ID
  creatorTokenId: bigint;   // the species' Genesis Beast; its holder is the creator
  params: Record<string, number | boolean>;
  musicState: { kill_bucket: number; defeat_bucket: number; summit_bucket: number; encounter_bucket: number; rank_tier: number; is_crown: boolean };
  events: NoteEvent[];
  sections: { id: number; start: number; tonic: number; shift: number }[];
  durationSeconds: number;
  soundSeed: bigint;
  motifHash: bigint;        // fixed for a Beast forever; history never changes it
  paramsHash: bigint;
  stateHash: bigint;        // cache key: changes only when a bucket or rank tier changes
  scoreHash: bigint;        // commitment to the whole performance
  midi: Uint8Array;         // Standard MIDI File, format 1
  bsn: Uint8Array;          // BSN1 compact note stream
  bsnFelts: bigint[];       // BSN1 packed [byte_len, 31-byte chunks…]
}

export const ENGINE_VERSION: number;
export function composeBeast(beast: Beast, live?: LiveStats, opts?: { speciesName?: string }): Song;
export function genesisBeast(traits: Partial<Beast> & { id: number }): Beast;
export function beastName(beast: Beast, speciesName?: string): string;
export function normalizeLive(beast: Beast, live?: LiveStats): Required<LiveStats>;

export function decodeTokenId(tokenId: bigint | string | number): Beast;
export function encodeTokenId(beast: Beast): bigint;
export function genesisTokenId(id: number, tier: number, beastType: number): bigint;

export function decodeBsn(input: Uint8Array | (bigint | string)[]): { tempo_us: number; events: (Omit<NoteEvent, 'voice' | 'role'> & { voice_id: number })[] };
export function bsnToMidi(input: Uint8Array | (bigint | string)[]): Uint8Array;
export function eventsToMidi(events: { time: number; duration: number; pitch: number; velocity: number; voice_id: number }[], tempoUs: number): Uint8Array;

export const DEFAULT_DROP_BPS: number;
export function dropSaltFromBlockHash(blockHash: bigint | string): bigint;
export function soundDropRoll(beast: Beast, opts: { salt: bigint | string }): number;
export function hasSound(beast: Beast, opts: { salt: bigint | string; bps?: number }): boolean;

export const TABLES: { species: string[]; prefixes: string[]; suffixes: string[]; types: string[] };
export function genesisTier(id: number): number;
export function genesisType(id: number): 0 | 1 | 2;
