/// @desc One run of one stage (or one practised attack). The pools (bullets,
///       enemies, ...) are global; the per-attempt state (player, tally,
///       stage, marks) lives here and is passed to scripts as `_g`.

// Empty every pool. The pools outlive rooms, so starting a run must clear
// them; this is the only call (`check_run_clears_the_field` checks it).
run_clear_field();

// A practice run is an ordinary run with a stage-def-shaped `practice.def`
// (see `practice_functions`); `undefined` means a normal stage run.
practice = global.practice;

// Falls back to stage one so `room_game` can be run directly from the IDE.
def = (practice != undefined) ? practice.def
                              : (global.stage_def ?? stage_ziggy_def());

t = 0;
tally = 0;
phase = Phase.Intro;
intro_t = 100;

player = player_new();
player.entry = 80;

hud = hud_new();

// This attempt's marks (`rank_functions`).
marks = rank_ledger_new();
bg = def.make_bg();
stage = stage_new(def);

boss_ref = undefined;
win_pending = 0;
midboss_pending = 0;
result_t = 0;
pause_row = 0;
// Practice result panel: cursor row and how the attempt ended. Assigned up
// front so nothing reads them unset.
result_row = 0;
practice_result = undefined;
// The phase to return to when the pause menu closes.
phase_before_pause = Phase.Playing;

// The spell background. `spell_bg` is what the boss wants (a BCOL_*, or -1
// for none); `spell_col` keeps the last hue so the wash can fade out after
// `spell_bg` returns to -1.
spell_bg = -1;
spell_col = BCOL_CRIMSON;
spell_fade = 0;
// The background style (from the boss def); kept after the spell ends so the
// wash fades out in the same style.
spell_style = SPELLBG_SIGIL;

// Counter for the intro wipe and result fade (separate from `t`).
fade = 0;

/// @desc Called by `boss_finish`.
on_boss_beaten = function(_e) {
    if (boss_is_final(_e)) {
        // Let the death animation play before the result panel.
        win_pending = 170;
    } else {
        midboss_pending = 130;
    }
};

/// @desc Called by `boss_end_phase` when an attack ends, with whether it was
///       broken (vs timed out). Ends a practice attempt; does nothing in a
///       normal run. This is the only place that knows broken from timed out,
///       since the health is set to the threshold either way.
on_phase_end = function(_e, _beaten) {
    if (practice == undefined) return;
    practice_result = practice_outcome(
        _e, _beaten ? PracticeEnd.Beaten : PracticeEnd.TimedOut, marks);
    practice_note_best(practice, tally);
    phase = Phase.Won;
    result_t = 0;
    result_row = 0;
};

/// @desc Called by the Step event when the player is hit, so the boss can
///       void its capture bonus.
on_player_hit = function() {
    boss_note_hit(boss_ref);
};

// Input for this frame comes from here instead of the keyboard when set (used
// by the screenshot harness).
input_override = undefined;

// Practice: skip the intro, fly-in and name splash (`t` is wound past it,
// since the splash would repeat the attack's name the spell banner shows),
// and put the boss on the field. Last, because `practice_begin` reads the
// player, ledger and spell state set up above.
if (practice != undefined) {
    phase = Phase.Playing;
    intro_t = 0;
    player.entry = 0;
    t = 200;
    practice_begin(self);
}

audio_stop_all();
