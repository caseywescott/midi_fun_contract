use core::traits::TryInto;
use koji::composition::barry_harris::{normalize_pc, voicelead};
use koji::composition::barry_voice_motion::VoiceMotionPolicy;
use koji::composition::barry_voice_motion::{
    score_voice_motion, voicelead_with_policy, voices_do_not_cross,
};

#[test]
fn test_minimal_motion_matches_v1() {
    let prev = array![60_i16, 64, 67, 71].span();
    let target = array![0_u8, 4, 7, 11].span();
    let v1 = voicelead(prev, target, 48, 72, 0);
    let v2 = voicelead_with_policy(prev, target, 48, 72, VoiceMotionPolicy::MinimalMotion, 0);
    assert(v1.len() == v2.len(), 'len');
    let mut i: usize = 0;
    loop {
        if i >= v1.len() {
            break;
        }
        assert(*v1.at(i) == *v2.at(i), 'same note');
        i += 1;
    };
}

#[test]
fn test_contrary_outer_prefers_contrary() {
    let prev = array![48_i16, 72].span();
    let parallel_score = score_voice_motion(
        prev, array![50_i16, 74].span(), VoiceMotionPolicy::ContraryOuterVoices,
    );
    let contrary_score = score_voice_motion(
        prev, array![50_i16, 70].span(), VoiceMotionPolicy::ContraryOuterVoices,
    );
    assert(contrary_score < parallel_score, 'contrary wins');
}

#[test]
fn test_oblique_top_preserves_top() {
    let prev = array![48_i16, 60, 72].span();
    let score = score_voice_motion(
        prev, array![50_i16, 62, 72].span(), VoiceMotionPolicy::ObliqueTopVoice,
    );
    let moved_score = score_voice_motion(
        prev, array![50_i16, 62, 74].span(), VoiceMotionPolicy::ObliqueTopVoice,
    );
    assert(score < moved_score, 'fixed top');
}

#[test]
fn test_oblique_bass_preserves_bass() {
    let prev = array![48_i16, 60, 72].span();
    let score = score_voice_motion(
        prev, array![48_i16, 62, 74].span(), VoiceMotionPolicy::ObliqueBass,
    );
    let moved_score = score_voice_motion(
        prev, array![50_i16, 62, 74].span(), VoiceMotionPolicy::ObliqueBass,
    );
    assert(score < moved_score, 'fixed bass');
}

#[test]
fn test_voicelead_no_crossing() {
    let prev = array![48_i16, 55, 60, 67].span();
    let target = array![0_u8, 7, 4, 11].span();
    let out = voicelead_with_policy(
        prev, target, 48, 72, VoiceMotionPolicy::ContraryOuterVoices, 3,
    );
    assert(voices_do_not_cross(out.span()), 'no cross');
    assert(out.len() == 4, 'four voices');
}
