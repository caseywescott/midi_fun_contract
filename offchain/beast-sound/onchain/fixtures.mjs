// Immutable MIDI parity snapshots; pure Cairo composer retains its historical policy inputs.
import { writeFileSync } from 'node:fs';
import { composeBeast, encodeTokenId } from '../src/index.js';
const beast = {id:1,prefix:57,suffix:15,level:126,health:229,shiny:0,animated:0,tier:1,beast_type:0};
const cases = [
  ['genesis', {...beast,prefix:0,suffix:0,level:1,health:100,shiny:1,animated:1}, {adventurers_killed:0,scars:0,rank:0,species_count:1243}],
  ['named_fresh', beast, {adventurers_killed:0,scars:0,rank:500,species_count:954}],
  ['veteran', beast, {adventurers_killed:40,scars:9,rank:1,species_count:954}],
  ['heaviest', {id:53,prefix:69,suffix:18,level:255,health:1023,shiny:1,animated:1,tier:1,beast_type:2}, {adventurers_killed:200,scars:63,rank:1,species_count:1243}],
  ...[1,2,3,4,7,8,15,16,31,32,63,64].map(n=>['threshold_'+n,beast,{adventurers_killed:n,scars:n,rank:n,species_count:954}]),
];
const fixtures = cases.map(([name,beast,live]) => {
  live = {...live,summit_held_seconds:0};
  const score = composeBeast(beast,live);
  return {name,beast,live,token_id:'0x'+encodeTokenId(beast).toString(16),midi_b64:Buffer.from(score.midi).toString('base64'),midi_bytes:score.midi.length,tempo_us:score.params.tempo_us,duration_seconds:score.durationSeconds,notes:score.events.length};
});
writeFileSync(new URL('fixtures/midi.json',import.meta.url),JSON.stringify(fixtures,null,2)+'\n');
console.log(fixtures.slice(0,4).map(f=>({name:f.name,bytes:f.midi_bytes,notes:f.notes,duration:f.duration_seconds})));
