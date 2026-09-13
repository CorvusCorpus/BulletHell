/// @desc The hall with nobody in it: a card on the rack that flies the
/// Gilded Sanctum's background, over and over, and contains nothing else.
///
/// **A background cannot be judged from a still, and it cannot be judged from
/// a stage either.** `tools/shot.py` answers "does this frame read", which is
/// what it is for and what it is the only tool for; what it cannot answer is
/// anything about *movement* -- whether the reveal is paced right, whether
/// the camera's swell is a rhythm or a lurch, whether the orrery turns at a
/// rate that reads as an instrument or as a spinner. Those are questions for
/// somebody watching, and the only way to watch them used to be to play four
/// minutes of waves and a midboss and hope the turn came when it was
/// convenient.
///
/// So the background gets what an attack got when `practice_functions` was
/// written: a way to run it on its own, immediately, as many times as you
/// like. It is the same argument and it takes the same shape -- **written as
/// content rather than as a debug view**, so what is being looked at is the
/// stage's own console, its own field, its own frame and its own camera,
/// rather than a diagnostic that would have to be judged twice.
///
/// **It loops, and the cut back to phase A is a cut.** `bg_set_omen` is
/// one-way on purpose, because a stage turns once; a review tool wants to see
/// the turn again without quitting to the rack, so this rewinds it. What that
/// draws is the camera jumping from flying height back to nine hundred units
/// up, which is a hard cut and reads as one -- and a hard cut is the right
/// thing here, because the two poses are what is being compared and a cut is
/// how you compare two poses.
///
/// **Nothing in it can touch the save**, on the terms `stage_drafts` sets
/// out: `id` is the empty string, so there is no stage to file a clear
/// against, and there is no boss for `on_boss_beaten` to fire on, so the path
/// that reaches `progress_record` is never entered at all.
///
/// Deleting this file and its line in `rack_list` removes the whole feature,
/// which is deliberate -- it is a tool for a stage that is being built, and
/// the day the Sanctum's hall is finished is the day this card should stop
/// being on the rack.

// How long the approach is held, how long the open hall is held afterwards,
// and how many times round. The reveal itself takes `BG_OMEN_TIME` between
// the two and is the thing being looked at, so both holds are long enough to
// read the pose either side of it and no longer.
#macro PREVIEW_HOLD_A (7 * FPS)
#macro PREVIEW_HOLD_B (15 * FPS)
#macro PREVIEW_CYCLES 12

/// @desc The card, shaped exactly like a stage.
///
///       **`build` is defined, unlike the drafting table's**, because this
///       one genuinely is a run -- a field, a player, a console and a
///       background flying. What keeps it away from the save is the empty id
///       and the absence of a boss, which are the same two locks and are both
///       load-bearing: a run reaches `progress_record` only through
///       `on_boss_beaten`, and there is nobody here to beat.
///
///       `bosses` is absent rather than empty, which is what makes
///       `practice_available` answer false -- there are no attacks to list,
///       and X on the rack does nothing rather than opening an empty panel.
function preview_stage_def() {
    return {
        id: "",
        name: "THE EMPTY ARCHIVES",
        subtitle: "Mika's hall, and nothing in it",
        needs: 0,
        make_bg: bg_sanctum,
        build: preview_stage_script,
        // One, so the console's ledger draws a single socket rather than
        // fourteen it will never fill. There is nothing here to grade.
        encounters: 1,
        preview: true,
    };
}

/// @desc Is this rack entry the review card rather than a stage?
///
///       **Read through `[$ ]`, because every other entry lacks the field**,
///       and a bare `_def.preview` on one of them raises rather than
///       answering `undefined` -- the trap `stage_is_draft` is written around
///       one file over, and the one `practice_bosses` is written around one
///       further.
///
///       It exists so the rack can say what the card is. "NOT YET CLEARED" is
///       true of it and is a lie about it: there is no boss on it, so there
///       is nothing that could ever clear it, and a card advertising a
///       condition it cannot meet is a card that reads as broken.
function stage_is_preview(_def) {
    if (_def == undefined) return false;
    return _def[$ "preview"] ?? false;
}

/// @desc The running order: phase A, the reveal, phase B, and round again.
///
///       **The first rewind is a no-op and is written anyway.** Leaving it
///       out would make the first pass through the loop a different shape
///       from every later one, which is exactly the sort of asymmetry that
///       ends up mattering the day somebody changes the timings.
function preview_stage_script() {
    var _e = [];
    var _t = 40;
    for (var _i = 0; _i < PREVIEW_CYCLES; _i++) {
        array_push(_e, ev(_t, wave_bg_rewind()));
        _t += PREVIEW_HOLD_A;
        array_push(_e, ev(_t, wave_bg_omen()));
        _t += BG_OMEN_TIME + PREVIEW_HOLD_B;
    }
    return _e;
}
