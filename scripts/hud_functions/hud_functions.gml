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
        case "boss":
            return [FIELD_X0 + BOSS_BAR_INSET, BOSS_BAR_Y,
                    FIELD_X1 - BOSS_BAR_INSET, BOSS_SPELL_Y + BOSS_SPELL_ROW];
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
    var _want = (_boss == undefined) ? 1 : (_boss.hp / _boss.hp_max);
    _h.boss_slosh = max(_h.boss_slosh * 0.93,
                        min(1, abs(_want - _h.boss_shown) * 6));
    _h.boss_shown += (_want - _h.boss_shown) * 0.18;

    // A phase boundary crossed is the one event in a fight worth marking on
    // the bar itself, and the bar is the only thing that knows it happened --
    // the boss's own phase index is the fact, and comparing it here costs an
    // integer.
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

    // The boss's own line, over the field.
    //
    // **It goes when a practice attempt is over.** The phase index does not
    // move until `clear_t` runs out, so for a second and a half after the
    // attack has ended the line is still naming it and still counting its
    // clock down -- under a panel announcing the same attack in the past
    // tense. In a stage that is fine, because the boss is dead and the bar
    // says so; in practice the bar is describing a fight that is not over,
    // during a screen that says it is. The whole line goes rather than only
    // its name: what a bar spanning seven attacks has to say about the one
    // that was practised is nothing.
    var _over = (_g.phase == Phase.Won || _g.phase == Phase.Lost);
    var _practice = (_g[$ "practice"] != undefined);
    if (_boss != undefined && _boss.boss.started && !(_over && _practice)) {
        hud_boss_bar(_h, _boss);
    }

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
// ---------------------------------------------------------------------------

/// @desc The boss's name, health tube, timer and marks -- inside the field.
///
///       **One bar, with the thresholds notched on it.** Touhou refills a
///       boss's bar per attack, which is legible and says nothing about how
///       far through the fight you are. Here it only ever goes down and the
///       phase table's thresholds are cut into it, so a glance answers both
///       "how is this attack going" and "how much of this is left".
///
///       **The bar is pinned to the top of the field and the words hang off
///       it.** They were the other way round for a pass, with the name centred
///       above the tube and the timer beside it -- fifty-six pixels of type
///       between the top of the playfield and the one part of this line that
///       is read at a glance mid-dodge.
///
///       **And the name is at the bar's left-hand end, not over its middle.**
///       Centring it was right while the boss held station well below the
///       line: the caption owned the centre because nothing else was ever
///       there. Raising `BOSS_HOME_Y` takes that away -- the middle of the top
///       of the field is the boss's face now -- so the name goes back to the
///       left end and the timer to the right, which is where the genre has
///       always put them and which is what gives the boss the middle.
function hud_boss_bar(_h, _boss) {
    var _b = _boss.boss;
    var _x1 = FIELD_X0 + BOSS_BAR_INSET;
    var _x2 = FIELD_X1 - BOSS_BAR_INSET;
    var _w = _x2 - _x1;
    var _y = BOSS_BAR_Y;

    var _p = boss_phase(_boss);
    var _col = (_p == undefined) ? COL_LIFE : global.bullet_colour[_p.col];

    // The name, under the bar's left-hand end and tracked, which is what lets
    // it be small and still read as a title.
    draw_set_font(fnt_ui());
    draw_set_valign(fa_top);
    draw_text_tracked(_x1, BOSS_NAME_Y, string_upper(_b.def.name), 9,
                      merge_colour(COL_GILT_LIT, _col, 0.3), 0.95, 3,
                      fa_left);

    // **The marks are in the console and not here.** Touhou draws its
    // remaining-attack stars in the playfield beside the bar, and the first
    // pass of this line copied that; what it produced was a row of small
    // coloured shapes over live scenery a few pixels above a bar that already
    // carries the same information as notches. Two readouts of one fact, one
    // of them occluding, when the console beside the field has a whole row for
    // them and the room to draw them at a size that reads. See
    // `hud_draw_attacks`.

    // The timer on the current attack, if it has one, at the other end.
    var _secs = boss_time_left(_boss);
    if (_secs >= 0) {
        var _urgent = (_secs < 8);
        draw_set_font(fnt_num());
        draw_set_halign(fa_right);
        draw_text_outline(_x2, BOSS_NAME_Y - 12, string(floor(_secs)),
                          _urgent ? merge_colour(COL_LIFE, c_white,
                                                 0.4 + 0.4 * dsin(current_time * 0.4))
                                  : COL_GILT_LIT,
                          _urgent ? 1 : 0.9, 3);
        draw_set_halign(fa_left);
    }

    draw_gauge_h(_x1, _y, _w, BOSS_BAR_H, _h.boss_shown, _col, 1, {
        slosh: _h.boss_slosh,
        glow: _h.boss_flare,
        seed: 29,
    });

    // The notches. Drawn from the table, so they cannot disagree with where
    // the attacks actually end.
    for (var _i = 0; _i < array_length(_b.phases); _i++) {
        var _f = _b.phases[_i].hp_end;
        if (_f <= 0.001) continue;
        var _nx = _x1 + _w * _f;
        // A spell's boundary is marked taller than a non-spell's, so the shape
        // of the fight -- where the named attacks are -- is legible on the bar
        // before any of them has been reached.
        var _tall = (_b.phases[_i].kind == AttackKind.Spell) ? 9 : 4;
        // **Dark where it crosses the liquid, pale where it crosses the empty
        // glass.** One colour cannot do both: a dark notch on the unfilled half
        // of the tube is a dark mark on a near-black trough and simply is not
        // there -- and that is the half of the bar saying how much of the fight
        // is left, which is the whole reason the notches exist.
        var _on_liquid = (_f <= _h.boss_shown + 0.001);
        draw_set_colour(_on_liquid ? COL_VOID : COL_GILT);
        draw_set_alpha(0.9);
        draw_rectangle(_nx - 1, _y - _tall, _nx + 1, _y + BOSS_BAR_H + _tall,
                       false);
    }

    // The spell's name, under the bar. Drawn from here rather than from
    // `hud_draw` because it is part of the boss's line and shares its
    // geometry -- see `hud_draw_spell_name`.
    if (_p != undefined && _p.kind == AttackKind.Spell) {
        hud_draw_spell_name(_h, _boss, _p);
    }

    // A phase broken: a flash travelling out from the threshold that was just
    // crossed. It is the one moment in a fight the bar is the thing that
    // happened, and it lasts about half a second.
    if (_h.boss_flare > 0.02) {
        draw_bloom(_x1 + _w * _h.boss_shown, _y + BOSS_BAR_H * 0.5,
                   340 * (1.2 - _h.boss_flare), _col, _h.boss_flare * 0.5);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
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
///       boss's own bar, inside the field.
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
function hud_draw_spell_name(_h, _boss, _p) {
    if (_h.spell_a <= 0.02 || _boss == undefined || _p == undefined) return;

    var _a = _h.spell_a;
    var _col = global.bullet_colour[_p.col];

    // **Stacked under the caster's name, at the same left margin.** It was
    // centred while the boss stood clear below this line; the boss is up here
    // now and the middle of the line is its face. The two names together are
    // one block -- who is casting, and what -- which is how they are read.
    draw_set_valign(fa_top);
    draw_set_halign(fa_left);
    draw_set_font(fnt_ui());
    draw_text_fit(FIELD_X0 + BOSS_BAR_INSET, BOSS_SPELL_Y, _p.name,
                  FIELD_W * 0.42, _col, _a, 3);

    // **Whether the capture is still live, at the other end of the line.**
    // It is the one fact about the attempt still in play, and a player who has
    // been hit has nothing left to protect -- they should be told at the time
    // rather than finding out on the result screen. It goes at the far end
    // rather than beside the name so that losing it does not shift the name,
    // which would read as the spell having changed.
    var _clean = (_boss.boss.hits_this_phase == 0
                  && _boss.boss.bombs_this_phase == 0);
    if (_clean) {
        draw_set_font(fnt_small());
        draw_text_tracked(FIELD_X1 - BOSS_BAR_INSET, BOSS_SPELL_Y + 8,
                          "CAPTURE LIVE", 5, COL_GRAZE, _a * 0.9, 2,
                          fa_right);
    }

    draw_set_halign(fa_left);
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
