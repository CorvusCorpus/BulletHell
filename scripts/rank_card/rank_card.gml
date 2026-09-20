/// @desc The rank card: the medal a finished encounter throws on the screen.
///
/// **A mark used to land in the console with a flare on it and nothing else
/// happened.** What a character-action game does at the end of a set piece is
/// put the medal on the screen, at size, for about a second -- and the reason
/// is not celebration, it is that a grade nobody notices is a grade nobody
/// plays for. The console's row is the *record*; this is the moment.
///
/// **It is additive, without exception, and that is a fairness rule rather
/// than a look.** The window it lands in is far tighter than it appears:
///
/// | | |
/// |---|---|
/// | `BOSS_PHASE_PAUSE` | 84 frames, and that is the *entire* clear window |
/// | a spell's `BOSS_SPELL_LEAD` | 90 more, but the eye card owns the middle of the field for all of them |
/// | a non-spell | the next pattern opens the frame the pause ends |
/// | a wave gate | half a second of grace, then whatever the timeline says |
///
/// So there is no timing at which the card can be promised clear air, and the
/// rule `grove_draw_front` keeps is the only guarantee that survives all four
/// of them: light can only ever brighten what is behind it, so no arrangement
/// of this can hide a bullet at any size, at any alpha, at any moment. What is
/// given up is a solid plate behind the medal, and that is not a loss worth
/// arguing about -- see `RANK_CARD_Y` for the one thing it did cost.
///
/// **Four beats, and the last one is the point.** The medal strikes, settles
/// under a travelling glint, holds while its numbers are read, and then
/// **flies to its own socket in the console** and fills it. That last beat is
/// what makes the card and the ledger one object rather than two readouts of
/// the same fact -- the same move the special already makes when the motes it
/// steals accelerate into the sigil's heart. `hud_mark_xy` is the shared
/// answer for where the socket is, because a card that flew to a socket the
/// row drew somewhere else would be two pieces of arithmetic drifting apart.

/// @desc An idle card. One per run, held on the console.
function rank_card_new() {
    return {
        t: -1,              // -1 is idle; nothing else reads as "no card"
        tier: 0,
        label: "",
        spell: false,
        earned: 0,
        target: 0,
        hits: 0,
        bombs: 0,
        slot: 0,            // which socket it flies home to
        total: 1,
        seen: 0,            // marks the console has already thrown a card for
    };
}

/// @desc Throw the card for a mark that has just been filed.
///
///       **Called by the console watching the ledger, not by `rank_note`.**
///       That split is the one `rank_functions` already keeps for the flare:
///       the ledger is a record and how loudly it is drawn is the console's
///       business, which is why nothing in the engine has to remember there
///       is a screen. It is also what lets the suites file two hundred marks
///       without animating any of them.
function rank_card_show(_c, _mark, _slot, _total) {
    _c.t = 0;
    _c.tier = _mark.tier;
    _c.label = _mark.label;
    _c.spell = _mark.spell;
    _c.earned = _mark[$ "earned"] ?? 0;
    _c.target = _mark[$ "target"] ?? 0;
    _c.hits = _mark[$ "hits"] ?? 0;
    _c.bombs = _mark[$ "bombs"] ?? 0;
    _c.slot = _slot;
    _c.total = max(1, _total);

    // **The top two rungs are the only ones you feel.** A shake on every
    // encounter is a shake the player stops reading, and this game already
    // spends its shake budget on being hit -- which is a thing that must not
    // be imitated by good news. See `player_step`.
    if (_mark.tier >= Mark.Amethyst) fx_shake(10);
    // **The cue is the break, plus the capture over it for the top two.**
    // Two more synthesised WAVs is two more things to replace when the set
    // is recorded, and what the card needs said -- "an encounter ended, and
    // this one went well" -- is exactly what those two already say. The
    // capture cue is drawn thin and high precisely so it can sound over
    // another one, which is the property being used here.
    sfx(Sfx.SpellBreak);
    if (_mark.tier >= Mark.Gold) sfx(Sfx.Capture);
}

/// @desc Advance it. Idle is free.
function rank_card_step(_c) {
    if (_c.t < 0) return;
    _c.t++;
    if (_c.t >= RANK_CARD_TIME) _c.t = -1;
}

/// @desc Is one on screen?
function rank_card_live(_c) {
    return _c.t >= 0;
}

/// @desc Where the medal is this frame, and how big, as `[x, y, scale]`.
///
///       **The flight is the fourth beat and it is eased into, not switched
///       to.** A medal that held still and then jumped onto a path reads as
///       two animations; one whose scale and position are a single function
///       of `t` reads as one object doing one thing. So the home position is
///       blended in over `RANK_CARD_FLY`, and the *size* it arrives at is the
///       socket's size rather than the medal's -- it becomes the mark.
function rank_card_where(_c) {
    var _t = _c.t;

    // Beat one: it arrives oversized and settles. An overshoot rather than a
    // ramp, because a thing that arrives at exactly its final size has not
    // been struck, it has been faded in.
    var _s = 1.0;
    if (_t < RANK_CARD_STRIKE) {
        var _f = _t / RANK_CARD_STRIKE;
        _s = 1.62 - 0.62 * _f * _f;
    } else if (_t < RANK_CARD_SETTLE) {
        // A small elastic settle under it, which is what sells the weight.
        var _f = (_t - RANK_CARD_STRIKE) / (RANK_CARD_SETTLE - RANK_CARD_STRIKE);
        _s = 1.0 + 0.055 * dcos(_f * 540) * (1 - _f);
    }

    var _x = FIELD_CX;
    var _y = RANK_CARD_Y;

    // **Over `RANK_CARD_FLY - 1`, and the fencepost is visible.** The last
    // frame the card is alive for is `RANK_CARD_TIME - 1`, so dividing by
    // the flight's length leaves the fraction at 23/24 -- and cubed, that is
    // an ease of 0.88. The medal disappeared an eighth of the way short of
    // the socket it was supposed to be filling, every time, which is the
    // whole point of the beat missed by one frame. It reads as *nearly*
    // right, which is why `test_rank_card` measures the landing rather than
    // trusting the path.
    var _fly = _t - (RANK_CARD_TIME - RANK_CARD_FLY);
    if (_fly > 0) {
        var _f = clamp(_fly / max(1, RANK_CARD_FLY - 1), 0, 1);
        // Slow out of the field and fast into the socket, so the eye is
        // handed the medal before it is asked to follow it.
        var _e = _f * _f * _f;
        var _home = hud_mark_xy(_c.slot, _c.total);
        _x = lerp(_x, _home[0], _e);
        _y = lerp(_y, _home[1], _e);
        _s = lerp(_s, RANK_CARD_HOME_S, _e);
    }
    return [_x, _y, _s];
}

/// @desc How solid the card is: 0 through the flight's end, 1 in the middle.
function rank_card_alpha(_c) {
    var _t = _c.t;
    if (_t < 3) return _t / 3;
    var _fly = _t - (RANK_CARD_TIME - RANK_CARD_FLY);
    if (_fly > 0) return 1 - clamp(_fly / max(1, RANK_CARD_FLY - 1), 0, 1) * 0.55;
    return 1;
}

/// @desc Draw it. **Everything here is additive** -- see the note at the top.
function rank_card_draw(_c) {
    if (_c.t < 0) return;

    var _w = rank_card_where(_c);
    var _x = _w[0], _y = _w[1], _s = _w[2];
    var _a = rank_card_alpha(_c);
    var _col = mark_colour(_c.tier);

    gpu_set_blendmode(bm_add);

    // Beat one: the strike. A flash at the medal and a shockwave leaving it,
    // both gone within a fifth of a second -- long enough to say something
    // landed and too short to be in the way of anything.
    // **Small, because additive is not the same as free.** The first pass
    // put a 620-pixel bloom at 55% over the medal, and photographed at frame
    // two the whole field was milky: added light cannot hide a bullet, which
    // is the rule this file is built on, and it can still take most of the
    // contrast out of the thing the bullet is being read against. The strike
    // has to be felt at the medal and not across the playfield.
    if (_c.t < RANK_CARD_STRIKE * 3) {
        var _f = _c.t / (RANK_CARD_STRIKE * 3);
        draw_bloom(_x, _y, 380 * (0.5 + _f), _col, (1 - _f) * 0.30 * _a);
        var _rr = 90 + 420 * _f;
        draw_sprite_ext(spr_fx_ring, 0, _x, _y,
                        _rr / sprite_get_width(spr_fx_ring) * 2,
                        _rr / sprite_get_width(spr_fx_ring) * 2, 0,
                        _col, (1 - _f) * 0.55 * _a);
    }

    // The medal's own light, under it, so it sits in a glow rather than on
    // the scenery. It is the only thing here that survives the flight.
    draw_bloom(_x, _y, 300 * _s, _col, 0.30 * _a);

    var _sc = _s * RANK_CARD_SCALE;
    var _frame = min(_c.tier, RANK_CARD_FRAMES - 1);
    draw_sprite_ext(spr_ui_medal, _frame, _x, _y, _sc, _sc, 0, _col, _a);
    // A second pass on the lit structure only, which is what stops an
    // additive medal reading as a flat coloured disc: the bevel and the
    // facets are already the brightest alpha in the sprite, so adding it to
    // itself widens the distance between the faces rather than the whole.
    draw_sprite_ext(spr_ui_medal, _frame, _x, _y, _sc, _sc, 0,
                    merge_colour(_col, c_white, 0.55), _a * 0.55);

    // Beat two: the glint. A four-pointed spark crossing the face, which is
    // the house's own motif doing the job a sheen would -- and a sheen is a
    // band clipped to a silhouette, which without a shader is a band that
    // runs off the edge of the thing it is polishing.
    if (_c.t >= RANK_CARD_STRIKE && _c.t < RANK_CARD_GLINT_END) {
        var _f = (_c.t - RANK_CARD_STRIKE)
                 / (RANK_CARD_GLINT_END - RANK_CARD_STRIKE);
        var _r = 92 * _s;
        var _gx = _x + lerp(-_r, _r, _f);
        var _gy = _y + lerp(_r, -_r, _f) * 0.55;
        var _ga = dsin(_f * 180) * 0.9 * _a;
        var _gs = (0.30 + 0.22 * dsin(_f * 180)) * _s;
        draw_sprite_ext(spr_fx_spark, 0, _gx, _gy, _gs, _gs, 45,
                        c_white, _ga);
        draw_bloom(_gx, _gy, 150 * _s, c_white, _ga * 0.35);
    }

    gpu_set_blendmode(bm_normal);

    // ---- the words, which are ordinary outlined text ---------------------
    //
    // **Not additive, and that is not an exception to the rule above.** The
    // rule is about things that could hide a bullet; a line of outlined type
    // is what the spell banner and the boss's own name already are, and this
    // file's whole argument is that the *medal* is the big opaque thing.
    // Text is also the one element that has to stay legible over a lit
    // background, which added light cannot do.
    if (_c.t < RANK_CARD_TIME - RANK_CARD_FLY) {
        var _ta = clamp((_c.t - RANK_CARD_STRIKE) / 10, 0, 1)
                  * clamp((RANK_CARD_TIME - RANK_CARD_FLY - _c.t) / 8, 0, 1);
        // **Clear of the rim, which took a screenshot.** The medal is 176
        // authored and drawn at RANK_CARD_SCALE, so its lower edge is a
        // hundred-odd pixels down and a title at 128 printed itself across
        // the bottom of the very object it was naming.
        var _ty = _y + 158 * _s;

        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_font(fnt_head());
        draw_text_outline(_x, _ty, rank_card_title(_c),
                          merge_colour(_col, c_white, 0.25), _ta, 3);

        // What earned it, which is the half a medal cannot say. The target is
        // printed beside the score rather than instead of it, because "you
        // scored 18420" answers nothing on its own and "18420 of 15000" is
        // the whole of why the mark came out where it did.
        draw_set_font(fnt_small());
        var _met = (_c.earned >= _c.target);
        draw_text_tracked(_x, _ty + 52,
                          string(round(_c.earned)) + "  /  "
                          + string(round(_c.target)), 4,
                          _met ? COL_GRAZE : COL_SILVER, _ta * 0.92, 2,
                          fa_center);
        draw_text_tracked(_x, _ty + 90, rank_card_cost(_c), 6,
                          (_c.hits + _c.bombs > 0) ? COL_LIFE : COL_SILVER,
                          _ta * 0.8, 2, fa_center);

        // The encounter's own name, small and above the medal, so the player
        // knows which thing was graded. Above rather than below because the
        // block under the medal is already three lines deep, and because the
        // question "what is this a grade for" is asked before the grade is
        // read rather than after it.
        draw_text_tracked(_x, _y - 132 * _s, _c.label, 8, COL_PARCHMENT,
                          _ta * 0.75, 2, fa_center);

        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The word under the medal. **`ABSOLUTE AMETHYST` never appears here**
///       -- that is a fact about a whole stage and this is one encounter, and
///       printing it on a single wave would be promising a standing the run
///       has not earned yet.
function rank_card_title(_c) {
    return mark_name(_c.tier);
}

/// @desc What it cost, in words rather than in a table.
///
///       **"FLAWLESS" rather than "0 HITS  0 SIGILS".** Two zeroes is the
///       same information and it reads as a form with nothing filled in; the
///       one outcome the whole ladder is built around deserves to be said
///       rather than left as an absence.
function rank_card_cost(_c) {
    if (_c.hits <= 0 && _c.bombs <= 0) return "FLAWLESS";
    var _s = "";
    if (_c.hits > 0) {
        _s += string(_c.hits) + ((_c.hits == 1) ? " HIT" : " HITS");
    }
    if (_c.bombs > 0) {
        if (_s != "") _s += "     ";
        _s += string(_c.bombs) + ((_c.bombs == 1) ? " SIGIL" : " SIGILS");
    }
    return _s;
}
