/// @desc One run of one stage. This object owns everything in it.
///
/// **The pools are global and the run is here.** A bullet belongs to the
/// field, of which there is exactly one; the player, the tally, the stage's
/// place in its own timeline and the boss's phase are facts about *this
/// attempt*, and they live on the controller. Every rule in `scripts/` that
/// needs one is handed `_g` rather than reaching for an object -- the same
/// discipline `play_functions` keeps in the Wordsearch project, and for the
/// same reason: a rule you can read without knowing which object runs it.

// `global.stage_def` is what the title screen chose. The fallback exists so
// that running `room_game` straight out of the IDE plays stage one rather than
// dying on an undefined -- which is the situation `obj_boot`'s comment about
// globals is about.
// **The field is emptied here, and only here.** Every pool is a global that
// outlives the room, so entering `room_game` says nothing about what is on the
// field unless something says it. See `run_clear_field` for the two bugs that
// came of the clearing living on one entry path instead of at the entrance.
run_clear_field();

// **Practice is a run, not a mode with a room of its own.** One attack of one
// boss, with an empty timeline and a definition shaped exactly like a stage's
// -- so everything below this line, and the whole of the HUD, is written once.
// `undefined` is the whole of "an ordinary run of a whole stage". See
// `practice_functions`.
practice = global.practice;

def = (practice != undefined) ? practice.def
                              : (global.stage_def ?? stage_ziggy_def());

t = 0;
tally = 0;
phase = Phase.Intro;
intro_t = 100;

player = player_new();
player.entry = 80;

hud = hud_new();

// **The attempt's marks.** One grade per encounter, and the standing they add
// up to -- see `rank_functions`. It lives on the run rather than in a global
// because it is a fact about *this attempt*, which is the same split every
// other per-attempt number here keeps: the pools are global, the score is not.
marks = rank_ledger_new();
bg = def.make_bg();
stage = stage_new(def);

boss_ref = undefined;
win_pending = 0;
midboss_pending = 0;
result_t = 0;
pause_row = 0;
// Which row the result panel's cursor is on, and how the attempt ended. Only
// attack practice uses either -- a stage's result screen has one key and no
// choices -- but both are assigned here rather than at the moment they start
// mattering, because a readout that reads a variable the run may not have
// assigned is the trap `obj_boot`'s note about globals is about.
result_row = 0;
practice_result = undefined;
// Which phase to hand back to when the pause menu closes. Assigned here as
// well as at the moment of pausing, so nothing ever reads it unset.
phase_before_pause = Phase.Playing;

// The spell background. `spell_bg` is what the boss *wants* (a BCOL_*, or -1
// for none) and `spell_col` is the last hue it asked for -- kept separately so
// the wash can fade out after the spell has ended, which is the frame
// `spell_bg` goes back to -1 and there is no colour left to fade in.
spell_bg = -1;
spell_col = BCOL_CRIMSON;
spell_fade = 0;
// Which *kind* of background the caster uses. Set from the boss's definition
// when a spell starts, and left alone when it ends -- the wash has to keep
// fading out in the style it faded in with.
spell_style = SPELLBG_SIGIL;

// A rising counter used only for the intro wipe and the result fade. Kept off
// `t` because `t` is the pattern clock and must not be perturbed by ceremony.
fade = 0;

/// @desc Called by `boss_finish`. Which boss it was decides what happens.
on_boss_beaten = function(_e) {
    if (boss_is_final(_e)) {
        // Let the death throes play before the screen changes. A result panel
        // that arrived on the frame the boss popped would eat the one moment
        // the whole stage was building to.
        win_pending = 170;
    } else {
        midboss_pending = 130;
    }
};

/// @desc Called by `boss_end_phase` every time an attack ends, with whether it
///       was broken or merely survived.
///
///       **An attack ending is the end of a practice attempt**, and this is
///       the only place the difference between broken and timed out survives
///       -- `boss_end_phase` pulls the health down to the threshold either
///       way, so nothing downstream can tell them apart. In an ordinary run
///       there is nothing to do: the boss's own `clear_t` hands over to the
///       next attack, which is exactly what should happen.
on_phase_end = function(_e, _beaten) {
    if (practice == undefined) return;
    practice_result = practice_outcome(
        _e, _beaten ? PracticeEnd.Beaten : PracticeEnd.TimedOut, marks);
    practice_note_best(practice, tally);
    phase = Phase.Won;
    result_t = 0;
    result_row = 0;
};

/// @desc Called by the Step event when the player takes a hit, so the boss's
///       capture bonus knows. The boss cannot see the player's health, and
///       giving it a reference to the player so it could is a dependency in
///       exactly the wrong direction.
on_player_hit = function() {
    boss_note_hit(boss_ref);
};

// See the note in Step. `undefined` means "read the keyboard".
input_override = undefined;

// **The boss goes on last, because it needs the run it is being put into.**
// `practice_begin` calls the game's own spawner and `boss_enter_phase`, which
// read the player, the ledger and the spell background off `self` -- so every
// one of them has to exist first.
//
// The stage's own opening is skipped with it. `t` is wound past the name
// splash because the splash prints `def.name`, which in practice is the
// *attack's* name, and the spell banner is announcing the same words across
// the same field at the same moment -- two copies of one name reads as a bug
// rather than as ceremony, which is the argument `hud_draw_spell_name` is
// already built on. The fly-in goes for a plainer reason: the shortest path
// from wanting to see an attack again to seeing it is the whole feature.
if (practice != undefined) {
    phase = Phase.Playing;
    intro_t = 0;
    player.entry = 0;
    t = 200;
    practice_begin(self);
}

audio_stop_all();
