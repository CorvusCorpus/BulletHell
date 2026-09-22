/// @desc The scenes `tools/shot.py` can photograph: the list, which room each
///       is posed in, how each is posed, and when its shutter fires.
///
/// The list lives here so `obj_boot` can refuse an unknown scene name with an
/// error instead of hanging.

/// @desc Every scene name. Mika's are generated one per slot of his table
///       (`mika_n1` ... `mika_s8`); `tools/shot.py` generates the same names.
function shot_scene_list() {
    var _l = ["title", "practice", "stage", "focus", "bomb", "hit", "peril",
              "midboss",
              "declare", "spell", "boss", "laser", "rays", "clear", "items",
              "pause",
              "result", "rank", "practice_ready", "practice_result",
              "bullets",
              "motion", "drafts", "draft_attacks", "draft_spell",
              "hex_draw", "hex_seal", "hex_scatter", "hex_gaps",
              "hex_burst",
              "grove", "grove_arrive", "grove_turn", "grove_blood",
              "grove_boss", "grove_spell",
              "sanctum", "mika_attacks",
              "hall_a", "hall_b", "hall_turn", "hall_arrive"];
    var _n = array_length(mika_slots());
    for (var _i = 0; _i < _n; _i++) {
        array_push(_l, shot_mika_scene(_i));
    }
    return _l;
}

/// @desc The scene name for Mika's slot `_i` (`mika_slot_name`).
function shot_mika_scene(_i) {
    return "mika_" + string_lower(mika_slot_name(_i));
}

/// @desc Which of Mika's slots a scene asks for, or -1 if it is not one of
///       his.
function shot_mika_slot(_name) {
    var _n = array_length(mika_slots());
    for (var _i = 0; _i < _n; _i++) {
        if (_name == shot_mika_scene(_i)) return _i;
    }
    return -1;
}

// How far into one of Mika's attacks its picture is taken. `--burst` offsets
// are relative to this.
#macro SHOT_MIKA_AT (4 * FPS)

/// @desc Parse `-burst`'s comma-separated frame offsets, sorted (`obj_shot`
///       walks them in order).
function shot_parse_burst(_str) {
    var _out = [];
    var _cur = "";
    for (var _i = 1; _i <= string_length(_str) + 1; _i++) {
        var _ch = (_i > string_length(_str)) ? "," : string_char_at(_str, _i);
        if (_ch == ",") {
            if (_cur != "") array_push(_out, real(_cur));
            _cur = "";
        } else {
            _cur += _ch;
        }
    }
    array_sort(_out, true);
    return _out;
}

function shot_scene_known(_name) {
    var _l = shot_scene_list();
    for (var _i = 0; _i < array_length(_l); _i++) {
        if (_l[_i] == _name) return true;
    }
    return false;
}

/// @desc Which room a scene has to be posed in.
function shot_scene_room(_name) {
    switch (_name) {
        case "title":
        case "drafts":      return room_title;
        case "practice":
        case "draft_attacks":
        case "mika_attacks":   return room_practice;
        case "bullets":     return room_shot;  // a chart, not a game state
    }
    return room_game;
}

/// @desc Set globals a scene's room reads in its own Create (such as
///       `global.practice`), before the room change; `shot_pose` runs too late
///       for those.
function shot_scene_prepare(_name) {
    // Mika's slots are photographed through practice, in the open hall.
    var _slot = shot_mika_slot(_name);
    if (_slot >= 0) {
        global.stage_def = stage_sanctum_def();
        global.practice = practice_new(stage_sanctum_def(), 1, _slot);
        return;
    }

    switch (_name) {
        case "practice_ready":
        case "practice_result":
            var _stage = stage_ziggy_def();
            global.stage_def = _stage;
            // Ziggy's first spell.
            global.practice = practice_new(_stage, 1, 1);
            break;

        case "drafts":
            // The rack with the cursor on the drafting table (the last card).
            global.stage_pick = array_length(rack_list()) - 1;
            break;

        case "draft_attacks":
            global.stage_def = draft_stage_def();
            // Cursor on a named draft.
            global.practice = practice_new(draft_stage_def(), 0, 2);
            break;

        case "draft_spell":
            global.stage_def = draft_stage_def();
            // `Falling Sky`.
            global.practice = practice_new(draft_stage_def(), 0, 1);
            break;

        case "mika_attacks":
            // The attack list scrolled partway, with the cursor on one of
            // Mika's slots.
            global.stage_def = stage_sanctum_def();
            global.practice = practice_new(stage_sanctum_def(), 1, 9);
            break;

        case "sanctum":
        case "hall_a":
        case "hall_b":
        case "hall_arrive":
            // Stage three itself (Mika's slots have their own scenes).
            global.stage_def = stage_sanctum_def();
            break;

        case "hall_turn":
            // The review card, whose timeline drives the turn.
            global.stage_def = preview_stage_def();
            break;

        case "grove":
        case "grove_arrive":
        case "grove_turn":
        case "grove_blood":
        case "grove_boss":
        case "grove_spell":
            global.stage_def = stage_grove_def();
            break;

        case "hex_draw":
        case "hex_seal":
        case "hex_scatter":
        case "hex_gaps":
        case "hex_burst":
            // Practised as Velka's last attack.
            global.stage_def = stage_grove_def();
            global.practice = practice_new(stage_grove_def(), 1,
                                           array_length(velka_phases()) - 1);
            break;
    }
}

// ---------------------------------------------------------------------------
// Posing. Scenes reach their state through the game's own functions
// (`ziggy_spawn`, `boss_enter_phase`, `player_bomb`, ...), and then real frames
// run. The stage clock may be wound forward; its events still fire in order.
// ---------------------------------------------------------------------------

/// @desc The input a posed player holds (`_focus` shows the hitbox).
function shot_input(_shoot, _focus) {
    return { left: false, right: false, up: false, down: false,
             shoot: _shoot, bomb: false, focus: _focus };
}

/// @desc Put the boss on the field and start it on attack `_phase`, skipping
///       the arrival and the declaration. Returns the boss.
function shot_boss(_g, _phase, _maker) {
    var _b = _maker(_g);
    if (_b == undefined) return undefined;
    _g.boss_ref = _b;
    _b.boss.entry_t = 0;
    _b.boss.declare_t = 0;
    _b.boss.started = true;
    _b.x = _b.boss.home_x;
    _b.y = _b.boss.home_y;
    _b.touch = true;
    _g.phase = Phase.Playing;
    // Start at the health the attack begins at in the fight.
    if (_phase > 0) {
        _b.hp = _b.hp_max * _b.boss.phases[_phase - 1].hp_end;
    }
    // Fill the ledger with made-up marks for the earlier attacks, so the
    // console looks as it would at this point in a fight.
    for (var _i = 0; _i < _phase; _i++) {
        var _p = _b.boss.phases[_i];
        var _spell = (_p.kind == AttackKind.Spell);
        rank_note(_g[$ "marks"],
                  _spell ? _p.name
                         : (_b.boss.def.name + " " + string(_i + 1)),
                  (_i mod 3 == 0) ? Mark.Gold
                                  : ((_i mod 3 == 1) ? Mark.Amethyst
                                                     : Mark.Bronze),
                  _spell);
    }
    boss_enter_phase(_b, _g, _phase);
    return _b;
}

/// @desc Set a scene up. Returns the frame to release the shutter on.
function shot_pose(_scene, _g) {
    if (_g == undefined) {
        // The title, attack list and bullet chart have no run.
        return (_scene == "bullets") ? 6 : 40;
    }

    _g.phase = Phase.Playing;
    _g.intro_t = 0;
    _g.player.entry = 0;
    _g.input_override = shot_input(true, false);
    // Past the stage name splash (`t < 190`).
    _g.t = 400;

    // Mika's slots: player low and right of centre, untouchable (a posed
    // player gets hit, and a hit clears a circle of bullets out of the
    // picture). The shutter is `SHOT_MIKA_AT` into the attack, after the
    // practice count and, for a spell, the declaration.
    var _slot = shot_mika_slot(_scene);
    if (_slot >= 0) {
        _g.player.x = FIELD_CX + 120;
        _g.player.y = FIELD_Y1 - 260;
        _g.player.untouchable = true;
        var _spell = (mika_phases()[_slot].kind == AttackKind.Spell);
        return PRACTICE_READY + (_spell ? BOSS_SPELL_LEAD : 0)
               + SHOT_MIKA_AT;
    }

    switch (_scene) {
        case "motion":
            // Demonstrates the bullet behaviours the stages don't use yet
            // (`shot_motion_demo`), with no player fire.
            _g.input_override = shot_input(false, false);
            _g.player.x = FIELD_X0 + 200;
            _g.player.y = FIELD_Y1 - 120;
            return 92;

        case "stage":
            // Wound to just before the grimoire line: the busiest point of
            // the first half.
            _g.stage.t = 545;
            _g.player.x = FIELD_CX - 120;
            _g.player.y = FIELD_Y1 - 180;
            return 300;

        case "focus":
            // Focused (hitbox visible) inside Ziggy's first non-spell.
            shot_boss(_g, 0, ziggy_spawn);
            _g.input_override = shot_input(true, true);
            _g.player.x = FIELD_CX + 40;
            _g.player.y = FIELD_Y1 - 300;
            return 190;

        case "bomb":
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 260;
            _g.player.mp = MP_MAX;
            // Scenes posed on a spell add `BOSS_SPELL_LEAD`: a spell doesn't
            // fire until its declaration is over.
            return 236 + BOSS_SPELL_LEAD;   // the sweep is fired in shot_tick

        case "hit":
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX - 60;
            _g.player.y = FIELD_Y1 - 280;
            return 220 + BOSS_SPELL_LEAD;

        case "peril":
            // One hit from death (the low-life heartbeat), in a live pattern.
            // Best taken as a burst.
            shot_boss(_g, 2, ziggy_spawn);
            _g.player.x = FIELD_CX - 80;
            _g.player.y = FIELD_Y1 - 260;
            _g.player.hp = HP_PER_HIT;
            // Untouchable, or he dies before the shutter.
            _g.player.untouchable = true;
            return 220;

        case "midboss":
            shot_boss(_g, 0, ziggy_midboss_spawn);
            _g.player.x = FIELD_CX + 100;
            _g.player.y = FIELD_Y1 - 220;
            return 190;

        case "declare":
            // The one scene that keeps the boss's arrival ceremony.
            _g.boss_ref = ziggy_spawn(_g);
            _g.boss_ref.boss.entry_t = 0;
            _g.boss_ref.x = _g.boss_ref.boss.home_x;
            _g.boss_ref.y = _g.boss_ref.boss.home_y;
            _g.phase = Phase.BossDeclare;
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 200;
            // Mid-splash: past the arrival bounce, before the fade.
            return 2 + BOSS_DECLARE_TIME - 70;

        case "spell":
            // During the spell's banner and eye card (the field is empty,
            // since a spell doesn't fire until the declaration ends).
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX + 80;
            _g.player.y = FIELD_Y1 - 240;
            return 50;

        case "boss":
            shot_boss(_g, 2, ziggy_spawn);
            _g.player.x = FIELD_CX - 150;
            _g.player.y = FIELD_Y1 - 260;
            return 260;

        case "laser":
            // Sundering Lash, while the beams are still warnings.
            shot_boss(_g, 5, ziggy_spawn);
            _g.player.x = FIELD_CX + 200;
            _g.player.y = FIELD_Y1 - 280;
            return 76 + BOSS_SPELL_LEAD;

        case "rays":
            shot_boss(_g, 6, ziggy_spawn);
            _g.player.x = FIELD_CX - 90;
            _g.player.y = FIELD_Y1 - 300;
            return 210 + BOSS_SPELL_LEAD;

        case "clear":
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 260;
            return 230 + BOSS_SPELL_LEAD;   // the clear is fired in shot_tick

        case "items":
            // All three pickups over a live pattern, dropped in four lots (in
            // `shot_tick`) so some are arriving, falling and being collected.
            // No player fire.
            shot_boss(_g, 0, ziggy_spawn);
            _g.input_override = shot_input(false, false);
            _g.player.x = FIELD_CX + 60;
            _g.player.y = FIELD_Y1 - 200;
            _g.player.untouchable = true;
            return 196;

        case "rank":
            // The rank card, starting just after the attack ends (in
            // `shot_tick`). It animates for `RANK_CARD_TIME`, so use
            // `--burst`.
            shot_boss(_g, 2, ziggy_spawn);
            _g.player.x = FIELD_CX - 150;
            _g.player.y = FIELD_Y1 - 260;
            return 202;

        case "pause":
            shot_boss(_g, 2, ziggy_spawn);
            _g.player.x = FIELD_CX - 100;
            _g.player.y = FIELD_Y1 - 240;
            return 190;

        case "result":
            shot_boss(_g, 6, ziggy_spawn);
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 260;
            return 220 + BOSS_SPELL_LEAD;

        case "practice_ready":
            // The READY count before a practised attack. Nothing is posed:
            // `obj_game`'s Create started it from the practice request, and
            // the player is where a run puts them.
            return 50;

        case "draft_spell":
            // Nothing else is posed: `obj_game`'s Create put the boss on the
            // draft from the practice request.
            _g.player.x = FIELD_CX - 40;
            _g.player.y = FIELD_Y1 - 240;
            return 200 + PRACTICE_READY + BOSS_SPELL_LEAD;

        case "practice_result":
            // The boss is already on the attack (practice request); the tick
            // ends the attack.
            _g.player.x = FIELD_CX - 90;
            _g.player.y = FIELD_Y1 - 260;
            return 430;

        case "grove_arrive":
            // Partway through the opening fog.
            _g.player.x = FIELD_CX + 30;
            _g.player.y = FIELD_Y1 - 210;
            return round(GROVE_INTRO_TIME * 0.42);

        case "grove":
            // Night, with a wave of fodder, at the same timeline point as
            // stage one's `stage` scene.
            _g.stage.t = 530;
            _g.player.x = FIELD_CX - 140;
            _g.player.y = FIELD_Y1 - 200;
            return 300;

        case "grove_turn":
            // Totality. The turn is started and then run for real frames
            // (`shot_omen_frame`) rather than written directly, since it
            // eases a frame at a time.
            _g.player.x = FIELD_CX + 60;
            _g.player.y = FIELD_Y1 - 220;
            // Skip the opening fog (`intro = 1`), or the picture is of the
            // fog.
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            return shot_omen_frame(GROVE_WAVE_START * 0.5);

        case "grove_blood":
            // Mid-wavefront: far trees red, near ones not yet.
            _g.player.x = FIELD_CX - 60;
            _g.player.y = FIELD_Y1 - 240;
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            return shot_omen_frame(GROVE_WAVE_START + 0.34);

        case "hall_a":
            // The approach: camera high and aimed at the floor (`omen` is
            // 0). `intro = 1` skips the opening fade.
            _g.player.x = FIELD_CX - 90;
            _g.player.y = FIELD_Y1 - 210;
            _g.bg.intro = 1;
            return 150;

        case "hall_arrive":
            // A third of the way through the opening fade.
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 210;
            return round(HALL_INTRO_TIME * 0.34);

        case "hall_turn":
            // The reveal, partway through, driven by the review card's own
            // timeline.
            _g.player.x = FIELD_CX;
            _g.player.y = FIELD_Y1 - 230;
            return PREVIEW_HOLD_A + 40 + round(BG_OMEN_TIME * 0.62);

        case "hall_b":
            // The hall after the reveal (`omen` written straight to 1, since
            // this is the end state).
            _g.player.x = FIELD_CX + 70;
            _g.player.y = FIELD_Y1 - 240;
            _g.bg.omen_on = true;
            _g.bg.omen = 1;
            _g.bg.intro = 1;
            return 150;

        case "sanctum":
            // The early wave with two idle rings.
            _g.stage.t = 420;
            _g.player.x = FIELD_CX - 90;
            _g.player.y = FIELD_Y1 - 200;
            _g.bg.intro = 1;
            return 300;

        case "grove_boss":
            // Velka's first non-spell over the blood wood.
            shot_boss(_g, 0, velka_spawn);
            _g.player.x = FIELD_CX - 120;
            _g.player.y = FIELD_Y1 - 260;
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            _g.bg.omen = 1;
            return 200;

        case "grove_spell":
            // Velka's spell background, on a beam spell.
            shot_boss(_g, 1, velka_spawn);
            _g.player.x = FIELD_CX + 140;
            _g.player.y = FIELD_Y1 - 280;
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            _g.bg.omen = 1;
            _g.player.untouchable = true;
            return 240 + BOSS_SPELL_LEAD;

        case "hex_draw":
        case "hex_seal":
        case "hex_scatter":
        case "hex_gaps":
        case "hex_burst":
            // The ward is drawn round wherever the player stands, so the
            // player is placed (low and left, off centre) and left alone.
            // Untouchable: these scenes run about 16 seconds, a still player
            // would be hit, and a hit clears a circle out of the ward.
            _g.player.x = FIELD_CX - 210;
            _g.player.y = FIELD_Y1 - 300;
            // **And it does not dodge, so it is not asked to survive.** These
            // are the five longest scenes in the tool -- sixteen seconds of a
            // spell rather than the three or four every other one takes -- and
            // a player standing still under aimed volleys for that long is hit
            // four times and dies before the last of them.
            //
            // Health is the least of it. A hit sweeps a 190-pixel circle of
            // bullets away (see `player_hit`), so a posed player being hit
            // *takes a bite out of the ward being photographed* -- out of the
            // one pattern in the game whose entire claim is where its gaps
            // are. Every one of these pictures taken at less than full life
            // was quietly lying, and the seal is redrawn twice a cycle so
            // nothing was left to notice by the next movement.
            //
            // Set here rather than in `shot_tick` because it is a flag and not
            // a countdown, and set on these five rather than on every scene
            // because `hit` exists to photograph a hit and `player_hit` is a
            // no-op on somebody who cannot be touched.
            _g.player.untouchable = true;
            return shot_hex_frame(_scene) + PRACTICE_READY + BOSS_SPELL_LEAD;
    }
    return 40;
}

/// @desc The frame at which a turn started on the next frame reaches `_at`
///       (0..1), since the turn advances one `BG_OMEN_TIME`th per frame.
function shot_omen_frame(_at) {
    return 3 + round(clamp(_at, 0, 1) * BG_OMEN_TIME);
}

/// @desc The frame of `Demon Sealing Hex` each of its scenes is taken at.
function shot_hex_frame(_scene) {
    switch (_scene) {
        // Half inscribed: all seven traces half done.
        case "hex_draw":  return HEX_DRAW div 2;

        // The red ward closed and being fired into.
        case "hex_seal":  return HEX_RED_FAN0 + 130;

        // The red ward scattering.
        case "hex_scatter": return HEX_SCATTER_AT + 120;

        // The blue ward and its gaps.
        case "hex_gaps":  return HEX_BLUE_FAN0 + 110;

        // Just after the collapse: debris spreading and the shockwave rings
        // still on screen.
        case "hex_burst": return HEX_BURST_AT + 26;
    }
    return 40;
}

/// @desc Per-frame actions for scenes that need something to happen at a
///       particular frame (a bomb, a hit, a phase ending, item drops).
function shot_tick(_scene, _g, _t) {
    if (_g == undefined) return;

    switch (_scene) {
        case "motion":
            // The stage's first wave would arrive in this window; clear it.
            if (_t >= 28) enemy_clear_all();
            if (_t == 30) {
                run_clear_field();
                shot_motion_demo();
            }
            break;

        case "bomb":
            if (_t == 210 + BOSS_SPELL_LEAD) {
                _g.player.mp = MP_MAX;
                player_bomb(_g.player, _g);
            }
            break;

        case "hit":
            if (_t == 200 + BOSS_SPELL_LEAD) {
                _g.player.iframe = 0;
                player_hit(_g.player);
            }
            break;

        case "clear":
            if (_t == 216 + BOSS_SPELL_LEAD) {
                var _b = enemy_find_boss();
                if (_b != undefined) boss_end_phase(_b, _g, true);
            }
            break;

        case "items":
            if (_t == 110) item_drop_spread(FIELD_X0 + 300, FIELD_Y0 + 330, 3, 3, 5);
            if (_t == 140) item_drop_spread(FIELD_X0 + 980, FIELD_Y0 + 280, 3, 3, 5);
            if (_t == 172) item_drop_spread(FIELD_X0 + 560, FIELD_Y0 + 420, 2, 2, 4);
            // Just inside the magnet radius, so they are being pulled in.
            if (_t == 188) item_drop_spread(_g.player.x - 70,
                                            _g.player.y - 180, 2, 2, 3);
            break;

        case "rank":
            if (_t == 200) {
                var _b = enemy_find_boss();
                if (_b != undefined) boss_end_phase(_b, _g, true);
            }
            break;

        case "pause":
            if (_t == 176) {
                _g.phase_before_pause = Phase.Playing;
                _g.phase = Phase.Paused;
                _g.pause_row = 1;
            }
            break;

        case "practice_result":
            // Once the pattern has filled the field.
            if (_t == 348) {
                // Posed as grazed and untouched (a capture).
                _g.player.graze_n = 412;
                var _pb = enemy_find_boss();
                // Ended through `boss_end_phase`, as in play.
                if (_pb != undefined) boss_end_phase(_pb, _g, true);
            }
            break;

        case "result":
            if (_t == 200 + BOSS_SPELL_LEAD) {
                _g.tally = 4826150;
                _g.player.graze_n = 3184;
                _g.player.hit_n = 2;
                _g.player.bomb_n = 1;
                var _b = enemy_find_boss();
                if (_b != undefined) _b.boss.captured = 3;
                _g.boss_ref = _b;
                _g.phase = Phase.Won;
                _g.result_t = 0;
            }
            break;
    }
}

/// @desc Fires a demo of the bullet behaviours the stages don't use: a lob
///       (Cartesian force), a wake (`bullet_shed_every`), a split, lifetimes
///       fading out, and a mid-flight graphic change. Streams are staggered
///       so a single frame shows the whole path.
function shot_motion_demo() {
    // A lob: constant downward force with a terminal speed. Staggered so some
    // are still rising at the shutter.
    for (var _i = 0; _i < 8; _i++) {
        var _b = fire_xy(FIELD_X0 + 106, FIELD_Y0 + 356, 5.5, -6,
                         BSHAPE_ORB, BCOL_GOLD, _i * 8);
        bullet_force(_b, 0, 0.22, BQ_KEEP, 7);
    }

    // A wake: a child dropped every eight frames while the parent flies on.
    var _w = fire(FIELD_X0 + 76, FIELD_Y0 + 616, 6, 0, BSHAPE_RICE,
                  BCOL_JADE, 0);
    bullet_shed_every(_w, 6, 8, 6, 1, 2.2, 180);

    // A split: the parent becomes a ring.
    var _s = fire(FIELD_X0 + 1036, FIELD_Y0 + 116, 3.4, 270, BSHAPE_SPHERE,
                  BCOL_CRIMSON, 0);
    if (_s != undefined) _s.spin = 1.2;
    bullet_split_at(_s, 30, 12, 6.2);

    // Lifetimes a few frames apart, so the fade-out is visible along the row.
    for (var _i = 0; _i < 6; _i++) {
        var _f = fire(FIELD_X0 + 806 + _i * 66, FIELD_Y0 + 836, 1.4, 0,
                      BSHAPE_BALL, BCOL_ROSE, 0);
        bullet_expire_at(_f, 20 + _i * 6, 40);
    }

    // A column that changes graphic 26 frames into flight.
    for (var _i = 0; _i < 10; _i++) {
        var _c = fire(FIELD_X0 + 706, FIELD_Y1 - 56, 4.5, 90, BSHAPE_PELLET,
                      BCOL_GOLD, _i * 5);
        bullet_graphic_at(_c, 26, BSHAPE_CRYSTAL, BCOL_CYAN);
    }
}

/// @desc The "bullets" scene: every bullet shape in every hue, drawn as a
///       chart (not a game state).
function shot_draw_bullet_chart() {
    draw_clear(make_colour_rgb(18, 20, 30));

    var _x0 = 150;
    var _y0 = 92;
    var _cw = 118;
    var _rh = 56;

    draw_set_font(fnt_ui());
    draw_set_valign(fa_middle);
    draw_set_halign(fa_center);
    draw_text_outline(GAME_CX, 40, "EVERY BULLET, EVERY HUE", COL_SILVER, 0.8, 2);

    draw_set_font(fnt_small());
    for (var _c = 0; _c < BCOL_COUNT; _c++) {
        draw_set_halign(fa_center);
        draw_text_outline(_x0 + _c * _cw, _y0 - 26, string(_c), COL_SILVER,
                          0.5, 1);
    }

    for (var _s = 0; _s < BSHAPE_COUNT; _s++) {
        var _y = _y0 + _s * _rh;
        draw_set_halign(fa_right);
        draw_text_outline(_x0 - _cw * 0.7, _y,
                          string(global.bshape_radius[_s]), COL_SILVER, 0.5, 1);
        for (var _c = 0; _c < BCOL_COUNT; _c++) {
            draw_sprite_ext(global.bshape_sprite[_s],
                            bullet_frame(_s, _c, 0),
                            _x0 + _c * _cw, _y, 1, 1, 0, c_white, 1);
        }
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
