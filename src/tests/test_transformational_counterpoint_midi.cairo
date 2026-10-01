//! MIDI demos for all nine transformational-counterpoint texture types.
//!
//! Each voice is looped INDEPENDENTLY with its own phase offset so that canons
//! genuinely overlap: leader and follower(s) play simultaneously after the
//! warm-up period, matching the texture of renaissance_canon_long_3voice_ornamented.mid.
//!
//! Export all:  ./scripts/generate_transformational_counterpoint_midis.sh
//! Single test: scarb test -- --include-ignored --filter tc_<name>_midi_test

#[cfg(test)]
mod tc_midi_tests {
    use core::array::ArrayTrait;
    use core::traits::TryInto;
    use koji::math::Time;
    use koji::composition::aesthetic_profile::profile_renaissance;
    use koji::midi::output::output_midi_object;
    use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};
    use koji::composition::transformational_counterpoint::{
        CanonTransformKind, CanonTransformPlan, DegreeEvent,
        assign_voice_id, concat_degree_lines, degree_events_to_note_events, degree_line_from_degrees,
        delay_line, hocket_part, isorhythm_line, no_same_voice_overlaps, texture_profile_ok,
        transformed_follower, transpose_line, voice_exchange_by_index,
    };

    // ── Shared constants ────────────────────────────────────────────────────
    // 1 tick = eighth note at 120 BPM (125 ms).
    // Leader notes are 2 ticks (= quarter note).  20-note phrase = 40-tick span.
    const STEP_US: u64 = 125000;
    const UNIT: u32 = 2;
    const LEADER_LEN: u32 = 20;
    const LEADER_SPAN: u32 = 40; // LEADER_LEN * UNIT
    const TONIC: u8 = 60; // C4
    const MODE: u8 = 0; // Ionian / C major
    const OCTAVE: u32 = 7;
    const TEMPO: u32 = 500000; // 120 BPM

    // Number of phrase repetitions per voice in canon demos.
    // At 5 s/phrase, 7 loops = 35 s; overlap begins after the warm-up entry lag.
    const CANON_LOOPS: u32 = 7;
    // Simultaneous textures (hocket, voice exchange, isorhythm): longer since no warm-up.
    const SIM_LOOPS: u32 = 9;

    // ── Leader motif ────────────────────────────────────────────────────────
    // 20-note C-Ionian arch: C-D-E-D-F-E-G-F-A-G-A-B-A-G-F-A-G-F-E-C
    fn renaissance_leader() -> Array<DegreeEvent> {
        degree_line_from_degrees(
            array![0_i32, 1, 2, 1, 3, 2, 4, 3, 5, 4, 5, 6, 5, 4, 3, 5, 4, 3, 2, 0].span(),
            UNIT,
            0,
        )
    }

    /// Subject shared by the two time-scaled canons.  It is consonant against both a diminished
    /// fifth-below follower and an augmented sixth-below follower across their full cycles.
    fn time_scaled_leader() -> Array<DegreeEvent> {
        degree_line_from_degrees(
            array![0_i32, -1, -2, -1, 0, 0, -1, -2, 0, 0, 0, -1, 1, -1, 0, 0, 2, 0, 0, 0].span(),
            UNIT,
            0,
        )
    }

    /// Degrees 0–4 only: inversion around degree 2 produces only unisons, thirds, and fifths.
    fn mirror_leader() -> Array<DegreeEvent> {
        degree_line_from_degrees(
            array![0_i32, 1, 2, 1, 3, 2, 4, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1, 0, 0].span(),
            UNIT,
            0,
        )
    }

    /// Its reversed half lies a third below the first half, so the crab answer alternates thirds
    /// and sixths rather than colliding in seconds.
    fn crab_leader() -> Array<DegreeEvent> {
        degree_line_from_degrees(
            array![0_i32, 1, 2, 1, 3, 2, 4, 3, 2, 1, -1, 0, 1, 2, 0, 1, -1, 0, -1, -2].span(),
            UNIT,
            0,
        )
    }

    /// Paired complements around the degree-2 axis yield a third below after retrograde inversion.
    fn retrograde_inversion_leader() -> Array<DegreeEvent> {
        degree_line_from_degrees(
            array![0_i32, 1, 2, 1, 3, 2, 4, 3, 2, 1, 5, 4, 3, 2, 4, 3, 5, 4, 5, 6].span(),
            UNIT,
            0,
        )
    }

    // ── Low-level MIDI helpers ───────────────────────────────────────────────
    fn append_legato_note(
        ref evl: Array<Message>, channel: u8, note: u8, velocity: u8, on_t: Time, off_t: Time,
    ) {
        evl.append(Message::NOTE_ON(NoteOn { channel, note, velocity, time: on_t }));
        evl.append(Message::NOTE_OFF(NoteOff { channel, note, velocity: 64, time: off_t }));
    }

    /// Render one phrase of `line` into the event list, offset by `base` microseconds.
    fn emit_phrase(ref evl: Array<Message>, line: Span<DegreeEvent>, base: Time) -> u32 {
        let notes = degree_events_to_note_events(line, OCTAVE, TONIC, MODE);
        let n = notes.len();
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            let e = *notes.at(i);
            let on: Time = base + e.time.into() * STEP_US;
            let off: Time = on + e.duration.into() * STEP_US;
            let ch: u8 = e.voice_id.try_into().unwrap();
            append_legato_note(ref evl, ch, e.pitch, e.velocity, on, off);
            i += 1;
        };
        n
    }

    /// Loop a single voice for `loops` repetitions.
    ///
    /// `start_tick` — absolute tick at which this voice first enters.
    /// `phrase_ticks` — length of one phrase in ticks (determines loop stride).
    ///
    /// In a 2-voice canon with delay D, call:
    ///   loop_voice(leader, LEADER_SPAN, 0, N)          — voice 0
    ///   loop_voice(follower, LEADER_SPAN, D, N)         — voice 1
    /// Voices overlap after `D` ticks: exactly what a real canon sounds like.
    fn loop_voice(
        ref evl: Array<Message>,
        line: Span<DegreeEvent>,
        phrase_ticks: u32,
        start_tick: u32,
        loops: u32,
    ) -> u32 {
        let mut total: u32 = 0;
        let mut lp: u32 = 0;
        loop {
            if lp >= loops {
                break;
            }
            let tick: u32 = start_tick + lp * phrase_ticks;
            let base: Time = tick.into() * STEP_US;
            total += emit_phrase(ref evl, line, base);
            lp += 1;
        };
        total
    }

    /// The degree-space Renaissance profile is necessary but not sufficient for a C-Ionian MIDI
    /// demo: F–B is a diatonic fifth class but a chromatic tritone.  Audit realized pitches too.
    fn rendered_texture_is_consonant(line: Span<DegreeEvent>) -> bool {
        let notes = degree_events_to_note_events(line, OCTAVE, TONIC, MODE);
        let mut i: u32 = 0;
        loop {
            if i >= notes.len() {
                break;
            }
            let a = *notes.at(i);
            let mut j: u32 = i + 1;
            loop {
                if j >= notes.len() {
                    break;
                }
                let b = *notes.at(j);
                if a.voice_id != b.voice_id
                    && a.time < b.time + b.duration
                    && b.time < a.time + a.duration {
                    let interval = if a.pitch >= b.pitch { a.pitch - b.pitch } else { b.pitch - a.pitch };
                    let cls = interval % 12;
                    if !(cls == 0 || cls == 3 || cls == 4 || cls == 7 || cls == 8 || cls == 9) {
                        return false;
                    }
                }
                j += 1;
            };
            i += 1;
        };
        true
    }

    fn assert_consonant_texture(line: Span<DegreeEvent>) {
        let profile = profile_renaissance();
        assert(texture_profile_ok(line, @profile), 'degree consonance');
        assert(rendered_texture_is_consonant(line), 'MIDI consonance');
    }

    // ── Parser output + validation ───────────────────────────────────────────
    fn print_format(midiobj: @Midi) {
        let mut ev = midiobj.clone().events;
        loop {
            match ev.pop_front() {
                Option::Some(m) => {
                    match m {
                        Message::NOTE_ON(n) => {
                            println!(
                                "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                                *n.channel,
                                *n.note,
                                *n.velocity,
                                *n.time,
                            );
                        },
                        Message::NOTE_OFF(n) => {
                            println!(
                                "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                                *n.channel,
                                *n.note,
                                *n.velocity,
                                *n.time,
                            );
                        },
                        Message::SET_TEMPO(t) => {
                            match *t.time {
                                Option::Some(tv) => {
                                    println!(
                                        "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                        *t.tempo,
                                        tv,
                                    );
                                },
                                Option::None(_) => {
                                    println!(
                                        "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::None }})",
                                        *t.tempo,
                                    );
                                },
                            };
                        },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        }
    }

    fn finalize(ref evl: Array<Message>, min_note_ons: u32) {
        let midiobj = Midi { events: evl.span() };
        print_format(@midiobj);
        let mut ev2 = midiobj.clone().events;
        let mut ons: u32 = 0;
        let mut offs: u32 = 0;
        loop {
            match ev2.pop_front() {
                Option::Some(m) => {
                    match m {
                        Message::NOTE_ON(_) => { ons += 1; },
                        Message::NOTE_OFF(_) => { offs += 1; },
                        _ => {},
                    }
                },
                Option::None(_) => { break; },
            }
        };
        assert(ons >= min_note_ons, 'min note ons');
        assert(ons == offs, 'on off balance');
        let binary = output_midi_object(@midiobj);
        assert(binary.len() >= 22, 'midi too short');
    }

    // ── Shared plan builder ──────────────────────────────────────────────────
    fn canon_plan(
        kind: CanonTransformKind, transposition: i32, pivot: i32, factor: u32, voice_id: u32,
    ) -> CanonTransformPlan {
        // entry_time is ALWAYS 0 here — delays are applied by loop_voice, not baked
        // into the event times, so looping each voice independently creates real overlap.
        CanonTransformPlan {
            kind,
            entry_time: 0,
            transposition,
            pivot,
            factor,
            follower_voice_id: voice_id,
        }
    }

    // ── Demo 1: Exact 3-voice stretto ───────────────────────────────────────
    // Voice 0 at C4, voice 1 a third below (A3), voice 2 an octave below (C3).
    // Each enters one phrase after the previous.  Steady-state overlap from phrase 3.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_exact_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = renaissance_leader();

        let f1 = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Exact(()), -2, 0, 1, 1),
        );
        let f2 = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Exact(()), -7, 0, 1, 2),
        );
        let with_f1 = concat_degree_lines(leader.span(), f1.span());
        let composite = concat_degree_lines(with_f1.span(), f2.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        // Each voice enters UNIT*2 ticks (2 notes) after the previous, creating real stretto overlap.
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, CANON_LOOPS);
        total += loop_voice(ref evl, f1.span(), LEADER_SPAN, UNIT * 2, CANON_LOOPS);
        total += loop_voice(ref evl, f2.span(), LEADER_SPAN, UNIT * 4, CANON_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 2: Mirror canon (melodic inversion) ────────────────────────────
    // Follower is the inversion of the leader around degree 2 (E4).
    // Rising arch answered by falling arch; both voices overlap from phrase 2.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_mirror_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = mirror_leader();

        let follower = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Mirror(()), 0, 4, 1, 1),
        );
        let composite = concat_degree_lines(leader.span(), follower.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, CANON_LOOPS);
        total += loop_voice(ref evl, follower.span(), LEADER_SPAN, UNIT * 2, CANON_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 3: Crab canon (retrograde) ─────────────────────────────────────
    // Follower is the time-reversed leader: pitches descend as leader ascends.
    // Because both occupy the same timespan, they interlock on every loop boundary.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_crab_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = crab_leader();

        let follower = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Crab(()), 0, 0, 1, 1),
        );
        let composite = concat_degree_lines(leader.span(), follower.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, CANON_LOOPS);
        total += loop_voice(ref evl, follower.span(), LEADER_SPAN, UNIT * 2, CANON_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 4: Augmentation canon (2× slower follower) ─────────────────────
    // Both voices start simultaneously; follower moves at half speed.
    // 8 leader phrases (320 ticks) = 4 augmented follower phrases (320 ticks).
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_augmentation_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = time_scaled_leader();

        let follower = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Augmentation(()), -5, 0, 2, 1),
        );
        // Follower phrase = 2 × LEADER_SPAN = 80 ticks.
        let aug_span: u32 = LEADER_SPAN * 2;
        let leader_twice = concat_degree_lines(
            leader.span(), delay_line(leader.span(), LEADER_SPAN).span(),
        );
        let composite = concat_degree_lines(leader_twice.span(), follower.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, 8);
        total += loop_voice(ref evl, follower.span(), aug_span, 0, 4);
        finalize(ref evl, total);
    }

    // ── Demo 5: Diminution canon (2× faster follower) ───────────────────────
    // Both voices start simultaneously; follower moves at double speed.
    // The follower is a fifth below (-4 diatonic degrees), not a fourth (-3).
    // 7 leader phrases (280 ticks) = 14 diminished follower phrases (280 ticks).
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_diminution_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = time_scaled_leader();

        let follower = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::Diminution(()), -4, 0, 2, 1),
        );
        // Follower phrase = LEADER_SPAN / 2 = 20 ticks.
        let dim_span: u32 = LEADER_SPAN / 2;

        // A full leader statement overlaps two diminished statements.  Validate the whole
        // 40-tick composite, rather than only the first 20 ticks, so loop-boundary seconds
        // cannot slip into the rendered MIDI.
        let follower_twice = concat_degree_lines(
            follower.span(), delay_line(follower.span(), dim_span).span(),
        );
        let composite = concat_degree_lines(leader.span(), follower_twice.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, 7);
        total += loop_voice(ref evl, follower.span(), dim_span, 0, 14);
        finalize(ref evl, total);
    }

    // ── Demo 6: Retrograde-inversion canon ──────────────────────────────────
    // Follower is the RI of the leader around degree 2 (E4): retrograde of inversion.
    // Combines crab-style time reversal with mirror-style pitch flip.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_retrograde_inversion_canon_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = retrograde_inversion_leader();

        let follower = transformed_follower(
            leader.span(), canon_plan(CanonTransformKind::RetrogradeInversion(()), 0, 4, 1, 1),
        );
        let composite = concat_degree_lines(leader.span(), follower.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, leader.span(), LEADER_SPAN, 0, CANON_LOOPS);
        total += loop_voice(ref evl, follower.span(), LEADER_SPAN, LEADER_SPAN, CANON_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 7: Voice exchange ───────────────────────────────────────────────
    // Voice 0 (upper) and voice 1 (lower, −2 = third below) swap pitch content
    // at the midpoint of every phrase: a classic invertible-counterpoint exchange.
    // Both voices play simultaneously from the first phrase.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_voice_exchange_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = renaissance_leader();

        let transposed = transpose_line(leader.span(), -2_i32);
        let companion = assign_voice_id(transposed.span(), 1);
        let mid: u32 = LEADER_LEN / 2; // exchange at note 10
        let (pa, pb) = voice_exchange_by_index(leader.span(), companion.span(), mid, LEADER_LEN);
        let composite = concat_degree_lines(pa.span(), pb.span());
        assert_consonant_texture(composite.span());

        let mut total: u32 = 0;
        total += loop_voice(ref evl, pa.span(), LEADER_SPAN, 0, SIM_LOOPS);
        total += loop_voice(ref evl, pb.span(), LEADER_SPAN, 0, SIM_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 8: Hocket ───────────────────────────────────────────────────────
    // The 20-note arch is partitioned across two voices in strict alternation:
    // voice 0 takes even-indexed notes, voice 1 takes odd-indexed notes.
    // Both parts play from the start; the composite line is continuously audible.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_hocket_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));
        let leader = renaissance_leader();

        let part0 = hocket_part(leader.span(), 2, 0, 0);
        let part1 = hocket_part(leader.span(), 2, 1, 1);
        let composite = concat_degree_lines(part0.span(), part1.span());
        assert(no_same_voice_overlaps(composite.span()), 'hocket no overlap');

        let mut total: u32 = 0;
        total += loop_voice(ref evl, part0.span(), LEADER_SPAN, 0, SIM_LOOPS);
        total += loop_voice(ref evl, part1.span(), LEADER_SPAN, 0, SIM_LOOPS);
        finalize(ref evl, total);
    }

    // ── Demo 9: Isorhythm (color 5 / talea 3) ───────────────────────────────
    // Voice 0: high ascending arc [C-D-E-G-B] against dotted talea [2-4-3].
    // Voice 1: lower answer [F-G-E-G-E] against reordered talea [4-2-3].
    // LCM(5, 3) = 15 events per period; 2 repeats = 30 events, 90-tick span.
    // Both voices play simultaneously; rhythmic independence from the LCM offset.
    #[ignore]
    #[test]
    #[available_gas(2000000000000)]
    fn tc_isorhythm_midi_test() {
        let mut evl = ArrayTrait::<Message>::new();
        evl.append(Message::SET_TEMPO(SetTempo { tempo: TEMPO, time: Option::Some(0) }));

        let v0 = isorhythm_line(
            array![7_i32, 8, 9, 11, 13].span(), // C5 D5 E5 G5 B5
            array![2_u32, 4, 3].span(), // short-long-medium
            2,
            0,
        );
        let v1 = isorhythm_line(
            array![3_i32, 4, 2, 4, 2].span(), // F4 G4 E4 G4 E4
            array![4_u32, 2, 3].span(), // long-short-medium
            2,
            1,
        );
        // Phrase = LCM(5,3) × 2 repeats = 30 events; sum of all durations = 90 ticks.
        let iso_span: u32 = 90;
        let composite = concat_degree_lines(v0.span(), v1.span());
        assert_consonant_texture(composite.span());
        let mut total: u32 = 0;
        total += loop_voice(ref evl, v0.span(), iso_span, 0, SIM_LOOPS);
        total += loop_voice(ref evl, v1.span(), iso_span, 0, SIM_LOOPS);
        finalize(ref evl, total);
    }
}
