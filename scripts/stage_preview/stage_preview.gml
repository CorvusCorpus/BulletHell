/// @desc The review card: a rack card that flies a background with no
///       enemies, looping its turn, so it can be looked at without playing
///       the stage. It flies the 3D wood (`bg_wood`), Velka's forest rebuilt
///       in real geometry; stage two still flies the old corridor, for
///       comparison.
///
/// Each loop rewinds the turn (`bg_clear_omen`), which is a hard cut back to
/// the night wood. `id` is empty and there is no boss, so it can never write
/// to the save. Delete this file and its line in `rack_list` to remove the
/// feature.

// Hold on the night wood, hold on the blood wood after the turn (which takes
// `BG_OMEN_TIME`), and how many loops.
#macro PREVIEW_HOLD_A (20 * FPS)
#macro PREVIEW_HOLD_B (15 * FPS)
#macro PREVIEW_CYCLES 12

/// @desc The card, shaped like a stage def. Unlike the drafting table it has a
///       `build`, since it is a real run. No `bosses` field, so
///       `practice_available` is false and X on the rack does nothing.
function preview_stage_def() {
    return {
        id: "",
        name: "THE DEEP WOOD",
        subtitle: "Velka's wood in three dimensions, and nothing in it",
        needs: 0,
        make_bg: bg_wood,
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

/// @desc The running order: rewind, hold on the night wood, turn, hold on
///       the blood wood; `PREVIEW_CYCLES` times. (The first rewind is a
///       no-op.)
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
