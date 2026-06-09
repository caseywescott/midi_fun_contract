//! Style profile presets (§11).

use koji::composition::ornamentation_v2::types::OrnamentStyleProfile;

pub fn profile_common_practice() -> OrnamentStyleProfile {
    OrnamentStyleProfile {
        name: 'common_practice',
        density: 35,
        chromaticism: 10,
        syncopation: 20,
        strict_counterpoint: 90,
        jazz_enclosure_bias: 0,
        baroque_ornament_bias: 40,
        suspension_bias: 80,
        neighbor_bias: 60,
        passing_bias: 80,
        grace_note_bias: 30,
        trill_bias: 30,
        turn_bias: 30,
        chromatic_approach_bias: 20,
        arpeggiation_bias: 40,
        pedal_bias: 30,
        max_ornaments_per_bar: 4,
        max_surface_notes_per_anchor: 6,
    }
}

pub fn profile_baroque_ornament() -> OrnamentStyleProfile {
    OrnamentStyleProfile {
        name: 'baroque',
        density: 65,
        chromaticism: 15,
        syncopation: 25,
        strict_counterpoint: 75,
        jazz_enclosure_bias: 0,
        baroque_ornament_bias: 80,
        suspension_bias: 60,
        neighbor_bias: 50,
        passing_bias: 50,
        grace_note_bias: 70,
        trill_bias: 80,
        turn_bias: 80,
        chromatic_approach_bias: 20,
        arpeggiation_bias: 40,
        pedal_bias: 30,
        max_ornaments_per_bar: 8,
        max_surface_notes_per_anchor: 8,
    }
}

pub fn profile_bebop_movement() -> OrnamentStyleProfile {
    OrnamentStyleProfile {
        name: 'bebop',
        density: 75,
        chromaticism: 65,
        syncopation: 70,
        strict_counterpoint: 35,
        jazz_enclosure_bias: 90,
        baroque_ornament_bias: 10,
        suspension_bias: 20,
        neighbor_bias: 80,
        passing_bias: 90,
        grace_note_bias: 40,
        trill_bias: 20,
        turn_bias: 30,
        chromatic_approach_bias: 90,
        arpeggiation_bias: 30,
        pedal_bias: 10,
        max_ornaments_per_bar: 10,
        max_surface_notes_per_anchor: 8,
    }
}

pub fn profile_modal_canon() -> OrnamentStyleProfile {
    OrnamentStyleProfile {
        name: 'modal_canon',
        density: 45,
        chromaticism: 5,
        syncopation: 35,
        strict_counterpoint: 70,
        jazz_enclosure_bias: 10,
        baroque_ornament_bias: 20,
        suspension_bias: 40,
        neighbor_bias: 80,
        passing_bias: 70,
        grace_note_bias: 20,
        trill_bias: 20,
        turn_bias: 20,
        chromatic_approach_bias: 10,
        arpeggiation_bias: 50,
        pedal_bias: 60,
        max_ornaments_per_bar: 5,
        max_surface_notes_per_anchor: 5,
    }
}

pub fn default_profile() -> OrnamentStyleProfile {
    profile_modal_canon()
}
