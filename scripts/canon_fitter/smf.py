"""Minimal Standard MIDI File read/write (stdlib only, format 0/1)."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence, Tuple


@dataclass
class MidiNote:
    tick: int
    pitch: int
    velocity: int
    channel: int = 0


@dataclass
class MidiTrack:
    notes: List[MidiNote]


@dataclass
class MidiFile:
    format: int
    division: int
    tracks: List[MidiTrack]
    tempo_us_per_quarter: int = 500000


def read_vlq(data: bytes, i: int) -> Tuple[int, int]:
    val = 0
    while i < len(data):
        b = data[i]
        i += 1
        val = (val << 7) | (b & 0x7F)
        if not (b & 0x80):
            break
    return val, i


def write_vlq(value: int) -> bytes:
    if value == 0:
        return bytes([0])
    parts: List[int] = []
    while value > 0:
        parts.insert(0, value & 0x7F)
        value >>= 7
    out = bytearray()
    for j, p in enumerate(parts):
        if j < len(parts) - 1:
            out.append(p | 0x80)
        else:
            out.append(p)
    return bytes(out)


def read_smf(path: Path) -> MidiFile:
    data = path.read_bytes()
    i = 0
    if data[i : i + 4] != b"MThd":
        raise ValueError("not a MIDI file")
    i += 4
    i += 4
    fmt, ntrks, division = struct.unpack(">HHH", data[i : i + 6])
    i += 6
    tracks: List[MidiTrack] = []
    tempo = 500000
    for _ in range(ntrks):
        if data[i : i + 4] != b"MTrk":
            raise ValueError("expected MTrk")
        i += 4
        tl = struct.unpack(">I", data[i : i + 4])[0]
        i += 4
        end = i + tl
        tick = 0
        status = 0
        notes: List[MidiNote] = []
        while i < end:
            delta, i = read_vlq(data, i)
            tick += delta
            b = data[i]
            if b & 0x80:
                status = b
                i += 1
            if status & 0xF0 == 0x90:
                note, vel = data[i], data[i + 1]
                i += 2
                if vel > 0:
                    notes.append(MidiNote(tick, note, vel, status & 0x0F))
            elif status & 0xF0 == 0x80:
                i += 2
            elif status == 0xFF:
                meta = data[i]
                i += 1
                ml, i = read_vlq(data, i)
                payload = data[i : i + ml]
                i += ml
                if meta == 0x51 and len(payload) == 3:
                    tempo = struct.unpack(">I", b"\x00" + payload)[0]
            elif status & 0xF0 == 0xB0:
                i += 2
            elif status & 0xF0 == 0xC0:
                i += 1
            elif status & 0xF0 == 0xE0:
                i += 2
            else:
                i += 1
        tracks.append(MidiTrack(notes))
        i = end
    return MidiFile(fmt, division, tracks, tempo)


def collapse_consecutive_same_pitch(pitches: Sequence[int]) -> List[int]:
    if not pitches:
        return []
    out = [pitches[0]]
    for p in pitches[1:]:
        if p != out[-1]:
            out.append(p)
    return out


def thin_to_max_len(pitches: Sequence[int], max_len: int) -> List[int]:
    seq = list(pitches)
    if len(seq) <= max_len:
        return seq
    # Keep endpoints; sample interior uniformly.
    if max_len < 2:
        return seq[:max_len]
    step = (len(seq) - 1) / (max_len - 1)
    return [seq[int(round(i * step))] for i in range(max_len)]


def extract_monophonic_pitches(
    midi: MidiFile,
    track: int = 0,
    max_len: int = 24,
    dedup: bool = True,
) -> Tuple[List[int], List[int]]:
    if track >= len(midi.tracks):
        raise ValueError(f"track {track} not found")
    notes = sorted(midi.tracks[track].notes, key=lambda n: (n.tick, n.pitch))
    pitches = [n.pitch for n in notes]
    ticks = [n.tick for n in notes]
    if dedup:
        new_p, new_t = [], []
        for p, t in zip(pitches, ticks):
            if not new_p or p != new_p[-1]:
                new_p.append(p)
                new_t.append(t)
        pitches, ticks = new_p, new_t
    pitches = thin_to_max_len(pitches, max_len)
    ticks = thin_to_max_len(ticks, max_len)
    return pitches, ticks


def degree_to_keynum(degree: int, tonic_keynum: int, scale: Sequence[int]) -> int:
    bias = 70
    d = degree + bias
    oct = d // 7
    idx = d % 7
    semis = scale[idx]
    return tonic_keynum + 12 * oct + semis - 120


def realize_degree(octave: int, degree: int, tonic_keynum: int, mode_id: int, scale: Sequence[int]) -> int:
    if octave == 12:
        return tonic_keynum + degree
    return degree_to_keynum(degree, tonic_keynum, scale)


def write_smf(path: Path, tracks: Sequence[Sequence[Tuple[int, int, int]]], division: int = 480, tempo: int = 500000) -> None:
    """Write format-1 SMF. Each track is [(delta_tick, pitch, duration_ticks), ...]."""
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks) + 1, division)
    chunks = [header]
    tempo_track = bytearray()
    tempo_track += write_vlq(0) + bytes([0xFF, 0x51, 0x03]) + struct.pack(">I", tempo)[1:4]
    tempo_track += write_vlq(0) + bytes([0xFF, 0x2F, 0x00])
    chunks.append(b"MTrk" + struct.pack(">I", len(tempo_track)) + tempo_track)
    for tr in tracks:
        data = bytearray()
        last_tick = 0
        events = sorted(tr, key=lambda e: e[0])
        for start, pitch, dur in events:
            delta = max(0, start - last_tick)
            data += write_vlq(delta) + bytes([0x90, pitch & 0x7F, 90])
            last_tick = start
            data += write_vlq(dur) + bytes([0x80, pitch & 0x7F, 0])
            last_tick = start + dur
        data += write_vlq(0) + bytes([0xFF, 0x2F, 0x00])
        chunks.append(b"MTrk" + struct.pack(">I", len(data)) + data)
    path.write_bytes(b"".join(chunks))
