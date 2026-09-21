/// @desc The console beside the field, and the boss's line inside it.
///
/// **One console, and one thin line over the playfield.** This is the third
/// arrangement the readouts have had and the reasoning for each rejection is
/// the part worth keeping.
///
/// They started in the four corners of a full-bleed field, fading as the
/// player flew near. That is unwinnable rather than mis-tuned: a readout has
/// to be big enough to read at a glance, anything that big can hide bullets,
/// and fading it makes it unreadable at exactly the moment it is most needed
/// -- you check your life when you are deepest in a pattern. Those are the
/// same pixels and no alpha satisfies both.
///
/// So the field got a boundary and the readouts got margins: a 168-pixel strip
/// above the field and a column beside it. The strip is what this pass
/// removes. It carried a boss's name at 66pt and a health tube spanning the
/// whole field -- a sixth of the display, for two facts -- and for the two or
/// three minutes of every stage before the boss arrives it held a stage name
/// and otherwise nothing. Meanwhile the column beside it was a pair of narrow
/// upright vials with 300 pixels of gap between them and the score.
///
/// What is here now:
///
///   the console, right of the field   the stage, the score, the graze count,
///                                     the attacks left, the spell being
///                                     survived, and the two meters at its foot
///   a line inside the field's top     the boss's name, bar, marks and timer
///
/// The boss's line is over the playfield **on purpose**, which is the one rule
/// the bordered field was built to keep and the one exception worth making:
/// a boss's health belongs beside the boss, every game in the genre puts it
/// there, and the whole thing is fourteen pixels tall. See `BOSS_BAR_H` and
/// the note in `test_hud_layout` about what is asserted in place of "clear of
/// the field".
///
/// **Nothing here fades and nothing here is small.** That is what the console
/// bought, and it is why every number on the screen is at the size it wants.

/// @desc The eased numbers and the one-shot flashes the HUD carries between
///       frames.
///
///       **Every one of these is derived by watching, not by being told.**
///       Nothing in the game calls `hud_note_hit` or `hud_note_score`; the
///       console compares what it is showing with what is true and reacts to
///       the difference. That is what keeps feedback from rotting: a new way
///       to lose health, or a new source of points, animates correctly the day
///       it is written because nobody had to remember to tell the HUD.
function hud_new() {
    return {
        life_shown: HP_MAX,      // the vessel lags the number, so a hit reads
        mana_shown: 0,
        boss_shown: 1,
        tally_shown: 0,
        spell_a: 0,              // the nameplate easing in behind the banner

        // **How hard each surface is sloshing.** Nudged when the number
        // underneath it jumps and decayed every frame otherwise, so taking a
        // hit throws the liquid about for a second afterwards. It is the one
        // piece of feedback that survives the player not looking directly at
        // the vessel, which is most of the argument for a vessel.
        life_slosh: 0,
        mana_slosh: 0,
        boss_slosh: 0,

        // The one-shot flares. Each is set to 1 by a change and decays; each
        // is read by exactly one thing on the screen.
        life_flare: 0,           // health lost -- the meter flushes
        mana_flare: 0,           // sigil gained
        tally_flare: 0,          // points scored -- the numerals swell
        graze_flare: 0,          // a near miss
        boss_flare: 0,           // a phase threshold crossed

        // **The rig: how far the boss's rail has come down.** A spring rather
        // than an eased number, because a thing on a chain has weight and a
        // thing that arrives at exactly its resting place has been faded in
        // rather than lowered -- the same argument the rank card's overshoot
        // is built on. It runs past 1 on the way down and settles back, so
        // `hud_rig_y` extrapolates rather than clamping.
        rig: 0,
        rig_v: 0,

        // **What the boss's percentage counter is showing, in tenths of a
        // per cent** -- a position on its wheels rather than a value. It rests
        // on whole tenths and turns between them, which the vessel's own
        // eased number cannot do: that converges on the truth, and the truth
        // is almost never a whole tenth, so a counter driven by it would sit
        // with its last wheel part-turned for the whole of an attack.
        pct_roll: 1000,

        // **Which stretch of the boss's health the rail spans**, as
        // `[top, bottom]` fractions of the whole. The whole fight in a stage;
        // one attack in practice. See `hud_boss_span`.
        boss_span: [1, 0],
        rig_seen: 0,             // what it was last frame, to catch the landing
        rig_flare: 0,            // the chains coming up taut

        graze_seen: 0,           // what the counters were last frame
        tally_seen: 0,
        life_seen: HP_MAX,
        mana_seen: 0,
        boss_phase_seen: -99,

        // The medal a finished encounter throws on the screen, and the count
        // of marks it has already thrown one for. See `rank_card`.
        card: rank_card_new(),
    };
}

/// @desc Where the `_i`th socket of `_total` sits in the console's row.
///
///       **One answer, because two things read it.** The row draws the marks
///       here and the rank card flies its medal to the same place, and a card
///       that landed a few pixels off the socket it was filling would read as
///       the console having missed rather than as two pieces of arithmetic
///       having drifted -- which is what they would be.
function hud_mark_xy(_i, _total) {
    var _per = max(1, floor(HUD_COL_W / 46));
    var _pitch = HUD_COL_W / min(max(_total, 1), _per);
    return [HUD_COL_X + _pitch * ((_i mod _per) + 0.5),
            HUD_ROW_MARKS + 64 + (_i div _per) * 42];
}

// ---------------------------------------------------------------------------
// Where everything is
//
// Each of these answers a rectangle, because the rule the layout keeps is
// expressed in rectangles: nothing the HUD draws is over the field, with the
// boss's line as the one declared exception. `test_hud_layout` walks every box
// below, so the thing being asserted is the thing being drawn.
// ---------------------------------------------------------------------------

/// @desc The box readout `_which` occupies, as `[x1, y1, x2, y2]`.
function hud_box(_which) {
    switch (_which) {
        case "stage":
            return [HUD_COL_X, HUD_ROW_STAGE - 8,
                    HUD_COL_X + HUD_COL_W, HUD_RULE_1];
        case "tally":
            return [HUD_COL_X, HUD_ROW_BEST - 12,
                    HUD_COL_X + HUD_COL_W, HUD_ROW_GRAZE + 52];
        case "marks":
            return [HUD_COL_X, HUD_ROW_MARKS - 22,
                    HUD_COL_X + HUD_COL_W, HUD_PANEL_Y1 - HUD_PAD];
        case "life":
            return [HUD_COL_X, HUD_ROW_LIFE - 42,
                    HUD_COL_X + HUD_METER_W, HUD_ROW_LIFE + HUD_METER_H];
        case "mana":
            return [HUD_COL_X, HUD_ROW_SIGIL - 42,
                    HUD_COL_X + HUD_METER_W, HUD_ROW_SIGIL + HUD_METER_H];
        // **Deliberately over the field**, and the only one that is. See the
        // note at the top of the file and in `constants` under "The boss's
        // line".
        // **From the frame down, because the rig hangs off the frame.** The
        // box starts at `FIELD_Y0` rather than at the rail, since the chains
        // and the nameplate occupy everything between the two -- and it ends
        // under the spell's name, which is the lowest thing the line prints.
        case "boss":
            return [FIELD_X0 + BOSS_BAR_INSET, FIELD_Y0,
                    FIELD_X1 - BOSS_BAR_INSET, BOSS_SPELL_Y + 20];
    }
    return [0, 0, 0, 0];
}

/// @desc The boxes that must never touch the playfield. The boss's line is not
///       among them and that is the whole point of the list existing.
function hud_console_boxes() {
    return ["stage", "tally", "life", "mana", "marks"];
}

/// @desc Walk every eased number one frame toward where it should be, and
///       light the flares that changed.
function hud_step(_h, _g) {
    var _p = _g.player;

    // **The vessel chases the number and never leads it.** A life meter that
    // arrives at the same instant as the hit is a number changing; one that
    // drains over a third of a second is damage being *taken*, and the drain
    // is the only part the player actually sees, because the frame the hit
    // lands on is a frame full of flash and shake.
    //
    // The slosh is taken from how far the vessel still has to travel, so a
    // quarter of the bar disappearing throws the surface and a shard picked up
    // barely ripples it. Nothing has to tell the HUD a hit happened.
    _h.life_slosh = max(_h.life_slosh * 0.94,
                        min(1, abs(_p.hp - _h.life_shown) / HP_PER_HIT));
    _h.mana_slosh = max(_h.mana_slosh * 0.94,
                        min(1, abs(_p.mp - _h.mana_shown) / MP_PER_BOMB));

    _h.life_shown += (_p.hp - _h.life_shown) * 0.16;
    _h.mana_shown += (_p.mp - _h.mana_shown) * 0.22;
    _h.tally_shown += (_g.tally - _h.tally_shown) * 0.20;

    // The flares. Decayed first and then re-lit, so a change on the frame a
    // flare would have expired still reads at full strength.
    _h.life_flare = max(0, _h.life_flare - 0.045);
    _h.mana_flare = max(0, _h.mana_flare - 0.05);
    _h.tally_flare = max(0, _h.tally_flare - 0.06);
    _h.graze_flare = max(0, _h.graze_flare - 0.09);
    _h.boss_flare = max(0, _h.boss_flare - 0.03);

    // **The ledger's own flare is decayed here rather than by the ledger**, so
    // that a mark landing is a visible event without `rank_note` having to know
    // there is a screen. The ledger is a record; how loudly it is drawn is the
    // console's business, and that split is why `rank_functions` has no draw
    // call in it.
    var _led = _g[$ "marks"];
    if (_led != undefined) _led.flare = max(0, _led.flare - 0.018);

    // **The card is thrown by watching the ledger, like everything else on
    // this plate.** Nothing in the engine calls it: `hud_step` compares how
    // many marks the console has already animated with how many there are,
    // and the difference is the event. That is the same bargain the slosh and
    // the five flares are built on -- a new way to earn a mark animates
    // correctly the day it is written, because nobody had to remember to say
    // so. It also means the suites can file two hundred marks without
    // animating one.
    var _got = rank_count(_led);
    if (_got > _h.card.seen) {
        var _stage = _g[$ "stage"];
        var _total = (_stage != undefined) ? _stage.encounters : _got;
        rank_card_show(_h.card, _led.marks[_got - 1], _got - 1,
                       max(_got, _total));
    }
    _h.card.seen = _got;
    rank_card_step(_h.card);

    // **Health lost, not health changed.** Picking a shard up is a good thing
    // and should not set off the same alarm a bullet does, so the flare is one
    // sided -- which a plain `abs` difference could not express.
    if (_p.hp < _h.life_seen - 0.01) _h.life_flare = 1;
    if (_p.mp > _h.mana_seen + 0.01) {
        _h.mana_flare = max(_h.mana_flare, 0.6);
    }
    if (_g.tally > _h.tally_seen) {
        // Scaled by how much was scored, so a shard ticks and a captured
        // spell lands. Sixty thousand points is the biggest single award in
        // the game and is what saturates it.
        _h.tally_flare = max(_h.tally_flare,
                             min(1, (_g.tally - _h.tally_seen) / 12000));
    }
    if (_p.graze_n > _h.graze_seen) _h.graze_flare = 1;

    _h.life_seen = _p.hp;
    _h.mana_seen = _p.mp;
    _h.tally_seen = _g.tally;
    _h.graze_seen = _p.graze_n;

    var _boss = enemy_find_boss();
    // **In attack practice the rail is the attack, not the fight.** The boss
    // still has the whole fight's health and the attack still ends at its own
    // threshold -- practice starts it where the attack starts and changes
    // nothing about the rules -- but a spell that runs from 65% to 50% read
    // as exactly that, which is a figure about a fight nobody is having. The
    // rail and the counter read the boss's health as a share of the practised
    // attack's span instead, so it opens at 100.0 and breaks at 0.0.
    _h.boss_span = hud_boss_span(_g, _boss);
    var _want = (_boss == undefined) ? 1
              : hud_span_frac(_h.boss_span, _boss.hp / _boss.hp_max);
    _h.boss_slosh = max(_h.boss_slosh * 0.93,
                        min(1, abs(_want - _h.boss_shown) * 6));
    _h.boss_shown += (_want - _h.boss_shown) * 0.18;

    // **The counter turns toward the truth and stops on a whole tenth.** Its
    // share per frame is the vessel's own, so the number and the liquid drain
    // together; the floor on the step is what makes a single tenth roll over
    // in a few frames rather than creeping into place, and the snap is what
    // lets it come to rest square in the window. Floored rather than rounded,
    // so a boss that has taken any damage at all no longer reads 100.0.
    var _pct_want = clamp(floor(_want * 1000 + 0.0001), 0, 1000);
    var _pd = _pct_want - _h.pct_roll;
    if (abs(_pd) <= COUNTER_MIN_STEP) {
        _h.pct_roll = _pct_want;
    } else {
        _h.pct_roll += sign(_pd) * max(abs(_pd) * COUNTER_EASE,
                                       COUNTER_MIN_STEP);
    }

    // A phase boundary crossed is the one event in a fight worth marking on
    // the bar itself, and the bar is the only thing that knows it happened --
    // the boss's own phase index is the fact, and comparing it here costs an
    // integer.
    // **The rig is lowered by watching, like everything else on this plate.**
    // Nothing in the engine says "a boss has arrived": the console compares
    // what is on the field with what it is showing, which is the same bargain
    // the slosh and the five flares are built on and the reason a midboss, a
    // practised attack and a drafting-table row all get the arrival without
    // any of them being told to ask for one.
    //
    // It comes down for a boss that is on the field and not yet beaten, so it
    // is already hanging through the arrival and the declaration -- which is
    // the two seconds the movement exists to fill -- and draws back up over a
    // dying one while the body is still flying off the top.
    var _over = (_g[$ "phase"] == Phase.Won || _g[$ "phase"] == Phase.Lost);
    var _hung = (_boss != undefined) && !_boss.boss.beaten
                && !(_over && _g[$ "practice"] != undefined);
    _h.rig_v += ((_hung ? 1 : 0) - _h.rig) * BOSS_RIG_K
                - _h.rig_v * BOSS_RIG_D;
    _h.rig = max(0, _h.rig + _h.rig_v);

    // The landing: the one frame the chains come up taut. Caught by watching
    // the rig cross its own resting place rather than by a timer, so it fires
    // once however long the drop took.
    _h.rig_flare = max(0, _h.rig_flare - 0.045);
    if (_h.rig >= 1 && _h.rig_seen < 1) _h.rig_flare = 1;
    _h.rig_seen = _h.rig;

    var _ph_now = (_boss == undefined) ? -99 : _boss.boss.phase;
    if (_ph_now != _h.boss_phase_seen) {
        if (_h.boss_phase_seen != -99 && _ph_now > _h.boss_phase_seen) {
            _h.boss_flare = 1;
        }
        _h.boss_phase_seen = _ph_now;
    }

    // The nameplate arrives as the banner leaves -- see `hud_draw_spell_name`.
    var _want_spell = 0;
    if (_boss != undefined && _boss.boss.started && !_boss.boss.beaten) {
        var _ph = boss_phase(_boss);
        if (_ph != undefined && _ph.kind == AttackKind.Spell
            && _boss.boss.clear_t <= 0 && _boss.boss.banner_t <= 0) {
            _want_spell = 1;
        }
    }
    _h.spell_a += (_want_spell - _h.spell_a) * 0.10;
}

// ---------------------------------------------------------------------------
// The console
// ---------------------------------------------------------------------------

/// @desc Everything the HUD puts on the screen.
function hud_draw(_h, _g) {
    var _boss = enemy_find_boss();

    hud_draw_plate();
    hud_draw_stage(_g);
    hud_draw_score(_h, _g);
    hud_draw_meters(_h, _g);
    hud_draw_marks(_h, _g);

    // **The boss's line is not drawn from here**, and it is the only piece of
    // the HUD that is not. It hangs from the frame, so it has to go down
    // *before* the frame's mask cuts its chains off -- see
    // `hud_draw_boss_line`, which `obj_game` calls a line earlier for exactly
    // that reason.

    // **Last, so it is over the boss's line as well as over the field.** It
    // is the only thing the console draws that is not on the plate, and for
    // its second and a third it is the most important thing on the screen.
    rank_card_draw(_h.card);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The plate the console is mounted on, and the rules that divide it.
///
///       **The dividers are drawn here rather than by the sections they
///       divide**, because a rule belongs to the layout and not to either of
///       the two things it separates -- and a section that drew its own would
///       draw nothing when it had nothing to say, leaving a gap in the frame
///       every time the boss was between attacks.
function hud_draw_plate() {
    draw_plate(HUD_PANEL_X0, HUD_PANEL_Y0, HUD_PANEL_X1, HUD_PANEL_Y1);

    var _mid = HUD_COL_X + HUD_COL_W * 0.5;
    draw_rule(_mid, HUD_RULE_1, HUD_COL_W, COL_GILT, 0.9);
    draw_rule(_mid, HUD_RULE_2, HUD_COL_W, COL_GILT, 0.9);
    draw_rule(_mid, HUD_RULE_3, HUD_COL_W, COL_GILT, 0.9);

    draw_corners(HUD_PANEL_X0, HUD_PANEL_Y0, HUD_PANEL_X1, HUD_PANEL_Y1,
                 COL_GILT, 0.75, -6, 0.58);

    // **The headpiece, and a console needs one.** Four identical corners and
    // nothing else gives a panel no orientation: the eye has to find the
    // reading order rather than being handed it. Every reference this was
    // drawn against -- gilt bookbinding, an illuminated page, a profile card
    // -- puts a crest at the head of the panel, and the crescent in it is the
    // same mark the divider rules carry. One motif at three sizes is a house
    // style; three motifs is a collection.
    var _cw = HUD_COL_W;
    var _cs = _cw / sprite_get_width(spr_ui_crest);
    draw_sprite_ext(spr_ui_crest, 0, _mid - _cw * 0.5,
                    HUD_PANEL_Y0 + HUD_ROW_CREST, _cs, _cs, 0, COL_GILT, 0.9);
}

/// @desc The stage's name, at the head of the console.
///
///       **It moved out of the field.** The strip above the playfield used to
///       carry it, on the grounds that a hundred and sixty pixels of screen
///       existing for the boss's bar should not be empty for the two minutes
///       before the boss arrives. With the strip gone the argument goes with
///       it, and the name is better here anyway: the field is for the game and
///       a console is for the facts about it.
function hud_draw_stage(_g) {
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    draw_set_font(fnt_ui());
    draw_text_fit(HUD_COL_X, HUD_ROW_STAGE, string_upper(_g.def.name),
                  HUD_COL_W, COL_GILT_LIT, 0.95, 2);
    draw_set_font(fnt_small());
    draw_text_fit(HUD_COL_X, HUD_ROW_STAGE + 44, _g.def.subtitle,
                  HUD_COL_W, merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.45),
                  1, 2);
}

/// @desc The stage's best, this attempt's score, and the graze count.
///
///       **The best goes above the score, which is the genre's own order and
///       is right for a reason.** A score in isolation is a number; a score
///       under the number it is trying to beat is a *position*, and this game
///       is built out of stages replayed until they are clean. It costs one
///       lookup into progress and it is the closest thing the console has to a
///       reason to keep playing.
///
///       **The score is the one readout that swells.** It is also the only one
///       a player never has to read *during* a pattern, which is what makes an
///       animation on it affordable: a number that grows and settles is a
///       number you notice out of the corner of your eye and can then ignore,
///       and noticing is the whole of what a score is for.
function hud_draw_score(_h, _g) {
    var _p = _g.player;
    // **The definition says what BEST means, and the console does not ask.** A
    // stage's best is the saved record for its id; an attack practised on its
    // own has no stage record and must never write one, so its definition
    // carries its own -- the best score on that attack this session. Same
    // readout, same row, one accessor: the alternative is the console knowing
    // there is such a thing as practice, which is exactly what
    // `practice_new`'s stage-def-shaped definition exists to avoid.
    var _best = _g.def[$ "best"] ?? progress_stage(_g.def.id).best;

    // Lit once this attempt has passed it, because that is the only moment the
    // number means anything different from what it meant a second ago.
    var _beaten = (_g.tally > _best && _best > 0);
    hud_row(HUD_ROW_BEST, "BEST", string(max(_best, 0)), fnt_ui(),
            _beaten ? merge_colour(COL_GRAZE, c_white,
                                   0.3 + 0.3 * dsin(_g.t * 4))
                    : merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.15),
            _beaten ? 1 : 0.8);

    var _f = _h.tally_flare;
    if (_f > 0.02) {
        draw_bloom(HUD_COL_X + HUD_COL_W * 0.72, HUD_ROW_SCORE,
                   HUD_COL_W * 0.9, COL_GRAZE, _f * 0.24);
    }
    hud_row(HUD_ROW_SCORE, "SCORE", string(round(_h.tally_shown)), fnt_num(),
            merge_colour(COL_GRAZE, c_white, _f * 0.65), 1, 1 + _f * 0.09);

    hud_row(HUD_ROW_GRAZE, "GRAZE", string(_p.graze_n), fnt_ui(),
            merge_colour(COL_PARCHMENT, COL_RUNE,
                         0.2 + _h.graze_flare * 0.8), 1);
}

/// @desc One row of the console: a tracked tag on the left, a value on the
///       right, both centred on the same line.
///
///       **Every readout in the console goes through this, and that is the
///       whole point of it existing.** The score used to draw its own tag at
///       `y` and its numerals at `y + 34`, which put the one number the eye
///       goes to on a second line below and to the right of its own label --
///       out of line with `BEST` and `GRAZE` either side of it, and spending a
///       whole row of plate to say what the other rows say in one. Reported as
///       "the score text and actual score values aren't vertically aligned,
///       which isn't leaving much space", which is both halves of it.
///
///       **The alignment is `fa_middle` and it has to be.** A tag at 26pt and
///       a value at 56pt drawn from the same top edge are not on the same line
///       at all -- the small one floats at the top of the big one's cell. What
///       makes two different sizes read as one row is a shared centre, which is
///       also the one thing that stays true when a font changes.
function hud_row(_y, _tag, _value, _font, _col, _alpha = 1, _scale = 1) {
    draw_set_valign(fa_middle);

    draw_set_halign(fa_left);
    draw_set_font(fnt_small());
    // **A tag is antique gold, not grey.** It is the most-repeated element on
    // the console -- five of them down the column -- so it is what sets the
    // panel colour more than any single ornament does, and grey caption text
    // over violet is the exact combination that reads as a settings dialog.
    draw_text_tracked(HUD_COL_X, _y, _tag, 6, HUD_TAG_COL, 1, 2);

    draw_set_halign(fa_right);
    draw_set_font(_font);
    draw_text_outline_scaled(HUD_COL_X + HUD_COL_W, _y, _value, _col, _alpha,
                             _scale, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The console's bottom section: the marks earned so far, the standing
///       they add up to, and what earned the last few.
///
///       **This replaces a control legend, and the legend was the wrong tenant
///       for a third of the console.** A legend is read once, on the way in,
///       and this game has five keys; giving three hundred pixels of plate to
///       something a player stops seeing on their second run is exactly the
///       waste that removed the strip above the field.
///
///       What is here instead is a mark per encounter and the standing they
///       average to. Everything above it on the console is a number that is
///       true this frame; this is the only thing that is a record of the
///       attempt, and the only part a player has a reason to look at *between*
///       encounters.
///
///       **It is the row of marks and nothing else.** An itemised list of the
///       last few, named and graded, lived under the row for one pass -- and
///       it was never asked for. It went in to fill the space the spell
///       nameplate left when that moved to the boss's line, which is a reason
///       to re-space a layout and not a reason to invent a readout. A ledger
///       of what each encounter scored belongs on the result screen, where
///       there is a whole page for it and the player has stopped dodging.
///
///       **The sockets are drawn before they are earned**, which is most of
///       why the block never reads as empty. A stage opens showing fourteen
///       hollows: how long this is going to be, how much of it is left, and
///       that there is something here to fill in. The total is counted off
///       the stage's own timeline -- see `stage_count_encounters` -- rather
///       than typed into the stage definition, which is what it used to be
///       and which was already wrong by one on stage one.
function hud_draw_marks(_h, _g) {
    var _x = HUD_COL_X;
    var _y = HUD_ROW_MARKS;
    var _cx = _x + HUD_COL_W * 0.5;
    var _led = _g[$ "marks"];

    // The watermark, behind everything. Two counter-rotating copies at a tenth
    // of the brightness of anything else on the plate: a texture rather than a
    // picture, which is the only thing a background behind live text may be.
    var _ring = merge_colour(COL_GILT, COL_RUNE, 0.35);
    var _rs = 330 / sprite_get_width(spr_boss_sigil);
    var _wy = (_y + HUD_PANEL_Y1) * 0.5;
    draw_sprite_ext(spr_boss_sigil, 0, _cx, _wy, _rs, _rs,
                    current_time * 0.004, _ring, 0.14);
    draw_sprite_ext(spr_boss_sigil, 0, _cx, _wy, _rs * 0.66, _rs * 0.66,
                    -current_time * 0.006, _ring, 0.11);

    // The tag and the standing, on the same row every other readout uses.
    // **Nothing at all until something has been graded**, because an attempt
    // nobody has marked yet is not a bad attempt, and a console reading SLAG
    // before the first wave would be telling the player they were losing.
    var _overall = rank_overall(_led);
    var _perfect = rank_is_perfect(_led);
    var _flare = (_led == undefined) ? 0 : _led.flare;
    if (_overall < 0) {
        draw_set_valign(fa_middle);
        draw_set_halign(fa_left);
        draw_set_font(fnt_small());
        draw_text_tracked(_x, _y, "MARKS", 6, HUD_TAG_COL, 1, 2);
        draw_text_tracked(_x + HUD_COL_W, _y, "UNMARKED", 6,
                          merge_colour(HUD_TAG_COL, COL_ARCANE, 0.45), 1, 2,
                          fa_right);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    } else {
        // **Shortened to one word, and never abbreviated anywhere else.**
        // "ABSOLUTE AMETHYST" set at 56px does not fit a 416-pixel column
        // beside its own tag, and shrinking the value to fit would make the
        // one standing worth chasing the smallest thing on the plate. The
        // row is drawn in a colour no other standing uses, so the word it
        // drops is the one the colour is already saying.
        var _oc = rank_overall_colour(_led);
        if (_flare > 0.02 || _perfect) {
            draw_bloom(_x + HUD_COL_W - 60, _y, 220, _oc,
                       max(_flare * 0.35, _perfect ? 0.22 : 0));
        }
        hud_row(_y, "MARKS", rank_overall_name(_led, true), fnt_ui(),
                merge_colour(_oc, c_white, _flare * 0.5), 1);
    }

    hud_draw_block_rule(_x, _y + 26,
                        (_overall < 0) ? COL_GILT : rank_overall_colour(_led),
                        0.6);

    // ---- the whole ledger, at a glance ------------------------------------
    //
    // Laid out to a pitch that shrinks only when a stage has more encounters
    // than one line can hold, and wrapped rather than compressed past a floor:
    // a mark below about twenty pixels stops being a shape and starts being a
    // dot, and a dot cannot carry a rank by colour.
    // **The total comes off the stage, which counted it from its own
    // timeline.** It used to be a number typed into the stage definition by
    // hand, and it was wrong on stage one -- see `stage_count_encounters`.
    // The `max` stays: a stage that files more marks than it predicted grows
    // the row rather than clipping it.
    var _got = rank_count(_led);
    var _stage = _g[$ "stage"];
    var _want = (_stage != undefined)
        ? _stage.encounters : (_g.def[$ "encounters"] ?? _got);
    var _total = max(_got, _want);
    if (_total > 0) {
        for (var _i = 0; _i < _total; _i++) {
            var _at = hud_mark_xy(_i, _total);
            var _mx = _at[0];
            var _cy2 = _at[1];

            if (_i < _got) {
                var _m = _led.marks[_i];
                var _mc = mark_colour(_m.tier);
                // The newest one still glowing, so a mark landing is something
                // that happened rather than something that is simply now true.
                var _new = (_i == _got - 1) ? _flare : 0;
                if (_m.tier >= Mark.Gold) {
                    draw_bloom(_mx, _cy2, 44, _mc, 0.18 + _new * 0.5);
                }
                var _s = 1 + _new * 0.35;
                draw_sprite_ext(spr_ui_mark, _m.spell ? 1 : 0, _mx, _cy2,
                                _s, _s, 0,
                                merge_colour(_mc, c_white, _new * 0.6), 1);
            } else {
                // **A socket has to be legible, not merely present.** At the
                // alpha this started on the row read as a smudge, and a row of
                // smudges says nothing about how much of the stage is left --
                // which is half of what drawing the unearned ones is for.
                draw_sprite_ext(spr_ui_mark, 2, _mx, _cy2, 1, 1, 0,
                                merge_colour(COL_GILT, COL_ARCANE, 0.4), 0.85);
            }
        }
    }

}

/// @desc The hairline under a block's tag. A rule under a heading, not a panel
///       behind a paragraph: a panel is a rectangle, and a rectangle in a
///       console that is already made of rectangles says nothing.
function hud_draw_block_rule(_x, _y, _col, _alpha) {
    draw_set_alpha(_alpha);
    draw_set_colour(_col);
    draw_rectangle(_x, _y, _x + HUD_COL_W, _y + 2, false);
    draw_set_alpha(_alpha * 0.35);
    draw_rectangle(_x, _y + 2, _x + HUD_COL_W, _y + 3, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The two meters, directly under the score block.
function hud_draw_meters(_h, _g) {
    var _p = _g.player;

    // **A quarter left beats.** The number is the one thing on screen the
    // player cannot afford to have stopped noticing, and a colour that moves
    // is noticed without being looked at.
    var _low = (_p.hp <= HP_PER_HIT);
    var _life_col = _low
        ? merge_colour(COL_LIFE, c_white, 0.35 + 0.35 * dsin(_g.t * 9))
        : COL_LIFE;

    hud_meter(HUD_ROW_LIFE, "LIFE", string(round(_p.hp)),
              _h.life_shown / HP_MAX, _life_col,
              HP_MAX div HP_PER_HIT, _h.life_slosh, _h.life_flare, _low, 11);

    // The sigil reads differently from life: what matters is not how full it
    // is but whether it is over the line. So the glass goes cold and grey
    // below a quarter and comes up to its own full colour above it -- and
    // *that is all the liquid does*. Ready used to whiten the fill as well,
    // which turned a 416-pixel tube into a bar of pale cyan every time the
    // meter did its job. The rim pulsing and the sheen travelling say ready;
    // the liquid says how much.
    var _ready = _p.mp >= MP_PER_BOMB;
    var _mana_col = _ready ? COL_MANA
                           : merge_colour(COL_MANA, COL_SLATE, 0.5);

    hud_meter(HUD_ROW_SIGIL, _ready ? "SIGIL  READY" : "SIGIL",
              string(round(_p.mp)), _h.mana_shown / MP_MAX, _mana_col,
              MP_MAX div MP_PER_BOMB, _h.mana_slosh, _h.mana_flare, _ready, 71);
}

/// @desc One meter: a tracked name and a value on one line, and the tube under
///       them.
///
///       **The name and the value share a line above the glass rather than
///       riding in it.** Upright, the value sat on the liquid because the
///       surface is where the eye already is; lying down there is no room for
///       a 56pt numeral inside 56 pixels of tube, and putting one there
///       shrinks it to the size of a footnote. Above the tube it gets the size
///       it wants, and the surface still carries the reading -- which was
///       always the vessel's job, not the number's.
function hud_meter(_y, _name, _value, _fraction, _col, _divs, _slosh, _flare,
                   _ready, _seed) {
    // The same row every other readout uses, so a meter's name and its value
    // sit on one line with each other and with `SCORE` four rows above.
    hud_row(_y - 24, _name, _value, fnt_ui(),
            merge_colour(COL_PARCHMENT, c_white, _flare * 0.8), 1);

    draw_gauge_h(HUD_COL_X, _y, HUD_METER_W, HUD_METER_H, _fraction, _col, 1, {
        quadrants: _divs,
        slosh: _slosh,
        seed: _seed,
        ready: _ready,
        glow: _flare,
    });

    // A flush of the meter's own colour across the whole tube when it changed.
    // Additive and short: it is the difference between a bar that moved and
    // damage that was *done*, and it is the only thing on the console loud
    // enough to be seen without being looked at.
    if (_flare > 0.02) {
        draw_bloom(HUD_COL_X + HUD_METER_W * 0.5, _y + HUD_METER_H * 0.5,
                   HUD_METER_W * 1.1, _col, _flare * 0.30);
    }
}

// ---------------------------------------------------------------------------
// The boss's line
//
// **It is a rig now, not a bar.** What used to be here was a fourteen-pixel
// tube pinned flush to the top of the field with its phase boundaries marked
// by rectangles poking out of it, a small tracked name at one end and a large
// numeral at the other. Every part of that was legible and none of it was an
// *object*: it existed the frame a fight started and vanished the frame one
// ended, and the two readouts on it were at two sizes for no reason anybody
// chose.
//
// What is drawn now is a gilded rail hung on two chains that run up out of the
// top of the frame, with the health in a channel cut down it, a graduated
// scale on its flanges, and a cartouche at its left end carrying the boss's
// health to a tenth of a per cent. Under it, on one line: what is being cast
// at the left, who is casting in the middle, and how long is left at the
// right -- all three at sizes that belong to each other.
//
// **Drawn before the field's mask**, which is what lets the chains be cut off
// by the frame rather than clamped by arithmetic. See the note in
// `hud_draw_boss_line`.
// ---------------------------------------------------------------------------

/// @desc The stretch of a boss's health the rail spans, as `[top, bottom]`
///       fractions of its whole health.
///
///       **The whole fight, except in attack practice.** There the attempt is
///       one attack, and a rail spanning the fight would open a spell at 65.0
///       and break it at 50.0 -- accurate about a fight nobody is having and
///       useless for the one they are. So in practice the span is the attack's
///       own: from where the attack before it ends to where this one does,
///       read off the same phase table the boss is running, so the rail cannot
///       disagree with when the attack will actually break.
///
///       Read off the practice *request* rather than off the boss's current
///       phase, because the attempt opens in a pause where the boss is on no
///       phase at all -- and the rail is already down by then.
function hud_boss_span(_g, _boss) {
    var _pr = _g[$ "practice"];
    if (_pr == undefined || _boss == undefined) return [1, 0];
    var _ph = _boss.boss.phases;
    var _i = _pr.phase_i;
    if (_i < 0 || _i >= array_length(_ph)) return [1, 0];
    var _top = (_i > 0) ? _ph[_i - 1].hp_end : 1;
    return [_top, _ph[_i].hp_end];
}

/// @desc A fraction of a boss's whole health, as a fraction of `_span`.
function hud_span_frac(_span, _f) {
    var _d = _span[0] - _span[1];
    if (_d <= 0.0001) return clamp(_f, 0, 1);
    return clamp((_f - _span[1]) / _d, 0, 1);
}

/// @desc Where the rail is this frame, given how far the rig has come down.
///
///       **One answer, because four things read it** -- the chains, the
///       terminals, the rail and everything printed under it -- and a rig
///       whose caption did not travel with its bar would come apart on the way
///       down.
function hud_rig_y(_h) {
    return lerp(BOSS_RIG_STOW, BOSS_BAR_Y, _h.rig);
}

/// @desc The boss's line: the rig it hangs from, the rail, the readouts on it
///       and the caption under it.
///
///       **Called from the GUI event before `field_draw_frame`, and that is
///       the whole reason it is not drawn with the rest of the console.** The
///       chains run *up out of the top of the field* and have to stop being
///       visible at the boundary; the frame's mask is four opaque rectangles
///       painted over everything outside the field, so drawing the rig under
///       it cuts the chains off at exactly the line the frame is on, for free.
///       Clamping them in arithmetic instead would be the thing
///       `BG_NEAR_EDGE`'s window and `cut_pad`'s margin are both notes about:
///       a number that can be got wrong where a construction cannot.
///
///       It is also what makes the *arrival* possible. The rail is stowed
///       above `FIELD_Y0`, which is to say behind the mask, so "hidden" is a
///       fact about where it is rather than an alpha somebody has to remember
///       to set -- and lowering it into view is one number.
function hud_draw_boss_line(_h, _g) {
    if (_h.rig <= 0.004) return;

    var _boss = enemy_find_boss();
    var _x1 = FIELD_X0 + BOSS_BAR_INSET;
    var _x2 = FIELD_X1 - BOSS_BAR_INSET;
    var _y  = hud_rig_y(_h);
    var _cy = _y + BOSS_BAR_H * 0.5;
    var _a  = clamp(_h.rig * 1.6, 0, 1);

    // What the liquid is coloured. The current attack's hue while there is
    // one, and the caster's own before the fight has started -- the rail comes
    // down during the arrival, when `boss_phase` is still `undefined`, and a
    // bar that arrived in the health meter's pink and changed colour on the
    // frame the first attack opened would read as a fault.
    var _p = (_boss == undefined) ? undefined : boss_phase(_boss);
    var _col = COL_LIFE;
    if (_p != undefined) _col = global.bullet_colour[_p.col];
    else if (_boss != undefined) {
        _col = global.bullet_colour[_boss.boss.def.col];
    }

    // --- the rig itself ------------------------------------------------
    //
    // **Chain, then rail, then terminal**, and the order is the assembly's.
    // The chain is cut at the terminal's eye and the eye drawn over the cut,
    // so the last link is never a link sawn in half; the collar clasps the
    // rail, so it has to be in front of it. Drawn the other way round -- which
    // it was for one screenshot -- the rail paints over its own hardware and
    // what is left is a bar with two small knobs floating above it.
    var _eye = _cy - (sprite_get_yoffset(spr_ui_hanger) - UI_HANGER_EYE);
    for (var _s = 0; _s < 2; _s++) {
        var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
        draw_chain(_hx, FIELD_Y0 - 30, _eye, COL_GILT, _a);
    }

    draw_rail(_x1, _y, _x2 - _x1, BOSS_BAR_H, _a);

    // --- the health, in the channel cut down the rail -------------------
    //
    // **The two ends carry the two things that are fractions.** The cartouche
    // at the left holds the boss's health as a number and the dial at the
    // right holds the attack's clock; between them is the channel, which is
    // the same pair of facts as a shape. Both are set in from the terminals by
    // the same margin, so the rail reads as one instrument rather than as a
    // bar with things on it.
    var _px0 = _x1 + BOSS_RIG_END + 22;
    var _dx  = _x2 - BOSS_RIG_END - 28 - BOSS_DIAL_D * 0.5;
    var _ch_x = _px0 + BOSS_PCT_W + 14;
    var _ch_w = (_dx - BOSS_DIAL_D * 0.5 - 14) - _ch_x;
    var _ch_y = _cy - BOSS_BAR_CHANNEL * 0.5;

    // **The liner is bronze, not the console's slate.** A vessel takes the
    // colour of whatever it is set into, and this one is set into gold -- a
    // cool grey ring inside a gilded rail reads as a fitting in a different
    // alloy rather than as a recess, which is exactly what photographed when
    // the rail was first drawn round it.
    draw_gauge_h(_ch_x, _ch_y, _ch_w, BOSS_BAR_CHANNEL, _h.boss_shown, _col,
                 _a, {
        slosh: _h.boss_slosh,
        glow: _h.boss_flare,
        seed: 29,
        rim: merge_colour(COL_GILT, COL_VOID, 0.52),
    });

    // **A recess is read off the shadow its lip casts into it**, not off the
    // fact that it is dark. One hairline of void along the channel's upper
    // contour is the whole of it, and it is the difference between a slot cut
    // into a bar and a dark stripe painted along one.
    gpu_set_blendmode(bm_normal);
    draw_primitive_begin(pr_trianglestrip);
    var _lipr = BOSS_BAR_CHANNEL * 0.5;
    var _lxs = capsule_samples(_ch_x, _ch_x + _ch_w, _lipr, _ch_x + _ch_w);
    for (var _i = 0; _i < array_length(_lxs); _i++) {
        var _lx = _lxs[_i];
        var _lh = capsule_half(_lx, _ch_x, _ch_x + _ch_w, _lipr);
        draw_vertex_colour(_lx, _cy - _lh, COL_VOID, _a * 0.55);
        draw_vertex_colour(_lx, _cy - _lh + 2.4, COL_VOID, 0);
    }
    draw_primitive_end();

    hud_rail_scale(_h, _boss, _ch_x, _ch_w, _cy, _col, _a);

    // --- the readouts ---------------------------------------------------
    var _ta = clamp((_h.rig - 0.42) * 2.4, 0, 1);
    // **The dial is hardware and is drawn whether or not there is a clock.** A
    // rail that grew a bezel on the frame an attack started and lost it again
    // between attacks would read as the instrument coming apart; what the
    // clock changes is what is *in* the dial, which is what a dial is for.
    hud_draw_boss_dial(_h, _boss, _dx, _cy, _a);
    if (_boss != undefined) {
        hud_draw_boss_pct(_h, _px0, _cy, _col, _a);
        hud_draw_boss_plate(_boss, _y - BOSS_BAR_Y, _a, _ta);
        hud_draw_boss_caption(_h, _boss, _p, _y - BOSS_BAR_Y, _ta);
    }

    // The terminals last, so each collar is in front of the metal it clasps.
    for (var _s = 0; _s < 2; _s++) {
        var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
        draw_sprite_ext(spr_ui_hanger, 0, _hx, _cy, 1, 1, 0, COL_GILT, _a);
    }

    // **The landing, said at the hardware rather than across the field.** A
    // rail this size arriving with no impact anywhere reads as a sprite being
    // moved; a flash at the two points actually taking the load reads as
    // something coming up short on its chains. Additive and small, on
    // `grove_draw_front`'s rule -- light can only brighten what is behind it,
    // so nothing here can hide a bullet at any strength.
    if (_h.rig_flare > 0.02) {
        var _f = _h.rig_flare;
        for (var _s = 0; _s < 2; _s++) {
            var _hx = (_s == 0) ? (_x1 + BOSS_RIG_END) : (_x2 - BOSS_RIG_END);
            draw_bloom(_hx, _cy, 120 * (1.4 - _f), COL_GILT_LIT, _f * 0.5);
        }
        // And a sheen running out from the middle along the metal, which is
        // the rail's own length being announced. It is the same move the sigil
        // meter makes when it is ready, run once instead of forever.
        gpu_set_blendmode(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        var _sw = (_x2 - _x1) * 0.5 * (1 - _f);
        for (var _s = -1; _s <= 1; _s += 2) {
            draw_vertex_colour(FIELD_CX + _sw * _s, _y, COL_GILT_LIT, 0);
            draw_vertex_colour(FIELD_CX + _sw * _s, _y + BOSS_BAR_H,
                               COL_GILT_LIT, 0);
        }
        draw_primitive_end();
        draw_bloom(FIELD_CX + _sw, _cy, 90, COL_GILT_LIT, _f * 0.35);
        draw_bloom(FIELD_CX - _sw, _cy, 90, COL_GILT_LIT, _f * 0.35);
        gpu_set_blendmode(bm_normal);
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The graduations on the rail's flanges and the phase boundaries cut
///       through them.
///
///       **The minor ticks are what make it an instrument.** A scale with only
///       the values that matter marked on it is a diagram; one with a regular
///       graduation behind those is a thing that was manufactured, and it
///       costs nineteen hairlines. They are on both flanges, because a rule
///       graduated on one edge only reads as having been printed on rather
///       than cut into.
///
///       **A boundary is dark where it crosses the liquid and pale where it
///       crosses the empty channel.** One colour cannot do both: a dark notch
///       on the unfilled half of a near-black channel is not there at all, and
///       that is the half of the bar saying how much of the fight is left.
///
///       **A spell's boundary carries a stud under the metal and a non-spell's
///       does not**, so the shape of the fight -- where the named attacks are
///       -- is legible before any of them has been reached. They were
///       rectangles standing out of the top and bottom of the tube before,
///       which is the readout this whole line was reported as looking
///       primitive for.
function hud_rail_scale(_h, _boss, _x, _w, _cy, _col, _alpha) {
    var _r = BOSS_BAR_CHANNEL * 0.5;
    var _lo = _x + _r;
    var _hi = _x + _w - _r;

    // The graduation, on both flanges of the casing.
    var _top = _cy - BOSS_BAR_H * 0.5;
    var _bot = _cy + BOSS_BAR_H * 0.5;
    draw_set_colour(COL_GILT_LIT);
    for (var _i = 1; _i < RAIL_GRADS; _i++) {
        var _gx = lerp(_lo, _hi, _i / RAIL_GRADS);
        var _major = (_i mod 5 == 0);
        var _len = _major ? 4.6 : 2.6;
        // A dark groove with a pale line beside it, which is what the console's
        // divisions are engraved with and the only thing that reads as a cut
        // rather than as a painted mark. A single hairline in gilt on gilt at
        // this size is not there at all -- it was drawn that way first and the
        // scale photographed blank.
        draw_set_colour(COL_VOID);
        draw_set_alpha(_alpha * (_major ? 0.75 : 0.5));
        draw_rectangle(_gx - 1, _top + 2.4, _gx, _top + 2.4 + _len, false);
        draw_rectangle(_gx - 1, _bot - 2.4 - _len, _gx, _bot - 2.4, false);
        draw_set_colour(COL_GILT_LIT);
        draw_set_alpha(_alpha * (_major ? 0.6 : 0.36));
        draw_rectangle(_gx, _top + 2.4, _gx + 1, _top + 2.4 + _len, false);
        draw_rectangle(_gx, _bot - 2.4 - _len, _gx + 1, _bot - 2.4, false);
    }

    if (_boss == undefined) {
        draw_set_alpha(1);
        draw_set_colour(c_white);
        return;
    }

    // The boundaries, from the table, so they cannot disagree with where the
    // attacks actually end.
    var _ph = _boss.boss.phases;
    var _now = _boss.boss.phase;
    for (var _i = 0; _i < array_length(_ph); _i++) {
        // Mapped into the rail's span, so in practice -- where the rail is one
        // attack -- every other attack's boundary falls off one end and is
        // not drawn, rather than being notched somewhere the liquid can never
        // reach.
        var _f = hud_span_frac(_h.boss_span, _ph[_i].hp_end);
        if (_f <= 0.001 || _f >= 0.999) continue;
        var _nx = _lo + (_hi - _lo) * _f;
        var _spell = (_ph[_i].kind == AttackKind.Spell);
        var _on_liquid = (_f <= _h.boss_shown + 0.001);

        // **The one still being fought for pulses.** Everything else on this
        // scale says where the fight has been; the next boundary down is the
        // only one that says what the player is working toward, and it is free
        // to say so because it is the one mark nothing else is competing with.
        var _live = (_i == _now);
        var _puls = _live ? (0.55 + 0.45 * dsin(current_time * 0.22)) : 1;

        // The groove through the channel.
        draw_set_colour(_on_liquid ? COL_VOID : COL_GILT_LIT);
        draw_set_alpha(_alpha * (_on_liquid ? 0.9 : 0.75) * _puls);
        draw_rectangle(_nx - 1, _cy - _r + 0.5, _nx, _cy + _r - 0.5, false);
        draw_set_colour(_on_liquid ? merge_colour(_col, c_white, 0.7)
                                   : COL_GILT);
        draw_set_alpha(_alpha * (_on_liquid ? 0.6 : 0.4) * _puls);
        draw_rectangle(_nx, _cy - _r + 0.5, _nx + 1, _cy + _r - 0.5, false);

        // The key cut through the flanges: a full-depth notch for a spell and
        // a shallow one for a non-spell.
        var _deep = _spell ? (BOSS_BAR_H * 0.5) : (BOSS_BAR_H * 0.5 - 4);
        draw_set_colour(COL_GILT_LIT);
        draw_set_alpha(_alpha * (_spell ? 0.85 : 0.5) * _puls);
        draw_rectangle(_nx - 1, _cy - _deep, _nx + 1, _cy - _r, false);
        draw_rectangle(_nx - 1, _cy + _r, _nx + 1, _cy + _deep, false);

        if (_spell) {
            // The stud: a small lozenge sitting proud of the metal, in the
            // same family as the lozenge the console's ledger marks a spell
            // with -- one motif at two sizes, which is the rule the crescent
            // in the rules and the crest is under.
            //
            // **Under the rail, and it was on top.** The top of the rail is
            // where the nameplate stands now, and a stud rising into it
            // wherever a spell's boundary falls near the middle is two pieces
            // of hardware in one place. Underneath, a stud is seven pixels of
            // gold at the one height the rail already costs the field.
            var _sy = _cy + BOSS_BAR_H * 0.5 + 4;
            var _sr = 5 * (_live ? (0.9 + 0.22 * dsin(current_time * 0.22))
                                 : 1);
            draw_set_alpha(_alpha * 0.9);
            draw_set_colour(COL_GILT_LIT);
            draw_triangle(_nx, _sy - _sr, _nx - _sr * 0.62, _sy,
                          _nx + _sr * 0.62, _sy, false);
            draw_triangle(_nx, _sy + _sr, _nx - _sr * 0.62, _sy,
                          _nx + _sr * 0.62, _sy, false);
            if (_live) draw_bloom(_nx, _sy, 34, COL_GILT_LIT, 0.30 * _alpha);
        }
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The boss's health as a percentage, in the cartouche at the rail's
///       left end.
///
///       **A tube answers "roughly how much" and cannot answer "how close is
///       this to breaking".** In the last tenth of an attack the liquid moves
///       a few pixels for damage the player can feel landing, which reads as
///       the bar having stopped responding; a tenth of a per cent is a number
///       that visibly moves for every shot that connects. The two are not a
///       duplicate readout -- the bar is a shape and this is a value, and the
///       genre has always wanted both.
///
///       **It is a counter, and it used to be a string.** Redrawn every frame
///       from the eased value, the digits simply *were* a different number on
///       the next frame, which the eye has to notice rather than being shown.
///       On wheels, damage is a digit rolling down out of the window and the
///       next rolling in over the top, and a big loss spins the low wheels
///       while the high ones turn over once -- see `draw_counter_wheel`.
///
///       **It turns at the vessel's own rate**, driven by `pct_roll` rather
///       than by the liquid's number: that one converges on the truth and
///       almost never lands on a whole tenth, so a counter driven by it would
///       stand part-turned for the whole attack. The two share `COUNTER_EASE`
///       with the liquid's ease, so they drain together and cannot be seen to
///       disagree -- the defect the note above `hall_orb_x` in `bg_sanctum`
///       is about, one screen over.
function hud_draw_boss_pct(_h, _x, _cy, _col, _alpha) {
    // **The ground is a drum, not a hole.** Flat void behind a counter reads
    // as digits printed on black; a field lit across its middle and falling
    // away to dark at top and bottom reads as a cylinder the digits are
    // painted on, which is what makes the roll read as the drum turning
    // rather than as numbers sliding. Opaque, because at eighty-two per cent
    // the stage's embers came through it and sat on it as warm blobs.
    var _gx = _x + 9;
    var _gw = BOSS_PCT_W - 18;
    var _gh = BOSS_PCT_H - 14;
    var _gr = _gh * 0.5;
    var _gxs = capsule_samples(_gx, _gx + _gw, _gr, _gx + _gw);
    var _drum = merge_colour(COL_VOID, COL_ARCANE, 0.6);
    for (var _side = -1; _side <= 1; _side += 2) {
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < array_length(_gxs); _i++) {
            var _px = _gxs[_i];
            var _hh = capsule_half(_px, _gx, _gx + _gw, _gr);
            draw_vertex_colour(_px, _cy, _drum, _alpha);
            draw_vertex_colour(_px, _cy + _side * _hh, COL_VOID, _alpha);
        }
        draw_primitive_end();
    }

    // **Damage is said on the number as well as in the glass.** The wheels go
    // toward white while they are turning and on the frame a threshold falls,
    // which is the one event in a fight this readout is better placed to
    // report than the bar is.
    var _hot = min(1, _h.boss_slosh * 1.3 + _h.boss_flare);
    var _tint = merge_colour(COL_GILT_LIT, c_white, _hot * 0.7);
    var _p = clamp(_h.pct_roll, 0, 1000);      // tenths of a per cent
    var _sc = BOSS_PCT_SCALE;

    // **Fixed columns, laid out from the right.** A counter's wheels do not
    // move sideways, so the decimal point stays put however many digits the
    // number has -- which the proportional layout this replaced could only
    // manage by right-aligning a string that changed width under it.
    //
    // **One baseline under three sizes.** The whole part is centred on the
    // rail by its digits' ink; the tenth, the point and the sign stand on the
    // same baseline rather than on the same centre, or the small ones float
    // half way up the digits they belong to.
    draw_set_font(fnt_num());
    var _num_ink = string_height("0") * FONT_INK_RATIO * _sc;
    var _cw = string_width("0") * _sc;
    var _base = _cy + _num_ink * 0.5;
    var _rx = _x + BOSS_PCT_W - UI_PLAQUE_CHAMF - 7;

    draw_set_font(fnt_small());
    var _wpc = string_width("%");
    draw_set_halign(fa_right);
    draw_set_valign(fa_bottom);
    draw_text_outline(_rx, text_baseline_y(_base), "%", COL_GILT,
                      _alpha * 0.9, 2);

    draw_set_font(fnt_ui());
    var _tw = string_width("0");
    var _ui_ink = string_height("0") * FONT_INK_RATIO;
    var _tx = _rx - _wpc - 3 - _tw * 0.5;
    draw_counter_wheel(_tx, _base - _ui_ink * 0.5, counter_wheel_pos(_p, 0),
                       _tint, _alpha, 1, false, 2);

    var _wdot = string_width(".");
    var _dot_r = _tx - _tw * 0.5 - 1;
    draw_set_halign(fa_right);
    draw_set_valign(fa_bottom);
    draw_text_outline(_dot_r, text_baseline_y(_base), ".", _tint, _alpha, 2);

    // The whole part: units, tens and hundreds. The hundreds wheel never shows
    // a zero, and the tens wheel shows one only while there is a hundred above
    // it -- so 100.0 reads as three digits and 75.0 as two, and the roll from
    // one to the other shows the 1 leaving and nothing arriving.
    draw_set_font(fnt_num());
    var _ox = _dot_r - _wdot - 2 - _cw * 0.5;
    draw_counter_wheel(_ox, _cy, counter_wheel_pos(_p, 1), _tint, _alpha,
                       _sc, false, 3);
    draw_counter_wheel(_ox - _cw, _cy, counter_wheel_pos(_p, 2), _tint,
                       _alpha, _sc, _p < 100, 3);
    draw_counter_wheel(_ox - _cw * 2, _cy, counter_wheel_pos(_p, 3), _tint,
                       _alpha, _sc, true, 3);

    // **The moulding goes on last, over the wheels**, so a digit half turned
    // away -- which stands proud of the window by a few pixels -- disappears
    // behind the frame of the window rather than being drawn across it. It is
    // the construction a real counter has, and it is why the window needs no
    // clip.
    draw_sprite_ext(spr_ui_plaque, 0, _x + BOSS_PCT_W * 0.5, _cy, 1, 1, 0,
                    COL_GILT, _alpha);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc The attack's clock, as a dial mounted at the rail's right end.
///
///       **A clock is a fraction of something and was drawn as a bare count.**
///       The seconds left were set in the numeral face at the end of the line,
///       at a size nothing else on it shared -- so the readout that most wants
///       to be read without being parsed was the one thing here that had to
///       be. A dial answers "how much of this attack is left" the way the
///       channel beside it answers "how much of this boss is", which is the
///       vessel-over-a-bar argument applied to the last number on the line.
///
///       It is the player's own grace ring, one screen over: a faint band for
///       the whole clock, a bright arc for what is left sweeping clockwise
///       back to noon, and the head of the arc carrying the bloom because the
///       head is the part that moves. Additive, on `grove_draw_front`'s rule,
///       so nothing in it can hide a bullet.
///
///       **The count stays, inside it.** A dial says how much and a numeral
///       says how many; a player deciding whether to spend a sigil on the last
///       four seconds of a spell wants the second of those, and the middle of
///       a dial is the one place it can be printed without competing with
///       anything.
function hud_draw_boss_dial(_h, _boss, _cx, _cy, _alpha) {
    if (_alpha <= 0.004) return;

    var _r = BOSS_DIAL_D * 0.5;
    var _secs = (_boss == undefined) ? -1 : boss_time_left(_boss);
    var _p = (_boss == undefined) ? undefined : boss_phase(_boss);
    var _whole = (_p == undefined) ? 0 : max(1, _p.time);
    var _frac = (_secs < 0) ? 0 : clamp(_secs * FPS / _whole, 0, 1);
    var _urgent = (_secs >= 0 && _secs < BOSS_DIAL_URGENT);

    // The face, so the arc has something to be read against and the stage's
    // own scenery does not show through the middle of the instrument.
    draw_set_colour(COL_VOID);
    draw_set_alpha(_alpha);
    draw_circle(_cx, _cy, _r - BOSS_DIAL_D * 0.09, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    var _bz = BOSS_DIAL_D / sprite_get_width(spr_ui_dial);
    draw_sprite_ext(spr_ui_dial, 0, _cx, _cy, _bz, _bz, 0, COL_GILT, _alpha);

    if (_secs < 0) return;

    var _col = _urgent ? merge_colour(COL_GILT_LIT, COL_LIFE, 0.72)
                       : COL_GILT_LIT;
    // **Lifted toward white rather than taken to it.** At 0.45 the sweep came
    // back a pale grey ring, which is the one hue on this rail that is not
    // gold and reads as a different object entirely.
    var _lit = merge_colour(_col, c_white, 0.22);
    var _flick = _urgent ? (0.62 + 0.38 * dsin(current_time * 0.4)) : 1;
    var _rad = _r - BOSS_DIAL_D * 0.165;
    var _to = 90 - 360 * _frac;
    var _steps = max(2, ceil(360 * _frac / 6));
    var _a = _alpha * _flick;

    gpu_set_blendmode(bm_add);
    // The whole clock, so what has gone reads as gone.
    draw_arc_band(_cx, _cy, _rad - 2, _rad + 2, 0, 360, COL_GILT,
                  0.10 * _alpha, 0.10 * _alpha, 48);
    if (_frac > 0.001) {
        // **Dim at the tail and bright at the head.** Run at the strength the
        // player's grace ring is drawn at, a full clock came back as a
        // near-white ring at the end of the bar -- which is the brightest
        // thing on the screen saying the *least* interesting thing a dial can
        // say, since a fresh attack is exactly the moment nobody is reading
        // the clock. What the eye wants off this is where the head is.
        draw_arc_band(_cx, _cy, _rad - 6, _rad + 6, 90, _to, _col,
                      0.03 * _a, 0.13 * _a, _steps);
        draw_arc_band(_cx, _cy, _rad - 2.5, _rad + 2.5, 90, _to, _lit,
                      0.10 * _a, 0.52 * _a, _steps);
    }
    gpu_set_blendmode(bm_normal);
    if (_frac > 0.001) {
        draw_bloom(_cx + lengthdir_x(_rad, _to), _cy + lengthdir_y(_rad, _to),
                   BOSS_DIAL_D * 0.34, _lit, 0.42 * _a);
    }

    // **The count, on two wheels that turn over as each second goes.** It
    // was a string that changed on the frame a second elapsed, which is the
    // one moment a clock is meant to be *seen* to move. The wheel turns in
    // the first fifth of each new second and then stands still, eased so it
    // snaps over rather than drifting -- a mechanism, not a slider.
    var _n = floor(_secs);
    var _u = clamp((_secs - _n - (1 - DIAL_TICK_SHARE)) / DIAL_TICK_SHARE,
                   0, 1);
    var _pos = _n + _u * _u * (3 - 2 * _u);
    var _ncol = _urgent ? merge_colour(COL_LIFE, c_white,
                                       0.35 + 0.35 * dsin(current_time * 0.4))
                        : COL_GILT_LIT;

    // **One digit is centred and two straddle the centre**, and the pair
    // slides between the two as the tens wheel turns away, so going from ten
    // seconds to nine is one movement rather than a roll followed by a jump.
    draw_set_font(fnt_num());
    var _ncw = string_width("0") * BOSS_DIAL_SCALE;
    var _two = clamp(_pos - 9, 0, 1);
    var _ones_x = _cx + _ncw * 0.5 * _two;
    draw_counter_wheel(_ones_x, _cy, counter_wheel_pos(_pos, 0), _ncol,
                       _alpha, BOSS_DIAL_SCALE, false, 3);
    draw_counter_wheel(_ones_x - _ncw, _cy, counter_wheel_pos(_pos, 1), _ncol,
                       _alpha, BOSS_DIAL_SCALE, true, 3);
    draw_set_alpha(1);
}

/// @desc The caster's nameplate, standing on the rail.
///
///       **Small type in a setting, not large type on a field.** Free-standing
///       the name had to be set at the numeral face's own size to read as a
///       title at all, which is a great deal of outlined capitals across the
///       part of the field the boss is in. The plate is what says "this is a
///       label", so the letters no longer have to -- and it is what makes the
///       rail read as one object with a name on it rather than as a bar with a
///       caption near it.
///
///       **On top of the rail, in the gap the chains already occupy.** It was
///       hung underneath for one pass, which is a forty-pixel tab in the
///       middle of the field's top edge -- exactly where the boss stands. The
///       rail's whole job is to keep the field under it clear.
///
///       **Hardware and type fade separately.** The plate is part of the rig
///       and comes down with it at `_hw`; the name is type and eases in at
///       `_ta` once the rig is most of the way home, like everything else
///       printed on this line.
function hud_draw_boss_plate(_boss, _dy, _hw, _ta) {
    if (_hw <= 0.004) return;

    // **Tracked, because a name set solid is a word and a name opened out is a
    // title.** Measured before it is drawn, so the plate is sized to the name
    // rather than the name fitted to a plate somebody guessed at: `THE
    // PROCTOR` and `MIKA` are the two ends of that, and neither gets a hole in
    // its frame.
    var _nm = string_upper(_boss.boss.def.name);
    draw_set_font(fnt_ui());
    var _nw = text_tracked_width(_nm, BOSS_NAME_TRACK);
    var _pw = min(BOSS_PLATE_MAX_W, _nw + BOSS_PLATE_PAD * 2);
    draw_tablet(FIELD_CX, BOSS_PLATE_Y + _dy, _pw, BOSS_PLATE_H, _hw);

    if (_ta <= 0.02) return;
    // **Centred by its ink, not by its cell.** See `text_cap_middle_y`: a name
    // in capitals has no descender and sits high in a cell that reserves room
    // for one -- invisible on a free-standing caption, and the entire defect
    // on one set inside a frame.
    draw_set_valign(fa_bottom);
    draw_text_tracked(FIELD_CX, text_cap_middle_y(BOSS_NAME_Y + _dy), _nm,
                      BOSS_NAME_TRACK, COL_GILT_LIT, _ta * 0.96, 3,
                      fa_center);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc What is printed under the rail, which is the spell's name and
///       nothing else.
///
///       **The field under the rail is the boss's.** It carried the caster's
///       name, then the caster's name and the clock, then the caster's name
///       and the spell's name and a capture flag. Every one of those has moved
///       somewhere it does not cost the boss room: the name is on a plate on
///       top of the rail, the clock is a dial on it, and the capture flag is
///       gone. What is left is the one fact that changes during a fight and
///       is not a fraction of anything.
function hud_draw_boss_caption(_h, _boss, _p, _dy, _alpha) {
    if (_alpha <= 0.02) return;
    if (_p != undefined && _p.kind == AttackKind.Spell) {
        hud_draw_spell_name(_h, _boss, _p, _dy, _alpha);
    }
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}


// ---------------------------------------------------------------------------
// The ceremony
// ---------------------------------------------------------------------------

/// @desc The boss's name splash: a band, a name, a title, and a ring.
function hud_draw_declare(_boss) {
    var _b = _boss.boss;
    var _t = BOSS_DECLARE_TIME - _b.declare_t;        // frames elapsed
    var _in = min(1, _t / 18);
    var _out = min(1, _b.declare_t / 22);
    var _a = _in * _out;
    if (_a <= 0.01) return;

    draw_band(FIELD_CY, 320, 0.72 * _a);

    // The name arrives oversized and settles, which is the one piece of motion
    // that makes a title land rather than appear.
    var _scale = 1 + 0.5 * (1 - _in) * (1 - _in);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline_scaled(FIELD_CX, FIELD_CY - 40, _b.def.name,
                             global.bullet_colour[_b.def.col], _a, _scale, 3);
    draw_set_font(fnt_head());
    draw_text_outline(FIELD_CX, FIELD_CY + 80, _b.def.title, COL_SILVER,
                      _a * 0.9, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The spell banner and the eye card.
///
///       **The card is behind the banner and both are behind the field.** The
///       point of the announcement is to be looked at for about a second while
///       the pattern is still winding up -- not to hide the pattern, which by
///       then is live. So both fade out over their own life and neither ever
///       reaches full opacity over the middle of the screen.
function hud_draw_spell(_boss) {
    var _b = _boss.boss;
    var _p = boss_phase(_boss);
    if (_p == undefined || _p.kind != AttackKind.Spell) return;

    var _col = global.bullet_colour[_p.col];

    if (_b.eye_t > 0) draw_eye_card(_b.def.eye, _b.eye_t / BOSS_EYE_TIME);

    if (_b.banner_t > 0) {
        var _t = _b.banner_t / BOSS_SPELL_BANNER;
        var _in = min(1, (1 - _t) * 6);
        var _a = _in * min(1, _t * 3.2);

        // **The banner arrives where the nameplate is going to live**, oversized
        // and sliding in from the right, and shrinks onto it as it fades. That
        // is a change of place as much as of size: it used to fly in across the
        // bottom of the screen, which is the player's working area, and then
        // hand over to a plate somewhere else entirely -- two announcements of
        // one thing, in two places, neither of them where the player is
        // looking. Announcing it on the spot it will then occupy makes the
        // banner and the plate one gesture.
        // **It is announced over the field and then lives in the column.**
        // The banner is the one moment a spell's name is worth a large piece
        // of the screen, so it arrives across the middle of the play area at
        // full size and slides out to the right as it fades -- ending pointed
        // at the plate that is about to take over. Two and a half seconds of
        // ceremony over the field is affordable; forty seconds of nameplate
        // there is not, which is the whole reason the plate is in the margin.
        var _slide = (1 - _in) * 280;
        var _y = FIELD_CY + 260;

        draw_band(_y, 200, 0.6 * _a);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(fnt_spell());
        draw_text_fit(FIELD_CX + _slide, _y, _p.name,
                      FIELD_W - 120, _col, _a, 3);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }
}

/// @desc The spell's name, for as long as the spell lasts. Drawn under the
///       left end of the boss's rail, inside the field.
///
///       **The banner is ceremony and it leaves; this is information and it
///       stays.** A named attack in this genre is a thing the player learns by
///       name -- it is how they think about the attempt, how they talk about
///       it and what they look up afterwards -- and the first version put the
///       name on screen for two and a half seconds at the start of an attack
///       that then ran for another forty. Three seconds in, nothing anywhere
///       said which spell was being survived.
///
///       **Where it goes has now been wrong twice and the reasons were good
///       both times.** It started at the bottom of the field, which on a
///       full-bleed playfield is *inside the player's working area*: the one
///       permanent piece of text in the game competing for the pixels being
///       read hardest. It moved to the console on the reasoning that forty
///       seconds of nameplate over the play area is not affordable where two
///       and a half seconds of banner is. In the console it was the width of
///       the column away from the health bar it refers to, three lines tall,
///       and it clipped off the bottom of the plate the moment a title ran
///       long.
///
///       It is under the bar now, and two things make that work which did not
///       hold before. The names are single -- "Cinder Waltz" rather than
///       "Ember Sign -- Cinder Waltz" -- so the plate is one short line rather
///       than three; and the top of the field is where the boss is and the
///       player is not, which is the same exception the bar itself is, on the
///       same terms: outlined text, one line, and nothing opaque.
///
///       It arrives *as the banner goes* -- `spell_a` only starts easing up
///       once `banner_t` has run out, because the same words in two places at
///       once reads as a bug rather than as ceremony.
function hud_draw_spell_name(_h, _boss, _p, _dy = 0, _alpha = 1) {
    if (_h.spell_a <= 0.02 || _boss == undefined || _p == undefined) return;

    var _a = _h.spell_a * _alpha;
    var _col = global.bullet_colour[_p.col];

    // **Under the cartouche, at the rail's left end.** It shared the caster's
    // row for a pass, which put its capitals across the bottom of the
    // cartouche -- reported as sitting too high and overlapping the meter,
    // which it was. `BOSS_SPELL_Y` is derived from the cartouche's own depth,
    // so it cannot be put back under it by a change to either.
    //
    // **Fitted rather than clipped**, so a long title shrinks and stays at the
    // rail's end rather than running out into the middle, which is the
    // boss's. The scale is worked out here rather than inside `draw_text_fit`
    // because centring by ink needs it: a shrunk line has a shorter cap height
    // and has to be set on its centre line at its own size.
    draw_set_font(fnt_ui());
    var _w = string_width(_p.name);
    var _s = (_w > BOSS_SPELL_W && _w > 0) ? (BOSS_SPELL_W / _w) : 1;
    draw_set_valign(fa_bottom);
    draw_set_halign(fa_left);
    draw_text_fit(FIELD_X0 + BOSS_BAR_INSET,
                  text_cap_middle_y(BOSS_SPELL_Y + _dy, _s), _p.name,
                  BOSS_SPELL_W, _col, _a, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc The pause menu.
///
///       **Centred on the field, not on the screen.** The scrim still covers
///       everything, because a pause is modal and a console that stayed bright
///       under it would read as still live -- but the *text* belongs over the
///       playfield. Centred on `GAME_CX` it lands two hundred and thirty
///       pixels to the right of where the player is looking and runs straight
///       across the console's readouts, which through a 68% scrim is two
///       layers of type in the same place. Every modal in this file makes the
///       same move for the same reason.
function hud_draw_pause(_g) {
    draw_scrim(0.68);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_CY - 170, "PAUSED", COL_SILVER, 1, 3);

    // **The middle row says what it restarts.** In an ordinary run that is the
    // stage; in attack practice it is one attack, and a menu offering to
    // restart a stage during a run that has no stage in it is a menu telling
    // the player something untrue about where they are.
    var _practice = (_g[$ "practice"] != undefined);
    var _rows = _practice ? ["RESUME", "RESTART ATTACK", "BACK TO ATTACKS"]
                          : ["RESUME", "RESTART STAGE", "ABANDON"];
    draw_set_font(fnt_head());
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _sel = (_g.pause_row == _i);
        draw_text_outline(FIELD_CX, FIELD_CY - 10 + _i * 78, _rows[_i],
                          _sel ? COL_GRAZE : COL_SILVER, _sel ? 1 : 0.6, 2);
    }
    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 76,
                      "ARROWS  CHOOSE      Z  CONFIRM      ESC  RESUME",
                      COL_SILVER, 0.55, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The end-of-stage screen -- win or lose, the same layout.
function hud_draw_result(_g) {
    var _won = (_g.phase == Phase.Won);
    var _t = min(1, _g.result_t / 40);
    draw_scrim(0.78 * _t);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_Y0 + 190,
                      _won ? "STAGE CLEAR" : "DEFEATED",
                      _won ? COL_GRAZE : COL_LIFE, _t, 3);

    // **The standing, which nothing used to draw.** Every mark carried a
    // label and a tier and the only readout was the row of sockets in the
    // console; the one page in the game with room to say what the attempt was
    // worth said nothing about it. It goes above the numbers rather than
    // among them because it is not one of them -- it is the answer the five
    // rows below are the working for.
    // **Clear of the title, which took a screenshot to see.** `fnt_title` is
    // 132px and the panel's headline is drawn from its middle, so it occupies
    // roughly sixty pixels either side of `FIELD_Y0 + 190` -- and the first
    // version put the tag at +232, which printed STANDING straight through
    // the bottom of STAGE CLEAR. It is the crest-through-the-stage-name
    // finding again, and nothing but a picture was going to report it: both
    // coordinates are inside the field and neither box overlaps a console
    // box, which is all `test_hud_layout` can ask.
    var _led = _g[$ "marks"];
    if (rank_count(_led) > 0) {
        draw_set_font(fnt_small());
        draw_text_tracked(FIELD_CX, FIELD_Y0 + 318, "STANDING", 10,
                          COL_SILVER, _t * 0.7, 2, fa_center);
        draw_set_halign(fa_center);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, FIELD_Y0 + 376, rank_overall_name(_led),
                          rank_overall_colour(_led), _t, 3);
    }

    var _boss = _g.boss_ref;
    var _caught = (_boss == undefined) ? 0 : _boss.boss.captured;

    var _rows = [
        ["SCORE", string(_g.tally)],
        ["GRAZE", string(_g.player.graze_n)],
        ["SPELLS CAPTURED", string(_caught)],
        ["TIMES HIT", string(_g.player.hit_n)],
        ["SIGILS SPENT", string(_g.player.bomb_n)],
    ];
    // **The label is smaller than the value, and that is what makes the block
    // fit.** Set in the same 66pt face, "SPELLS CAPTURED" is 640 pixels of
    // type either side of a centre line, which on a 1360-wide field lands its
    // first letter on the boundary. It is also the wrong hierarchy: the label
    // is the question and the number is the answer.
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _y = FIELD_Y0 + 476 + _i * 78;
        draw_set_halign(fa_right);
        draw_set_font(fnt_ui());
        draw_text_outline(FIELD_CX - 30, _y, _rows[_i][0], COL_SILVER,
                          _t * 0.8, 2);
        draw_set_halign(fa_left);
        draw_set_font(fnt_num());
        draw_text_outline(FIELD_CX + 30, _y, _rows[_i][1], c_white, _t, 2);
    }

    draw_set_halign(fa_center);
    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 76, "Z  CONTINUE", COL_GRAZE,
                      _t * (0.6 + 0.4 * dsin(_g.t * 4)), 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The count before a practised attack opens.
///
/// **The beat is the boss's own pause and this only says so.** Practice
/// arrives inside `clear_t` -- the invulnerable moment a fight already puts
/// between two attacks -- so nothing here creates a state; it reads one. What
/// it adds is the *count*, because a pause the player cannot see the end of is
/// indistinguishable from a game that has not started, and the whole point of
/// the beat is that they spend it deliberately: reading where the boss has
/// drifted to, and getting off the spawn point.
///
/// **No name and no title.** The spell's banner is two seconds away and will
/// say both at size; putting them here as well is the same words twice, which
/// is the rule the nameplate under the boss's bar is already built on.
function hud_draw_practice_ready(_boss) {
    var _left = _boss.boss.clear_t;
    if (_left <= 0) return;

    var _n = ceil(_left / FPS);
    // Where this second is up to: 1 on the tick, 0 at the next one.
    var _f = ((_left - 1) mod FPS) / FPS;
    // Snaps in on the tick and eases out across the second, growing as it
    // goes. A number that simply held for a second would read as a still
    // frame -- what says "this is a countdown" is that each one arrives.
    var _a = min(1, _f * 3.2);

    draw_set_valign(fa_middle);
    draw_set_font(fnt_small());
    draw_text_tracked(FIELD_CX, FIELD_CY - 78, "READY", 12, COL_GILT,
                      0.7, 2, fa_center);

    draw_set_halign(fa_center);
    draw_set_font(fnt_title());
    draw_text_outline_scaled(FIELD_CX, FIELD_CY + 16, string(_n),
                             COL_GILT_LIT, _a, 1 + (1 - _a) * 0.45, 3);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The end of a practice attempt: how it went, and three ways on.
///
/// **A stage's result screen has one key and this one has a menu, and the
/// difference is what the player is going to do next.** A stage that has just
/// ended has one obvious next move -- back to the rack -- so offering a choice
/// would be furniture. An attack that has just ended has one obvious next move
/// too and it is *the same attack again*: that is the entire reason to be
/// here, and putting it behind a trip through two screens would make the loop
/// this mode exists to shorten longer than the one it replaces.
///
/// **It reports the outcome in three words rather than two.** Broken, survived
/// and defeated are three different things in this genre and a panel that
/// folded the middle one into either of the others would be lying about the
/// rules the attack is played under -- a spell run down to its clock is not a
/// loss, it just pays nothing. See `practice_end_name`.
function hud_draw_practice_result(_g) {
    var _r = _g[$ "practice_result"];
    var _t = min(1, _g.result_t / 40);
    // **Darker than the stage's panel, because there is more to read on it.**
    // A stage result is five numbers and one key; this is a grade, two numbers
    // and a menu, and the field keeps running underneath -- shards from the
    // clear are bright gold and they were landing behind the menu rows.
    draw_scrim(0.84 * _t);

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    var _col = practice_end_colour(_r);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_Y0 + 200, practice_end_name(_r), _col,
                      _t, 3);

    // What was being practised, under the verdict rather than over it: the
    // player knows which attack they picked and does not know yet how it went.
    // Fitted, because a spell name is authored prose and the longest one in
    // the game is not the longest one that will ever exist.
    //
    // **Its caster is not repeated here.** The console beside the field is
    // already printing the boss and the stage under this same name, three
    // hundred pixels away, and a panel is not improved by saying what the
    // thing next to it is already saying -- it is improved by being short
    // enough that its menu is nowhere near the bottom of the field.
    draw_set_font(fnt_head());
    draw_text_fit(FIELD_CX, FIELD_Y0 + 292, string_upper(_g.def.name),
                  FIELD_W - 260, COL_PARCHMENT, _t, 2);

    // ---- the mark ---------------------------------------------------------
    //
    // **The same sprite the console draws, at three times the size.** The
    // ledger's row is a glance and this is the one moment the grade is the
    // subject, so it gets to be a thing on the page rather than a bead in a
    // row -- and it is the *same* thing, because a second way of drawing a
    // grade is a second grade as far as the eye is concerned.
    var _my = FIELD_Y0 + 396;
    if (_r != undefined && _r.tier >= 0) {
        var _mc = mark_colour(_r.tier);
        draw_bloom(FIELD_CX, _my, 260, _mc, _t * 0.3);
        draw_sprite_ext(spr_ui_mark, _r.spell ? 1 : 0, FIELD_CX, _my,
                        3, 3, 0, _mc, _t);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, _my + 82, mark_name(_r.tier), _mc, _t, 2);
    } else {
        // Dying leaves no mark, and saying so is better than printing the
        // bottom of the ladder: an attempt that ended before the attack did was
        // never graded, and SLAG would be a judgement nobody earned.
        draw_sprite_ext(spr_ui_mark, 2, FIELD_CX, _my, 3, 3, 0,
                        merge_colour(COL_GILT, COL_ARCANE, 0.4), _t * 0.8);
        draw_set_font(fnt_head());
        draw_text_outline(FIELD_CX, _my + 82, "UNMARKED",
                          merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.5),
                          _t * 0.8, 2);
    }

    // ---- what it cost -----------------------------------------------------
    //
    // **The two numbers a capture turns on, and nothing else.** The stage
    // panel lists five because a stage is five minutes of accumulation; an
    // attack is forty seconds, and the only two questions about one are
    // whether it touched you and whether you had to spend anything -- which
    // are exactly the two inputs `rank_for_attack` reads. The graze count and
    // the score are on the console, unmoved, three hundred pixels away.
    var _hits  = (_r == undefined) ? 0 : _r.hits;
    var _bombs = (_r == undefined) ? 0 : _r.bombs;
    var _rows = [["TIMES HIT", string(_hits)],
                 ["SIGILS SPENT", string(_bombs)]];
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _y = FIELD_Y0 + 560 + _i * 58;
        draw_set_halign(fa_right);
        draw_set_font(fnt_ui());
        draw_text_outline(FIELD_CX - 26, _y, _rows[_i][0], COL_SILVER,
                          _t * 0.8, 2);
        draw_set_halign(fa_left);
        draw_set_font(fnt_num());
        draw_text_outline(FIELD_CX + 26, _y, _rows[_i][1], c_white,
                          _t * 0.9, 2);
    }

    // ---- and the three ways on -------------------------------------------
    draw_set_halign(fa_center);
    draw_set_font(fnt_head());
    // **Three rows, and the bottom one has to clear the footer.** At the pitch
    // this started on the last row's descenders were sitting in the hint line
    // and the block ran to within fifty pixels of the field's own boundary --
    // which is the failure a screenshot catches and no assertion ever will,
    // since every one of these coordinates is inside the field and none of
    // them overlaps a console box.
    // **"BACK TO TITLE" rather than "QUIT TO TITLE", and the reason is the
    // Q.** The sprite fonts are spaced by ink and have no kerning, so Cinzel's
    // Q -- whose tail sweeps out to the right of its bowl -- takes an advance
    // wide enough to hold the tail and leaves a gap where the next letter
    // should tuck under it. At `fnt_ui` on the title screen that gap is a few
    // pixels and reads as nothing; at this size it reads as a word break, and
    // "Q UIT TO TITLE" is what the first screenshot of this panel came back
    // with. The general fix is kerning pairs in `make_fonts.py`; the specific
    // one is not putting a large Q in front of a narrow letter.
    var _menu = ["RETRY ATTACK", "CHOOSE ANOTHER", "BACK TO TITLE"];
    for (var _i = 0; _i < array_length(_menu); _i++) {
        var _sel = (_g.result_row == _i);
        draw_text_outline(FIELD_CX, FIELD_Y0 + 724 + _i * 68, _menu[_i],
                          _sel ? COL_GRAZE : COL_SILVER,
                          _t * (_sel ? 1 : 0.55), 2);
    }

    draw_set_font(fnt_ui());
    draw_text_outline(FIELD_CX, FIELD_Y1 - 72,
                      "ARROWS  CHOOSE      Z  CONFIRM",
                      merge_colour(COL_PARCHMENT, COL_GILT, 0.4), _t * 0.6, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
