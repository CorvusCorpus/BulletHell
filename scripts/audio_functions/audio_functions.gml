/// @desc Every sound the game makes, and the one rule that keeps it playable.
///
/// **Nothing here plays a sound. `sfx` casts a vote and `sfx_step` counts
/// them**, once a frame, and that inversion is the whole file.
///
/// A boss non-spell fires a hundred and twenty bullets on a single frame, and
/// a spell that opens with a wall fires three hundred. If `fire` played a
/// sound, that frame would start a hundred and twenty voices of the same
/// 75-millisecond cue within a few samples of each other -- which is not a
/// hundred and twenty shots, it is one shot at a hundred and twenty times the
/// amplitude, comb-filtered by its own copies into a burst of noise. It would
/// also exhaust the mixer's voice pool, so the *next* thing that mattered --
/// the hit, the graze, the spell being named -- would be the thing that failed
/// to sound.
///
/// The usual answer is a cooldown checked at the call site, and it is the
/// wrong shape: it puts the rule in a hundred places, it fires on whichever
/// bullet happened to be first rather than on the volley, and it cannot know
/// that a hundred and twenty went out rather than four. So instead:
///
///   - **`sfx(cue)` is free and idempotent-ish.** It increments a counter.
///     Every bullet, every graze, every collected shard may call it, as often
///     as it likes, and nothing can go wrong.
///   - **`sfx_step()` resolves the frame.** At most one voice per cue, at most
///     `SFX_VOICES` cues in total, and the *count* is what sets the gain and
///     the pitch -- so a volley of a hundred and twenty sounds bigger and
///     lower than a volley of four, out of one voice.
///
/// That makes "a pattern must not machine-gun the mixer" a property of the API
/// rather than a rule every caller has to remember, which is the same bargain
/// `fire`'s delay marks and the near layer's keep-out window make: a thing
/// that cannot be got wrong beats a thing that has to be got right.
///
/// **Decoration, and it must stay that way.** Nothing in `scripts/` may read
/// anything this file writes back into a rule -- same contract `fx_functions`
/// keeps, and for the same reason: `sfx_step` picks a random pitch every time
/// it plays anything, so a rule that read it would behave differently on every
/// run and could not be asserted on at all.
///
/// **The suites can see everything without hearing it.** `global.audio_on` is
/// false under both harnesses, and it is checked at the single point where a
/// sound would actually start -- so the whole decision runs, `sfx_played` says
/// what *would* have sounded, and `test_audio_budget` reads it. See
/// `audio_init` for why silence under a harness is not optional.

/// @desc Which cue. The order is the order in `tools/make_sfx.py`, and the
///       table below is indexed by it.
enum Sfx {
    ShotSoft,
    ShotSharp,
    ShotHeavy,
    LaserCharge,
    LaserFire,

    // **The ward cues are not hex-specific and are deliberately not named for
    // it.** `Demon Sealing Hex` was a draft when these were written, and a cue
    // called `HexImplode` would have been four sounds to rename the day it
    // moved to a real boss. It has moved -- it is Velka's -- and not one of
    // these had to change, which is the argument made. What they describe is a
    // *figure* being closed, thrown out, pulled in and detonated, which is a
    // shape any attack of that kind wants.
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
///
///       `gap` is **the minimum frames between two voices of this cue**, and
///       it is where the mix is actually tuned. A shot at 4 is fifteen a
///       second, which is about what the genre sounds like; at 1 it is sixty
///       and the pattern turns into static. The graze is at 5 for a different
///       reason -- it is a *reward*, and a reward paid sixty times a second
///       stops reading as one.
///
///       `swell` is how much a coalesced volley is allowed to grow: gain rises
///       by up to `swell` and pitch falls by a fraction of it, which is what a
///       lot of something sounds like. Zero for anything that can only ever
///       happen once, because a cue with nothing to coalesce should not carry
///       arithmetic that never runs.
///
///       `vary` is random pitch either side, and it is the difference between
///       a shot cue and a woodpecker. **The one place randomness is allowed
///       here**, and it is safe because nothing reads it back.
///
///       `prio` is both GameMaker's own voice priority and the order
///       `sfx_step` spends its per-frame budget in. The spell being named
///       outranks a shard being collected on the frame both happen, which is
///       the frame after a boss phase ends -- when fifty shards and a
///       declaration land together.
function sfx_cue(_snd, _gain, _gap, _prio, _swell = 0, _vary = 0.0) {
    return {
        snd: _snd, gain: _gain, gap: _gap, prio: _prio,
        swell: _swell, vary: _vary,
    };
}

/// @desc Build the cue table and the per-frame state. Called once, from
///       `obj_boot`, like every other pool in the game.
///
///       **Both harnesses are silent, and that is not a courtesy.**
///       `tools/test.py` and `tools/shot.py` run the game between one and
///       thirty-two times per invocation, minimised, while somebody is working
///       on something else -- see `build.run_game`, which already goes to some
///       length to stop the window taking the foreground. A build that also
///       played a boss death through their speakers thirty-two times would
///       undo the whole of that, and it is the same complaint one notch
///       louder.
///
///       `audio_master_gain` is set as well as the flag. The flag is what the
///       suites read; the gain is what covers anything that starts a sound
///       without going through this file, which today is nothing and tomorrow
///       might not be.
function audio_init(_on = true) {
    global.audio_on = _on;
    audio_master_gain(_on ? SFX_MASTER : 0);

    global.sfx_table = array_create(Sfx.COUNT, undefined);
    var _t = global.sfx_table;

    // **The gain column is computed, not guessed.** Every WAV is normalised
    // to a target loudness by `tools/make_sfx.py` -- RMS of its loudest 100ms
    // window, not its peak -- so a gain here is a straight statement about
    // where a cue sits in the mix, and the numbers were derived by measuring
    // each file and solving for the effective level wanted. Re-derive them
    // rather than nudging them if the generator's levels change.
    //
    //                          sound              gain  gap  prio swell vary
    _t[Sfx.ShotSoft]    = sfx_cue(snd_shot_soft,    0.52,  4,  20, 0.55, 0.05);
    _t[Sfx.ShotSharp]   = sfx_cue(snd_shot_sharp,   0.54,  4,  20, 0.55, 0.06);
    _t[Sfx.ShotHeavy]   = sfx_cue(snd_shot_heavy,   0.52,  6,  22, 0.50, 0.04);
    _t[Sfx.LaserCharge] = sfx_cue(snd_laser_charge, 0.43, 26,  55, 0.20, 0.03);
    _t[Sfx.LaserFire]   = sfx_cue(snd_laser_fire,   0.42, 14,  60, 0.25, 0.03);

    // **The ward's own moments, and they outrank the volleys landing over
    // them.** Each says something the player has to act on and each happens
    // once in twelve seconds, so a gap long enough to cover the movement it
    // belongs to is right -- `WardPull` at 100 frames cannot retrigger inside
    // its own 108-frame collapse, which would otherwise stack two copies of a
    // rising tone and turn a telegraph into a chord.
    _t[Sfx.WardClose]   = sfx_cue(snd_ward_close,   0.44, 30,  62, 0.00, 0.00);
    _t[Sfx.WardScatter] = sfx_cue(snd_ward_scatter, 0.45, 40,  86, 0.00, 0.00);
    _t[Sfx.WardPull]    = sfx_cue(snd_ward_pull,    0.46,100,  87, 0.00, 0.00);
    _t[Sfx.WardBurst]   = sfx_cue(snd_ward_burst,   0.54, 40,  91, 0.00, 0.00);

    // **The player's own shot is the quietest thing in the game.** It fires
    // twenty volleys a second for the whole of a stage; anything audible
    // enough to notice once is unbearable by the third minute.
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

    // What actually started this frame, for the suites and for anything that
    // ever wants to draw a meter. Kept the way every other pool here is: the
    // array beyond the count is last frame's, so this allocates nothing.
    global.sfx_played = array_create(SFX_VOICES, -1);
    global.sfx_played_n = 0;

    // Totals, so `test_audio_budget` can state the thing that matters as a
    // ratio: how many requests came in against how many voices went out.
    global.sfx_requests = 0;
    global.sfx_voices = 0;

    // Which room the votes standing in `sfx_want` were cast in. See
    // `sfx_step`: a request made on the last partial frame of a screen must
    // not sound on the next one.
    global.sfx_room = -1;
}

/// @desc Drop votes cast in a room the game has already left.
///
///       **The room is noticed on the first vote *or* step after the change,
///       not on the first step**, and getting that wrong cost the boss's
///       arrival cue. Entering `room_game` runs `obj_game`'s Create -- which
///       in attack practice calls `boss_spawn`, which asks for
///       `Sfx.BossAppear` -- and only then the first Step. With the check
///       living in `sfx_step` alone, that first step saw a room it had not
///       seen before and cleared the request the Create had just made: a cue
///       requested *after* the change, thrown away by the guard against
///       requests made before it.
///
///       Called from `sfx` as well, it is one integer compare in the hottest
///       path in the game and the votes on either side of a room boundary end
///       up on the correct side of it. Same bargain `BMod` and `BQ` make for
///       the ninety per cent of bullets that carry neither.
function sfx_sync_room() {
    if (room == global.sfx_room) return;
    global.sfx_room = room;
    for (var _i = 0; _i < Sfx.COUNT; _i++) {
        global.sfx_want[_i] = 0;
        // Cooldowns go too: a cue that sounded a moment ago on a screen the
        // player has left must not be suppressed on the one they arrived at.
        global.sfx_cool[_i] = 0;
    }
}

/// @desc Ask for a cue. **Call this as often as you like** -- once per bullet,
///       once per shard, once per grazed bullet. It increments a counter and
///       does nothing else, and `sfx_step` decides what that becomes.
function sfx(_cue) {
    if (_cue < 0 || _cue >= Sfx.COUNT) return;
    sfx_sync_room();
    global.sfx_want[_cue]++;
    global.sfx_requests++;
}

/// @desc Ask for a cue `_n` times at once, for a caller that already knows how
///       many. `fire_ring` knows it laid down thirty bullets without thirty
///       calls having to say so.
function sfx_many(_cue, _n) {
    if (_cue < 0 || _cue >= Sfx.COUNT || _n <= 0) return;
    sfx_sync_room();
    global.sfx_want[_cue] += _n;
    global.sfx_requests += _n;
}

/// @desc How loud one voice of a cue should be, given how many asked for it.
///
///       **Logarithmic, and that is the only honest curve for this.** Loudness
///       is roughly logarithmic in count anyway -- twice as many things make a
///       sound a fixed step louder, not twice as loud -- so a linear ramp
///       would put a forty-bullet volley off the top of the mix while leaving
///       four and eight sounding identical. `SFX_SWELL_FULL` is the count at
///       which a cue is as big as it is allowed to get.
function sfx_swell(_n) {
    if (_n <= 1) return 0;
    return min(1, ln(_n) / ln(SFX_SWELL_FULL));
}

/// @desc Resolve one frame of requests into at most `SFX_VOICES` voices.
///
///       **Called from the top of a controller's Step, before anything that
///       might `exit`.** That costs one frame of latency -- sixteen
///       milliseconds, well under the ear's ability to bind a sound to a
///       picture -- and buys that no early return can skip it. `obj_game`'s
///       Step has five `exit`s in it, three of which are the states where a
///       cue most needs to sound anyway: pausing, the result panel, and the
///       menu on it.
///
///       The budget is spent highest priority first, so on the busiest frame
///       in the game -- a spell ending, which pops the whole field into
///       shards, awards a capture and names the next attack -- what is heard
///       is the capture and the break rather than forty collected shards.
function sfx_step() {
    // **Votes do not cross a room boundary.** A cue requested on the last
    // partial frame of a run -- the death, say -- would otherwise be resolved
    // here on the title screen and play there, announcing an event that
    // happened on a screen the player has already left.
    //
    // Done by watching `room` rather than by asking every controller's Create
    // to remember, because that is three call sites today and four the day
    // somebody adds a screen. Same argument as `run_clear_field` being at the
    // entrance rather than on one path into it -- except that this one cannot
    // be forgotten at all. See `sfx_sync_room` for why `sfx` calls it too.
    sfx_sync_room();

    global.sfx_played_n = 0;

    for (var _v = 0; _v < SFX_VOICES; _v++) {
        // The best candidate: wanted, off cooldown, highest priority. A linear
        // scan of twenty-four rows, five times -- a hundred and twenty
        // compares a frame against the four thousand distance checks the
        // bullet pool already does, which is to say nothing at all.
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

    // **Everything left over is dropped, not held.** A request that could not
    // be afforded this frame is a request about something that has already
    // happened; carrying it forward would sound the shot after the bullet had
    // crossed half the field, and would let a busy second queue up a backlog
    // that plays out over the quiet one after it.
    for (var _c = 0; _c < Sfx.COUNT; _c++) {
        global.sfx_want[_c] = 0;
        if (global.sfx_cool[_c] > 0) global.sfx_cool[_c]--;
    }
}

/// @desc Start one voice of `_cue`, sized by how many asked for it.
///
///       **The single point at which a sound actually starts**, which is what
///       makes `global.audio_on` a one-line guarantee rather than a rule
///       spread over twenty call sites. Everything above this line runs under
///       a harness exactly as it does in play; only the last statement is
///       skipped.
function sfx_play_now(_cue, _n) {
    var _e = global.sfx_table[_cue];
    var _swell = sfx_swell(_n) * _e.swell;

    // Louder, and lower. **Both, because either alone reads as the wrong
    // thing**: gain on its own is the same shot turned up, and pitch on its
    // own is a different, larger object firing once. Together they are more of
    // the same object, which is what a volley is. The pitch drop is a third of
    // the gain rise because this set is deliberately narrow-band -- see
    // `tools/make_sfx.py` -- and a shot cue dragged a long way down lands in
    // the band the ceremony has to itself.
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

/// @desc Did this cue sound this frame? What the suites ask.
function sfx_sounded(_cue) {
    for (var _i = 0; _i < global.sfx_played_n; _i++) {
        if (global.sfx_played[_i] == _cue) return true;
    }
    return false;
}

/// @desc Forget every pending request and every cooldown. `sfx_step` does this
///       on a room change by itself; this is for a suite that wants a clean
///       frame without one.
function sfx_reset() {
    for (var _i = 0; _i < Sfx.COUNT; _i++) {
        global.sfx_want[_i] = 0;
        global.sfx_cool[_i] = 0;
    }
    global.sfx_played_n = 0;
    global.sfx_requests = 0;
    global.sfx_voices = 0;
    // Adopt the current room, so a reset is a clean frame *here* rather than a
    // clean frame that the next `sfx_sync_room` immediately wipes again.
    global.sfx_room = room;
}

// ---------------------------------------------------------------------------
// What a thing sounds like
// ---------------------------------------------------------------------------

/// @desc Which shot cue a bullet shape fires with.
///
///       **Three voices across eighteen shapes**, grouped by what the shape
///       reads as rather than by what it is: round things puff, pointed things
///       tick, and the big drawn ones land. That grouping is the entire reason
///       there are three cues and not one -- a pattern of needles and a
///       pattern of orbs are different patterns, and the sound should say so
///       before the eye has resolved which.
///
///       **It is here rather than in `bullet_table`**, which is the other
///       defensible home -- `SPIN` is a property of a shape and lives in
///       `tools/make_bullets.py` for exactly the reason a voice might. The
///       deciding argument is what re-running that generator costs: it redraws
///       eighteen sprites and rewrites every one of their frames, which is the
///       operation this project has twice shipped a blank sprite through. A
///       change to how a bullet *sounds* must not be able to blank a bullet.
///
///       A shape with no row falls through to the soft one, which is a sound
///       rather than a crash -- so a shape added tomorrow is quietly wrong
///       instead of loudly broken, and that is the right way round for
///       decoration.
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
