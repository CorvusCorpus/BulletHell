/// @desc The review card ("THE EMPTY ARCHIVES"): a rack card that flies stage
///       three's background with no enemies, looping approach -> reveal ->
///       open hall, so its motion can be watched without playing the stage.
///
/// Each loop rewinds the turn (`bg_clear_omen`), which is a hard cut back to
/// the approach camera. `id` is empty and there is no boss, so it can never
/// write to the save. Delete this file and its line in `rack_list` to remove
/// the feature.

// Hold on the approach, hold on the open hall after the reveal (which takes
// `BG_OMEN_TIME`), and how many loops.
#macro PREVIEW_HOLD_A (7 * FPS)
#macro PREVIEW_HOLD_B (15 * FPS)
#macro PREVIEW_CYCLES 12

/// @desc The card, shaped like a stage def. Unlike the drafting table it has a
///       `build`, since it is a real run. No `bosses` field, so
///       `practice_available` is false and X on the rack does nothing.
function preview_stage_def() {
    return {
        id: "",
        name: "THE EMPTY ARCHIVES",
        subtitle: "Mika's hall, and nothing in it",
        needs: 0,
        make_bg: bg_sanctum,
        build: preview_stage_script,
        encounters: 1,
        preview: true,
    };
}

/// @desc Is this rack entry the review card? (The rack labels it differently
///       from an uncleared stage.) Read with `[$ ]` because other entries
///       lack the field and a bare read would raise.
function stage_is_preview(_def) {
    if (_def == undefined) return false;
    return _def[$ "preview"] ?? false;
}

/// @desc The running order: rewind, hold on the approach, turn, hold on the
///       open hall; `PREVIEW_CYCLES` times. (The first rewind is a no-op.)
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
