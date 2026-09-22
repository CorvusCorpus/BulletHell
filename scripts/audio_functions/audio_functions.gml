/// @desc Sound effects.
///
/// Nothing calls `audio_play_sound` directly. `sfx(cue)` only counts a request
/// and may be called any number of times (e.g. once per bullet fired);
/// `sfx_step()` resolves each frame into at most one voice per cue and at most
/// `SFX_VOICES` voices in total, highest priority first, with the request count
/// raising the gain and lowering the pitch. This stops a volley of hundreds of
/// bullets from starting hundreds of voices.
///
/// `global.audio_on` is false under both harnesses; it is checked only at the
/// point a voice would start, so everything else runs normally and
/// `sfx_played` records what would have sounded (read by `test_audio_budget`).
/// Gameplay code never reads anything from this file (pitch is randomised).

/// @desc Which cue; indexes the table in `audio_init`.
enum Sfx {
    ShotSoft,
    ShotSharp,
    ShotHeavy,
    LaserCharge,
    LaserFire,

    // Used by `Demon Sealing Hex`: a figure closing, scattering, being pulled
    // in and detonating.
    WardClose,
    WardScatter,
    WardPull,
    WardBurst,

    PShot,
    Graze,
    Item,
    EnemyHit,
    EnemyDie,

    Hit,
    Bomb,
    PlayerDown,

    BossAppear,
    SpellDeclare,
    SpellBreak,
    SpellSurvive,
    Capture,
    BossDie,

    UiMove,
    UiSelect,
    UiBack,
    UiDeny,
    Pause,

    COUNT
}

/// @desc One row of the cue table.
///       `gap`: minimum frames between two voices of this cue.
///       `swell`: how much a frame's request count can raise the gain (pitch
///       drops by a third of it).
///       `vary`: random pitch variation either side.
///       `prio`: GameMaker voice priority, and the order `sfx_step` spends its
///       per-frame voice budget in.
function sfx_cue(_snd, _gain, _gap, _prio, _swell = 0, _vary = 0.0) {
    return {
        snd: _snd, gain: _gain, gap: _gap, prio: _prio,
        swell: _swell, vary: _vary,
    };
}

/// @desc Build the cue table and per-frame state. Called once from `obj_boot`,
///       with `_on` false under the test and screenshot harnesses so they make
///       no sound. The master gain is zeroed as well as the flag, to cover any
///       sound started outside this file.
function audio_init(_on = true) {
    global.audio_on = _on;
    audio_master_gain(_on ? SFX_MASTER : 0);

    global.sfx_table = array_create(Sfx.COUNT, undefined);
    var _t = global.sfx_table;

    // `tools/make_sfx.py` normalises every WAV by loudness (RMS of its loudest
    // 100ms window), and these gains were computed from the measured files.
    //
    //                          sound              gain  gap  prio swell vary
    _t[Sfx.ShotSoft]    = sfx_cue(snd_shot_soft,    0.52,  4,  20, 0.55, 0.05);
    _t[Sfx.ShotSharp]   = sfx_cue(snd_shot_sharp,   0.54,  4,  20, 0.55, 0.06);
    _t[Sfx.ShotHeavy]   = sfx_cue(snd_shot_heavy,   0.52,  6,  22, 0.50, 0.04);
    _t[Sfx.LaserCharge] = sfx_cue(snd_laser_charge, 0.43, 26,  55, 0.20, 0.03);
    _t[Sfx.LaserFire]   = sfx_cue(snd_laser_fire,   0.42, 14,  60, 0.25, 0.03);

    // Long gaps so a ward cue can't retrigger during its own movement.
    _t[Sfx.WardClose]   = sfx_cue(snd_ward_close,   0.44, 30,  62, 0.00, 0.00);
    _t[Sfx.WardScatter] = sfx_cue(snd_ward_scatter, 0.45, 40,  86, 0.00, 0.00);
    _t[Sfx.WardPull]    = sfx_cue(snd_ward_pull,    0.46,100,  87, 0.00, 0.00);
    _t[Sfx.WardBurst]   = sfx_cue(snd_ward_burst,   0.54, 40,  91, 0.00, 0.00);

    // The player's shot plays constantly, so it is kept quiet.
    _t[Sfx.PShot]       = sfx_cue(snd_pshot,        0.47,  5,  10, 0.00, 0.05);
    _t[Sfx.Graze]       = sfx_cue(snd_graze,        0.67,  5,  45, 0.35, 0.07);
    _t[Sfx.Item]        = sfx_cue(snd_item,         0.53,  4,  30, 0.40, 0.08);
    _t[Sfx.EnemyHit]    = sfx_cue(snd_enemy_hit,    0.49,  4,  15, 0.45, 0.09);
    _t[Sfx.EnemyDie]    = sfx_cue(snd_enemy_die,    0.56,  5,  50, 0.35, 0.06);

    _t[Sfx.Hit]         = sfx_cue(snd_hit,          0.53, 20,  95, 0.00, 0.02);
    _t[Sfx.Bomb]        = sfx_cue(snd_bomb,         0.68, 30,  92, 0.00, 0.00);
    _t[Sfx.PlayerDown]  = sfx_cue(snd_player_down,  0.59, 60,  98, 0.00, 0.00);

    _t[Sfx.BossAppear]  = sfx_cue(snd_boss_appear,  0.45, 60,  90, 0.00, 0.00);
    _t[Sfx.SpellDeclare]= sfx_cue(snd_spell_declare,0.51, 45,  94, 0.00, 0.00);
    _t[Sfx.SpellBreak]  = sfx_cue(snd_spell_break,  0.48, 30,  88, 0.00, 0.00);
    _t[Sfx.SpellSurvive]= sfx_cue(snd_spell_survive,0.51, 30,  88, 0.00, 0.00);
    _t[Sfx.Capture]     = sfx_cue(snd_capture,      0.52, 30,  93, 0.00, 0.00);
    _t[Sfx.BossDie]     = sfx_cue(snd_boss_die,     0.81, 90,  99, 0.00, 0.00);

    _t[Sfx.UiMove]      = sfx_cue(snd_ui_move,      0.54,  4,  70, 0.00, 0.03);
    _t[Sfx.UiSelect]    = sfx_cue(snd_ui_select,    0.45, 10,  80, 0.00, 0.00);
    _t[Sfx.UiBack]      = sfx_cue(snd_ui_back,      0.41, 10,  80, 0.00, 0.00);
    _t[Sfx.UiDeny]      = sfx_cue(snd_ui_deny,      0.41, 14,  80, 0.00, 0.00);
    _t[Sfx.Pause]       = sfx_cue(snd_pause,        0.52, 10,  85, 0.00, 0.00);

    global.sfx_want = array_create(Sfx.COUNT, 0);
    global.sfx_cool = array_create(Sfx.COUNT, 0);

    // The cues that sounded this frame (read by the suites).
    global.sfx_played = array_create(SFX_VOICES, -1);
    global.sfx_played_n = 0;

    // Running totals of requests and voices, for `test_audio_budget`.
    global.sfx_requests = 0;
    global.sfx_voices = 0;

    // The room the pending requests were made in (`sfx_sync_room`).
    global.sfx_room = -1;
}

/// @desc Drop requests and cooldowns left over from a room the game has left,
///       so a cue requested on a run's last frame doesn't play on the next
///       screen. Called from `sfx` as well as `sfx_step`: a new room's Create
///       can request a cue (e.g. `BossAppear` in practice) before its first
///       Step, and checking only in the Step would throw that request away.
function sfx_sync_room() {
    if (room == global.sfx_room) return;
    global.sfx_room = room;
    for (var _i = 0; _i < Sfx.COUNT; _i++) {
        global.sfx_want[_i] = 0;
        global.sfx_cool[_i] = 0;
    }
}

/// @desc Request a cue. Safe to call any number of times per frame; it only
///       increments a counter for `sfx_step`.
function sfx(_cue) {
    if (_cue < 0 || _cue >= Sfx.COUNT) return;
    sfx_sync_room();
    global.sfx_want[_cue]++;
    global.sfx_requests++;
}

/// @desc Request a cue `_n` times at once (e.g. `fire_ring` for a whole ring).
function sfx_many(_cue, _n) {
    if (_cue < 0 || _cue >= Sfx.COUNT || _n <= 0) return;
    sfx_sync_room();
    global.sfx_want[_cue] += _n;
    global.sfx_requests += _n;
}

/// @desc 0..1: how much a frame's request count swells a cue. Logarithmic in
///       the count, reaching 1 at `SFX_SWELL_FULL` requests.
function sfx_swell(_n) {
    if (_n <= 1) return 0;
    return min(1, ln(_n) / ln(SFX_SWELL_FULL));
}

/// @desc Resolve one frame of requests into at most `SFX_VOICES` voices,
///       highest priority first. Call it at the top of a controller's Step,
///       before any `exit`, so an early return can't skip it (this adds one
///       frame of latency).
function sfx_step() {
    sfx_sync_room();

    global.sfx_played_n = 0;

    for (var _v = 0; _v < SFX_VOICES; _v++) {
        // The best candidate: requested, off cooldown, highest priority.
        var _best = -1;
        var _best_prio = -1;
        for (var _c = 0; _c < Sfx.COUNT; _c++) {
            if (global.sfx_want[_c] <= 0) continue;
            if (global.sfx_cool[_c] > 0) continue;
            var _p = global.sfx_table[_c].prio;
            if (_p > _best_prio) {
                _best_prio = _p;
                _best = _c;
            }
        }
        if (_best < 0) break;

        sfx_play_now(_best, global.sfx_want[_best]);
        global.sfx_want[_best] = 0;
    }

    // Requests that didn't get a voice are dropped, not carried over.
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        global.sfx_want[_c] = 0;
        if (global.sfx_cool[_c] > 0) global.sfx_cool[_c]--;
    }
}

/// @desc Start one voice of `_cue`, sized by how many asked for it. The only
///       place a sound starts, and the only place `global.audio_on` is checked.
function sfx_play_now(_cue, _n) {
    var _e = global.sfx_table[_cue];
    var _swell = sfx_swell(_n) * _e.swell;

    // A bigger volley plays louder and slightly lower.
    var _gain = _e.gain * (1 + _swell) * SFX_MASTER;
    var _pitch = (1 - _swell * 0.34) + random_range(-_e.vary, _e.vary);

    global.sfx_cool[_cue] = _e.gap;
    if (global.sfx_played_n < SFX_VOICES) {
        global.sfx_played[global.sfx_played_n] = _cue;
        global.sfx_played_n++;
    }
    global.sfx_voices++;

    if (!global.audio_on) return;
    audio_play_sound(_e.snd, _e.prio, false, _gain, 0, max(0.25, _pitch));
}

/// @desc Did this cue sound this frame? (For the suites.)
function sfx_sounded(_cue) {
    for (var _i = 0; _i < global.sfx_played_n; _i++) {
        if (global.sfx_played[_i] == _cue) return true;
    }
    return false;
}

/// @desc Clear every pending request, cooldown and counter (for suites).
function sfx_reset() {
    for (var _i = 0; _i < Sfx.COUNT; _i++) {
        global.sfx_want[_i] = 0;
        global.sfx_cool[_i] = 0;
    }
    global.sfx_played_n = 0;
    global.sfx_requests = 0;
    global.sfx_voices = 0;
    // Adopt the current room so the next `sfx_sync_room` doesn't wipe again.
    global.sfx_room = room;
}

// ---------------------------------------------------------------------------
// What a thing sounds like
// ---------------------------------------------------------------------------

/// @desc Which shot cue a bullet shape fires with: pointed shapes are sharp,
///       large drawn shapes heavy, everything else (including any shape not
///       listed) soft. Kept here rather than in the generated `bullet_table`
///       so changing a sound doesn't require re-running `make_bullets.py`.
function sfx_for_shape(_shape) {
    switch (_shape) {
        case BSHAPE_RICE:
        case BSHAPE_DART:
        case BSHAPE_NEEDLE:
        case BSHAPE_OVAL:
        case BSHAPE_MOTE:
            return Sfx.ShotSharp;

        case BSHAPE_CARD:
        case BSHAPE_CRYSTAL:
        case BSHAPE_RUNE:
        case BSHAPE_STAR:
        case BSHAPE_STAR6:
        case BSHAPE_RING:
            return Sfx.ShotHeavy;
    }
    return Sfx.ShotSoft;
}
