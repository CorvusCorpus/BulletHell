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

    // A ring forming or caught; something flung outward; unused (its sound is
    // the charge's); a detonation. Used by Mika's rings and the sigil's seals.
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
    Charge,
    SpellCut,
    SpellDeclare,
    SpellBreak,
    SpellSurvive,
    Capture,
    BossDie,

    // The rank card's medals, one per `Mark` (see `sfx_for_mark`).
    MedalStone,
    MedalBronze,
    MedalSilver,
    MedalGold,
    MedalAmethyst,

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

    // `tools/make_sfx.py` writes every WAV at twice its loudness in the mix
    // (K-weighted), and prints the gain that brings it back down; these are
    // those gains.
    //
    //                          sound              gain  gap  prio swell vary
    _t[Sfx.ShotSoft]    = sfx_cue(snd_shot_soft,    0.56,  4,  20, 0.55, 0.05);
    _t[Sfx.ShotSharp]   = sfx_cue(snd_shot_sharp,   0.50,  4,  20, 0.55, 0.06);
    _t[Sfx.ShotHeavy]   = sfx_cue(snd_shot_heavy,   0.50,  6,  22, 0.50, 0.04);
    _t[Sfx.LaserCharge] = sfx_cue(snd_laser_charge, 0.50, 26,  55, 0.20, 0.03);
    _t[Sfx.LaserFire]   = sfx_cue(snd_laser_fire,   0.75, 14,  60, 0.25, 0.03);

    // Long gaps so a ward cue can't retrigger during its own movement.
    _t[Sfx.WardClose]   = sfx_cue(snd_ward_close,   0.56, 30,  62, 0.00, 0.00);
    _t[Sfx.WardScatter] = sfx_cue(snd_ward_scatter, 0.60, 40,  86, 0.00, 0.00);
    _t[Sfx.WardPull]    = sfx_cue(snd_ward_pull,    0.50,100,  87, 0.00, 0.00);
    _t[Sfx.WardBurst]   = sfx_cue(snd_ward_burst,   0.85, 40,  91, 0.00, 0.00);

    // A boss gathering itself before each attack (`boss_charge`). The sound
    // peaks just before `BOSS_CHARGE_LEAD` runs out.
    _t[Sfx.Charge]      = sfx_cue(snd_ward_pull,    0.50,100,  87, 0.00, 0.00);

    // The player's shot plays constantly, so it is kept quiet.
    _t[Sfx.PShot]       = sfx_cue(snd_pshot,        0.50,  5,  10, 0.00, 0.05);
    _t[Sfx.Graze]       = sfx_cue(snd_graze,        0.60,  5,  45, 0.35, 0.07);
    _t[Sfx.Item]        = sfx_cue(snd_item,         0.50,  4,  30, 0.40, 0.08);
    _t[Sfx.EnemyHit]    = sfx_cue(snd_enemy_hit,    0.50,  4,  15, 0.45, 0.09);
    _t[Sfx.EnemyDie]    = sfx_cue(snd_enemy_die,    0.72,  5,  50, 0.35, 0.06);

    _t[Sfx.Hit]         = sfx_cue(snd_hit,          0.87, 20,  95, 0.00, 0.02);
    _t[Sfx.Bomb]        = sfx_cue(snd_bomb,         0.91, 30,  92, 0.00, 0.00);
    _t[Sfx.PlayerDown]  = sfx_cue(snd_player_down,  0.59, 60,  98, 0.00, 0.00);

    _t[Sfx.BossAppear]  = sfx_cue(snd_boss_appear,  0.57, 60,  90, 0.00, 0.00);
    // A spell's cut-in opening, then its declaration (timed by
    // `boss_cutin_step` to land as the caster's eyes open).
    _t[Sfx.SpellCut]    = sfx_cue(snd_spell_cut,    0.53, 45,  94, 0.00, 0.00);
    _t[Sfx.SpellDeclare]= sfx_cue(snd_spell_declare,0.66, 45,  94, 0.00, 0.00);
    _t[Sfx.SpellBreak]  = sfx_cue(snd_spell_break,  0.65, 30,  88, 0.00, 0.00);
    _t[Sfx.SpellSurvive]= sfx_cue(snd_spell_survive,0.50, 30,  88, 0.00, 0.00);
    _t[Sfx.Capture]     = sfx_cue(snd_capture,      0.50, 30,  93, 0.00, 0.00);
    _t[Sfx.BossDie]     = sfx_cue(snd_boss_die,     0.97, 90,  99, 0.00, 0.00);

    _t[Sfx.MedalStone]  = sfx_cue(snd_medal_stone,  0.50, 30,  93, 0.00, 0.00);
    _t[Sfx.MedalBronze] = sfx_cue(snd_medal_bronze, 0.50, 30,  93, 0.00, 0.00);
    _t[Sfx.MedalSilver] = sfx_cue(snd_medal_silver, 0.50, 30,  93, 0.00, 0.00);
    _t[Sfx.MedalGold]   = sfx_cue(snd_medal_gold,   0.55, 30,  93, 0.00, 0.00);
    _t[Sfx.MedalAmethyst]=sfx_cue(snd_medal_amethyst,0.57, 30,  93, 0.00, 0.00);

    _t[Sfx.UiMove]      = sfx_cue(snd_ui_move,      0.50,  4,  70, 0.00, 0.03);
    _t[Sfx.UiSelect]    = sfx_cue(snd_ui_select,    0.50, 10,  80, 0.00, 0.00);
    _t[Sfx.UiBack]      = sfx_cue(snd_ui_back,      0.50, 10,  80, 0.00, 0.00);
    _t[Sfx.UiDeny]      = sfx_cue(snd_ui_deny,      0.50, 14,  80, 0.00, 0.00);
    _t[Sfx.Pause]       = sfx_cue(snd_pause,        0.50, 10,  85, 0.00, 0.00);

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

    // The music (see `music`): the track playing and its voice, the frame's
    // request, the room it was asked for in, whether it is paused, and the
    // voices still fading out.
    global.music_snd = noone;
    global.music_voice = -1;
    global.music_want = noone;
    global.music_asked = false;
    global.music_room = -1;
    global.music_held = false;
    global.music_fading = [];
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
    music_step();

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

// ---------------------------------------------------------------------------
// Music
//
// Like `sfx`, `music(snd)` only asks. `music_step` (run by `sfx_step`) acts on
// the frame's last request, so a practice run that asks for its stage's track
// and then, on the same frame, for its boss's starts on the boss's. A change
// of track crossfades over `MUSIC_FADE` frames, and leaving the room the music
// was asked for in fades it out. Both tracks are placeholders
// (`tools/make_music.py`).
// ---------------------------------------------------------------------------

/// @desc Ask for `_snd` (a streamed sound, or `noone` for silence) as the
///       music. Asking for the track already playing leaves it playing.
function music(_snd) {
    music_sync_room();
    global.music_want = _snd;
    global.music_asked = true;
}

/// @desc Fade the music out when the room it was asked for in is left.
function music_sync_room() {
    if (room == global.music_room) return;
    global.music_room = room;
    global.music_held = false;
    global.music_want = noone;
    global.music_asked = true;
}

/// @desc Pause the music (`true`) or carry on (`false`); a run holds it
///       while its pause menu is open. Safe to call every frame.
function music_hold(_held) {
    if (_held == global.music_held) return;
    global.music_held = _held;
    if (!global.audio_on || global.music_voice < 0) return;
    if (_held) audio_pause_sound(global.music_voice);
    else audio_resume_sound(global.music_voice);
}

/// @desc Act on the frame's request, and stop voices that have faded out.
function music_step() {
    music_sync_room();

    for (var _i = array_length(global.music_fading) - 1; _i >= 0; _i--) {
        var _f = global.music_fading[_i];
        _f.t--;
        if (_f.t <= 0) {
            if (global.audio_on) audio_stop_sound(_f.voice);
            array_delete(global.music_fading, _i, 1);
        }
    }

    // A track stopped from outside is no longer playing, so asking for it
    // again starts it from the top. A run's Create stops all audio, which is
    // what restarts the music on a retry.
    if (global.music_voice >= 0 && global.audio_on
        && !audio_is_playing(global.music_voice)
        && !audio_is_paused(global.music_voice)) {
        global.music_voice = -1;
        global.music_snd = noone;
        global.music_held = false;
    }

    if (!global.music_asked) return;
    global.music_asked = false;
    if (global.music_want == global.music_snd) return;

    // A crossfade: the old voice fades and is stopped once silent, and the
    // new one rises from silence. A track starting from silence starts at
    // full.
    var _ms = MUSIC_FADE * 1000 / FPS;
    var _from = 0;
    if (global.music_voice >= 0) {
        if (global.audio_on) audio_sound_gain(global.music_voice, 0, _ms);
        array_push(global.music_fading,
                   { voice: global.music_voice, t: MUSIC_FADE });
    } else {
        _from = MUSIC_MASTER;
    }
    global.music_snd = global.music_want;
    global.music_voice = -1;
    if (global.music_snd == noone || !global.audio_on) return;
    global.music_voice = audio_play_sound(global.music_snd, 100, true, _from);
    audio_sound_gain(global.music_voice, MUSIC_MASTER, _ms);
    if (global.music_held) audio_pause_sound(global.music_voice);
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
        case BSHAPE_KNIFE:
        case BSHAPE_ARROW:
        case BSHAPE_OVAL:
        case BSHAPE_MOTE:
        case BSHAPE_NOVA:
            return Sfx.ShotSharp;

        case BSHAPE_CARD:
        case BSHAPE_CRYSTAL:
        case BSHAPE_RUNE:
        case BSHAPE_STAR:
        case BSHAPE_SHURIKEN:
        case BSHAPE_RING:
            return Sfx.ShotHeavy;
    }
    return Sfx.ShotSoft;
}

/// @desc The cue for a medal of this tier (`Mark`): each rung's is higher and
///       fuller than the one below.
function sfx_for_mark(_tier) {
    switch (_tier) {
        case Mark.Stone:  return Sfx.MedalStone;
        case Mark.Bronze: return Sfx.MedalBronze;
        case Mark.Silver: return Sfx.MedalSilver;
        case Mark.Gold:   return Sfx.MedalGold;
    }
    return Sfx.MedalAmethyst;
}
