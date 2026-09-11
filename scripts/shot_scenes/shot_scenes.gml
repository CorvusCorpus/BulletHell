/// @desc The scenes `tools/shot.py` can photograph, and where each one lives.
///
/// **This list is the game's, not the tool's, and that is deliberate.** The
/// harness passes a scene name and `obj_boot` refuses one it does not know --
/// so a scene added to the Python side and not to this one fails immediately
/// with a message, rather than opening the title screen and sitting there
/// until the tool's timeout. That exact failure cost an afternoon in the
/// Wordsearch project, where the flag and the scene name were fused into one
/// string and an unrecognised one was silently ignored.
///
/// **A screenshot is the only test a drawn state has.** Everything about a
/// pattern that a suite can check -- the angles, the counts, the collision --
/// is checked in `selftest`; whether the screen *reads* is checked here and
/// nowhere else. A pattern that is correct and illegible is still a bug.

/// @desc Every scene, in the order they are worth looking at.
function shot_scene_list() {
    return ["title", "practice", "stage", "focus", "bomb", "hit", "midboss",
            "declare", "spell", "boss", "laser", "rays", "clear", "pause",
            "result", "practice_ready", "practice_result", "bullets",
            "motion", "drafts", "draft_attacks", "draft_spell",
            "hex_draw", "hex_seal", "hex_scatter", "hex_gaps",
            "hex_burst",
            "grove", "grove_arrive", "grove_turn", "grove_blood",
            "grove_boss", "grove_spell"];
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
        case "draft_attacks":  return room_practice;
        case "bullets":     return room_shot;  // a chart, not a game state
    }
    return room_game;
}

/// @desc Globals a scene's room reads in its own Create, set before it is
///       entered.
///
///       **`shot_pose` is too late for some of it.** It runs on the second
///       frame, after `obj_game`'s Create -- which is the right moment for
///       anything a run can be *put into*, and the wrong one for anything the
///       run reads to decide what kind of run it is. `global.practice` is the
///       second of those, exactly as `global.stage_def` is, so it is written
///       here for the same reason the rack writes it before a room change: a
///       room transition carries nothing with it.
function shot_scene_prepare(_name) {
    switch (_name) {
        case "practice_ready":
        case "practice_result":
            var _stage = stage_ziggy_def();
            global.stage_def = _stage;
            // Ziggy's first spell, which is the one with a name worth reading
            // across a panel and the background that goes with it.
            global.practice = practice_new(_stage, 1, 1);
            break;

        case "drafts":
            // The rack with the cursor on the drafting table, which is the
            // last card and therefore the one nothing else photographs. The
            // card has a branch of its own in the rack's Draw -- see
            // `stage_drafts` -- and a branch nothing looks at is a branch that
            // has never been checked.
            global.stage_pick = array_length(rack_list()) - 1;
            break;

        case "draft_attacks":
            global.stage_def = draft_stage_def();
            // Land on a named draft, so the picture has the spell bead, the
            // lit band and a name in it rather than the top of the list.
            global.practice = practice_new(draft_stage_def(), 0, 2);
            break;

        case "draft_spell":
            global.stage_def = draft_stage_def();
            // `Falling Sky` -- the one draft whose whole idea is the shape of
            // a trajectory, which is precisely the thing no assertion can see.
            global.practice = practice_new(draft_stage_def(), 0, 1);
            break;

        case "grove":
        case "grove_arrive":
        case "grove_turn":
        case "grove_blood":
        case "grove_boss":
        case "grove_spell":
            // **The Hollow Grove gets five pictures, and four of them are
            // about the background rather than about the fight.** That is
            // unusual here and it is the whole reason the stage exists: a
            // corridor is a thing in motion and a wood in it is a thing that
            // changes, and neither claim can be made by one frame. Night,
            // totality, the wave arriving, and the wood after it -- plus one
            // of the danmaku over the top of all of it, because a background
            // photographed with an empty field is a background nobody has
            // checked.
            global.stage_def = stage_grove_def();
            break;

        case "hex_draw":
        case "hex_seal":
        case "hex_scatter":
        case "hex_gaps":
        case "hex_burst":
            // **`Demon Sealing Hex` gets five pictures, and no other attack in
            // the game gets more than one.** That is not because it is more
            // important; it is because it is the only attack whose *shape* is
            // the pattern. Everything else here can be judged from one frame
            // -- a fan is a fan -- where this one makes five claims in
            // sequence that are each false in a different way if the geometry
            // is wrong, and `test_hex_seal` can only prove the arithmetic
            // behind them. A ward that closes into a perfect pentagram and is
            // unreadable against a dark field is exactly the bug this tool
            // exists for.
            // **Practised as Velka's, which is what it is.** It is her last
            // attack, so it is found by being last rather than by an index
            // somebody will forget to move when she gets a seventh.
            global.stage_def = stage_grove_def();
            global.practice = practice_new(stage_grove_def(), 1,
                                           array_length(velka_phases()) - 1);
            break;
    }
}

// ---------------------------------------------------------------------------
// Posing
//
// **Every scene reaches its state through the game's own functions.** A shot
// of a hand-built state proves the renderer works on states the game cannot
// reach, which is the one thing nobody needs to know. So a boss scene calls
// `ziggy_spawn` and `boss_enter_phase`; a bomb scene calls `player_bomb`; a
// hit scene calls `player_hit`. The only thing written directly is the stage's
// own clock, and winding that forward is a fast-forward through the real
// timeline rather than a fabrication -- the events still fire through
// `stage_step`, in order, doing exactly what they do in play.
// ---------------------------------------------------------------------------

/// @desc Input a posed player holds down. `_focus` is the interesting one:
///       it is what puts the hitbox and the reticle on screen.
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
    // Start it at the health that attack actually begins on -- the floor of
    // the one before it. Without this the bar is photographed nearly full
    // during a shot of the fifth attack, which is a picture of a state the
    // game cannot be in.
    if (_phase > 0) {
        _b.hp = _b.hp_max * _b.boss.phases[_phase - 1].hp_end;
    }
    // **And with the marks those attacks would have earned.** The same
    // argument as the health above, one readout over: a boss posed on its
    // fifth attack with an empty ledger is a picture of a state the game
    // cannot be in, and the ledger is now a third of the console. The tiers
    // are posed rather than earned, which is the whole business of this file.
    for (var _i = 0; _i < _phase; _i++) {
        var _p = _b.boss.phases[_i];
        var _spell = (_p.kind == AttackKind.Spell);
        rank_note(_g[$ "marks"],
                  _spell ? _p.name
                         : (_b.boss.def.name + " " + string(_i + 1)),
                  (_i mod 3 == 0) ? Mark.Gold
                                  : ((_i mod 3 == 1) ? Mark.Adamant
                                                     : Mark.Silver),
                  _spell);
    }
    boss_enter_phase(_b, _g, _phase);
    return _b;
}

/// @desc Set a scene up. Returns the frame to release the shutter on.
function shot_pose(_scene, _g) {
    if (_g == undefined) {
        // The title, the attack list and the bullet chart have no run behind
        // them.
        return (_scene == "bullets") ? 6 : 40;
    }

    _g.phase = Phase.Playing;
    _g.intro_t = 0;
    _g.player.entry = 0;
    _g.input_override = shot_input(true, false);
    // Past the stage's own opening title, which is gated on `t < 190` and in
    // play is long gone by the time any of these states can happen. Left at
    // zero, every boss shot was photographed with THE BRIMSTONE REACH written
    // across the middle of it.
    _g.t = 400;

    switch (_scene) {
        case "motion":
            // **Everything a bullet can be told to do, on one empty field.**
            // Nothing in the stage uses most of these yet, so without a scene
            // of their own they are behaviours no photograph can reach -- and
            // a trajectory that is arithmetically perfect and illegible is
            // exactly the bug this tool exists for.
            //
            // The player holds no shot button here: a stream of white player
            // shots up the middle would be the brightest thing in a picture
            // that is about the other bullets.
            _g.input_override = shot_input(false, false);
            _g.player.x = FIELD_X0 + 200;
            _g.player.y = FIELD_Y1 - 120;
            return 92;

        case "stage":
            // Wound to just before the grimoire line, so the two crossing
            // waves are mid-screen and the line is arriving over them --
            // the fullest the stage's first half ever is.
            _g.stage.t = 545;
            _g.player.x = FIELD_CX - 120;
            _g.player.y = FIELD_Y1 - 180;
            return 300;

        case "focus":
            // Focus is a *state*, so it needs a pattern to be focused inside
            // of. Ziggy's opening non-spell is the widest thing in the game
            // and the hitbox has room to be seen against it.
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
            // **`+ BOSS_SPELL_LEAD` on every scene posed on a spell.** A spell
            // holds fire until it has declared itself, so a scene asking for
            // "two hundred frames into the pattern" has to wait out the
            // declaration first -- written as the sum rather than as the total
            // so the intent survives the constant being retuned.
            return 236 + BOSS_SPELL_LEAD;   // the sweep is fired in shot_tick

        case "hit":
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX - 60;
            _g.player.y = FIELD_Y1 - 280;
            return 220 + BOSS_SPELL_LEAD;

        case "midboss":
            shot_boss(_g, 0, ziggy_midboss_spawn);
            _g.player.x = FIELD_CX + 100;
            _g.player.y = FIELD_Y1 - 220;
            return 190;

        case "declare":
            // The one scene that must NOT skip the ceremony.
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
            // Caught during the banner and the eye card, which together last
            // under three seconds and are the whole point of the scene.
            shot_boss(_g, 1, ziggy_spawn);
            _g.player.x = FIELD_CX + 80;
            _g.player.y = FIELD_Y1 - 240;
            // **Mid-declaration, and the field is empty because of it.** That
            // used to be impossible: a spell fired from the frame it was
            // named, so this scene was the eye card drawn over bullets the
            // card had already launched. The empty field is the rule now, and
            // it is the half of the ceremony worth photographing -- the other
            // half, a spell's pattern over its own background, is what `laser`
            // and `rays` show.
            return 50;

        case "boss":
            shot_boss(_g, 2, ziggy_spawn);
            _g.player.x = FIELD_CX - 150;
            _g.player.y = FIELD_Y1 - 260;
            return 260;

        case "laser":
            // Sundering Lash, caught while the beams are still *warnings*.
            // The telegraph is the mechanic; a shot of the fired beam would
            // photograph the half a player never has to read.
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
            // The beat before a practised attack opens, caught on the second
            // of its three counts. Nothing is posed: the count is running
            // because `obj_game`'s Create put the boss into its own pause off
            // the request `shot_scene_prepare` wrote.
            //
            // **The player is left where a run puts them**, unlike every other
            // scene here, because where they start is half of what the beat is
            // for -- a shot of a posed player would photograph away the
            // problem the beat exists to solve.
            return 50;

        case "draft_spell":
            // **Nothing is posed here either.** `obj_game`'s Create has
            // already put the boss on the draft off the request
            // `shot_scene_prepare` wrote, so what this photographs is the
            // drafting table's own entry path rather than a reconstruction of
            // it -- which is the point, since the whole claim being made is
            // that a draft is played through the game's machinery untouched.
            //
            // Far enough in for the lobs to have been thrown, hung and started
            // to fall, and nowhere near the 360 points of health the slot is
            // worth, so the attack is still running when the shutter goes.
            _g.player.x = FIELD_CX - 40;
            _g.player.y = FIELD_Y1 - 240;
            return 200 + PRACTICE_READY + BOSS_SPELL_LEAD;

        case "practice_result":
            // **Nothing is posed here.** The boss is already on the field and
            // already fighting the attack, because `obj_game`'s Create put it
            // there off the request `shot_scene_prepare` wrote -- which is the
            // point: this scene photographs the mode's own entry path rather
            // than a reconstruction of it. All the tick has to do is end the
            // attack.
            _g.player.x = FIELD_CX - 90;
            _g.player.y = FIELD_Y1 - 260;
            return 430;

        case "grove_arrive":
            // **The fog the stage comes out of.** Photographed part way
            // through the arrival rather than at either end of it, because
            // both ends are pictures of something else -- the first frame is
            // a flat rectangle and the last is the `grove` shot. What this
            // has to show is the wood becoming visible through cloud with the
            // moon already in it.
            _g.player.x = FIELD_CX + 30;
            _g.player.y = FIELD_Y1 - 210;
            return round(GROVE_INTRO_TIME * 0.42);

        case "grove":
            // The stage at its plainest: night, the moon on the horizon, and
            // a wave of fodder over it. **Wound to the same place stage one's
            // `stage` scene is** -- the fullest the first half ever gets --
            // so the two stages are photographed doing the same thing and the
            // only difference in the picture is the world.
            _g.stage.t = 530;
            _g.player.x = FIELD_CX - 140;
            _g.player.y = FIELD_Y1 - 200;
            return 300;

        case "grove_turn":
            // **Totality**, which is the one frame in the stage with almost no
            // light in it. The turn is posed rather than played to: the
            // timeline reaches it a minute and a half in, behind a midboss,
            // and a scene that got there honestly would be four minutes of
            // harness for one photograph.
            //
            // **The turn is *started* and then waited out, not written
            // straight into.** It eases a frame at a time like everything
            // else in the game, so a scene that set the number it wanted and
            // then ran sixty frames photographed sixty frames *past* the
            // moment it asked for -- which for this one is the difference
            // between the umbra covering the moon and the umbra having gone.
            // The first version of this picture was a lit wood with a caption
            // claiming it was an eclipse.
            _g.player.x = FIELD_CX + 60;
            _g.player.y = FIELD_Y1 - 220;
            // **Every scene posed inside the turn skips the arrival.** The
            // stage opens in fog that takes `GROVE_INTRO_TIME` frames to
            // lift, and the omen frames below land inside it -- so without
            // this the eclipse would be photographed through cloud and the
            // picture would be of the veil rather than of the moon. `grove`
            // waits the arrival out honestly and `grove_arrive` is a picture
            // of it; these three are about something else.
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            return shot_omen_frame(GROVE_WAVE_START * 0.5);

        case "grove_blood":
            // ...and the same wood a few seconds later, with the wavefront
            // part way down the corridor. **Caught mid-wave rather than after
            // it**, because "the far trees are red and the near ones are not
            // yet" is the claim, and a picture taken once it is over is a
            // picture of a red forest.
            _g.player.x = FIELD_CX - 60;
            _g.player.y = FIELD_Y1 - 240;
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            return shot_omen_frame(GROVE_WAVE_START + 0.34);

        case "grove_boss":
            // Velka's opening non-spell over the turned wood, which is what
            // the stage actually looks like when it is being played. The moon
            // is directly behind her and the danmaku is over both -- the one
            // question no still of the background alone can answer.
            shot_boss(_g, 0, velka_spawn);
            _g.player.x = FIELD_CX - 120;
            _g.player.y = FIELD_Y1 - 260;
            _g.bg.intro = 1;
            _g.bg.omen_on = true;
            _g.bg.omen = 1;
            return 200;

        case "grove_spell":
            // Her caster's own background: the wash, the bone circle and the
            // antlers out of the corners. Photographed on a spell whose
            // pattern is beams, so the picture has something in it as well as
            // the ceremony.
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
            // **The player is posed and then left alone**, because the ward is
            // drawn round wherever they are standing on the frame it opens --
            // so where they stand *is* the composition, and a scene that let
            // the run put them at the default spawn would photograph the seal
            // hanging off the bottom of the field every time.
            //
            // Low and left of centre, which is where a danmaku player actually
            // lives, and far enough off centre to prove the clamp is doing
            // something.
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

/// @desc The frame a stage's turn reaches `_at`, given it starts on the next
///       one.
///
///       `bg_omen_step` moves the turn by one part in `BG_OMEN_TIME` a frame
///       and nothing can write to it directly without lying about how the
///       stage actually plays -- which is the point. So a scene that wants the
///       wood half way through its eclipse asks for the *frame* that is, and
///       the two cannot drift apart when the constant is retuned.
function shot_omen_frame(_at) {
    return 3 + round(clamp(_at, 0, 1) * BG_OMEN_TIME);
}

/// @desc Which frame of `Demon Sealing Hex` each of its four pictures wants.
///
///       Written out here rather than inline so the four sit next to each
///       other and the gaps between them are legible: the four beats of the
///       attack, caught one apiece.
function shot_hex_frame(_scene) {
    switch (_scene) {
        // Half drawn. **The claim being photographed is that seven traces of
        // four different lengths are all half done at once** -- five arms
        // creeping out from their points while the two rings race round -- and
        // it is only visible while the seal is unfinished.
        case "hex_draw":  return HEX_DRAW div 2;

        // Closed, turned, and being fired into. This is the one that says
        // whether the red ward is fair: the player is sealed in a cell of
        // their own, and what has to read is where the walls are and where the
        // fan is going.
        case "hex_seal":  return HEX_RED_FAN0 + 130;

        // The red ward coming apart. **Every bead goes its own way**, which is
        // the movement that changed most and the only claim here a count
        // cannot check: thrown outward the figure keeps its shape and leaves
        // the room it was enclosing empty, and what has to be visible is that
        // half of it is coming back through the middle. Far enough in for the
        // beads to have travelled and near enough that it still reads as a
        // pentagram that has failed.
        case "hex_scatter": return HEX_SCATTER_AT + 120;

        // The blue ward, whose whole design is that it has gaps in it. If they
        // cannot be *seen* they may as well not be there, and no assertion
        // about their width can say whether they can.
        case "hex_gaps":  return HEX_BLUE_FAN0 + 110;

        // A moment after the collapse lands: the seal gone into a point and
        // the detonation coming back out of it.
        //
        // **The one claim here is that it looks like something breaking.** It
        // used to be one shape at one of three speeds, which photographs as
        // three expanding rings -- an arithmetically fine burst that reads as a
        // firework, and it took a person looking at this picture to say so.
        // What has to be visible now is chunks and grit in the same cloud,
        // unevenly spaced, with the heavy pieces still near the middle. Far
        // enough in that the speeds have pulled it apart and near enough that
        // the slow half has not left.
        //
        // **And near enough that the shockwave is still on screen.** The rings
        // and the sparks are the half of a detonation that carries its size
        // and none of the half that carries its danger, so a picture taken
        // after they have faded is a picture of the debris alone -- which is
        // the more useful frame for judging the pattern and the less useful
        // one for judging whether the complaint that started this was
        // answered. Twenty-six frames in has both.
        case "hex_burst": return HEX_BURST_AT + 26;
    }
    return 40;
}

/// @desc The things a scene has to do *at a moment* rather than at the start.
///
///       A bomb has to go off against a full screen, and a screen takes two
///       hundred frames to fill; a phase clear has to be caught on the frame
///       the bullets turn into score. Both are one-frame events, and both are
///       fired through the same function play fires them through.
function shot_tick(_scene, _g, _t) {
    if (_g == undefined) return;

    switch (_scene) {
        case "motion":
            // The stage's own timeline is still running underneath, and its
            // first wave is due inside this window. Clearing the fodder every
            // frame rather than winding the clock past it keeps the scene to
            // one subject without inventing a state the game cannot be in.
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

        case "pause":
            if (_t == 176) {
                _g.phase_before_pause = Phase.Playing;
                _g.phase = Phase.Paused;
                _g.pause_row = 1;
            }
            break;

        case "practice_result":
            // Late enough that the beat has run and the pattern is fully
            // out, so the sweep it converts is a real screen of danmaku
            // rather than the first two seconds of one.
            if (_t == 348) {
                // Grazed and clean, which is the outcome the panel has the
                // most to say about: a spell broken untouched is a capture and
                // the mark it earns is the top of the ladder.
                _g.player.graze_n = 412;
                var _pb = enemy_find_boss();
                // Ended through the game's own verb, so the ledger, the sweep,
                // the drops and the run's own `on_phase_end` all happen
                // exactly as they do in play. See `boss_end_phase`.
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

/// @desc The bullet chart: every shape, every hue, laid out and labelled.
///
///       Not a game state, so it is drawn rather than posed -- and it is the
///       one scene that is worth having *because* it is not a game state. It
///       is the only view that shows two shapes of the same hue side by side,
///       which is the comparison a player actually has to make at speed.
/// @desc Every behaviour a bullet can be given, laid out across one field.
///
///       **Two of these are only legible as a stream.** A trajectory is a
///       shape drawn by one bullet over two seconds, and a still frame has no
///       two seconds -- so each of them fires a line of shots with staggered
///       delays and lets the spread of their ages draw the path. What the
///       photograph holds is the same shape the player reads in play, at one
///       instant instead of over time.
function shot_motion_demo() {
    // A lob: the one shape the polar model cannot draw. A flat launch, a
    // constant downward force, and a terminal velocity to fall at.
    //
    // The stagger is wide on purpose: at eight frames apart these eight span
    // fifty-six frames of flight and the apex is twenty-seven frames in, so
    // three of them are still rising when the shutter goes. A tighter stagger
    // photographed the same arc entirely past its apex, which is a straight
    // line -- the picture was correct and said nothing.
    for (var _i = 0; _i < 8; _i++) {
        var _b = fire_xy(FIELD_X0 + 106, FIELD_Y0 + 356, 5.5, -6,
                         BSHAPE_ORB, BCOL_GOLD, _i * 8);
        bullet_force(_b, 0, 0.22, BQ_KEEP, 7);
    }

    // A wake: one bullet crossing the field, dropping a child behind it every
    // eight frames and flying on. A split cannot do this, because a split is
    // the parent's last act.
    var _w = fire(FIELD_X0 + 76, FIELD_Y0 + 616, 6, 0, BSHAPE_RICE,
                  BCOL_JADE, 0);
    bullet_shed_every(_w, 6, 8, 6, 1, 2.2, 180);

    // And a split, for the contrast: the parent is gone and the ring is what
    // it turned into.
    var _s = fire(FIELD_X0 + 1036, FIELD_Y0 + 116, 3.4, 270, BSHAPE_SPHERE,
                  BCOL_CRIMSON, 0);
    if (_s != undefined) _s.spin = 1.2;
    bullet_split_at(_s, 30, 12, 6.2);

    // A row given lifetimes a few frames apart, so the ramp itself is in the
    // picture: solid at one end, gone at the other, and harmless from the
    // first frame of the fade rather than the last.
    for (var _i = 0; _i < 6; _i++) {
        var _f = fire(FIELD_X0 + 806 + _i * 66, FIELD_Y0 + 836, 1.4, 0,
                      BSHAPE_BALL, BCOL_ROSE, 0);
        bullet_expire_at(_f, 20 + _i * 6, 40);
    }

    // A column that changes what it *is* partway up. Staggered again, so one
    // instant holds both halves of the change: everything above the line has
    // been flying for more than twenty-six frames and everything below it has
    // not -- and the hitbox changed with the picture.
    for (var _i = 0; _i < 10; _i++) {
        var _c = fire(FIELD_X0 + 706, FIELD_Y1 - 56, 4.5, 90, BSHAPE_PELLET,
                      BCOL_GOLD, _i * 5);
        bullet_graphic_at(_c, 26, BSHAPE_CRYSTAL, BCOL_CYAN);
    }
}

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
