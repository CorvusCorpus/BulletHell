/// @desc A conversation: Szuix and a boss talking before they fight.
///
/// A boss with something to say names a script in its def (`talk`, a function
/// returning the lines, and `portrait`, its standing portrait). `wave_boss`
/// starts it as the boss arrives (`talk_begin`). The boss waits above the
/// field, out of sight, until its name card, comes down as the card's name
/// lands, and holds its station until the conversation is over
/// (`boss.talking`). Practising a whole fight
/// plays it too, since the boss arrives the same way; practising one attack
/// doesn't, since the boss is put straight on it.
///
/// A script is a list of `talk_say(who, text)` lines and one `talk_card()`,
/// the beat on which the boss is named (`name_card`): its theme starts there
/// and its rail comes down. A script with no card still ends in one, played
/// by the boss's own declaration.
///
/// What is on screen, in the spell cut-in's terms (`spell_cutin`):
///
/// - The field is veiled. Szuix stands on the left and the boss on the
///   right, each a standing portrait (`tools/make_portraits.py`) cut off by
///   the field's edge. Whoever is speaking is lit, rimmed in their own
///   colour and stood forward; the other is dimmed and stood back. A
///   portrait arrives with a cut of light, hops as its line starts,
///   breathes, and blinks. The boss is a silhouette until its name card
///   names it, and comes out of it as the name lands.
/// - Behind each is a blade: a band of their colour at the cut-in's tilt,
///   run in from their side of the field, long while they speak and short
///   while they listen.
/// - The words are typed onto a plate of the cut-in's glass along the foot
///   of the field (one gilt rule along each edge, the title card's crescent
///   set into the top one), with the speaker's name on a tab standing on
///   their end of it. A boss not yet named is `? ? ?`.
///
/// Z shows the rest of a line, then turns to the next; held, it hurries. X
/// skips to the name card and then to the fight. The player holds still
/// while it is had (`obj_game`'s Step).
///
/// Lines are set in a sprite font of ASCII 32 to 126, so a script may use
/// nothing else (`test_talk` reads every script for it).

enum TalkWho {
    Player,
    Boss,
}

enum TalkKind {
    Say,
    Card,
}

// Frames.
#macro TALK_OPEN_TIME 22           // the veil comes down before the first line
#macro TALK_CLOSE_TIME 30          // everything leaving
#macro TALK_ENTER_TIME 26          // a portrait arriving
#macro TALK_FOCUS_TIME 14          // a speaker stepping forward, or back
#macro TALK_PLATE_TIME 12          // the plate opening, or closing
#macro TALK_CARD_HOLD 170          // an undismissed name card lets itself go
#macro TALK_HOLD_REPEAT 26         // Z held this long starts to hurry

// From the conversation ending to the boss's first attack opening.
#macro TALK_HANDOVER 60

// Frames a line rests after a comma, and after a full stop.
#macro TALK_PAUSE_SHORT 5
#macro TALK_PAUSE_LONG 11

// Where the speakers stand: the point midway between a portrait's eyes.
#macro TALK_PLAYER_X (FIELD_X0 + 300)
#macro TALK_BOSS_X (FIELD_X1 - 440)
#macro TALK_EYE_Y (FIELD_Y0 + 290)

// What a listener is dimmed toward.
#macro TALK_DIM make_colour_rgb(58, 52, 104)
// What a boss not yet named is shown as: a silhouette. It comes out of it
// over this many frames as its name lands.
#macro TALK_SHADOW make_colour_rgb(14, 10, 28)
#macro TALK_REVEAL_TIME 12

// A blade: its height, and how far past its speaker it runs toward the
// middle while they listen and while they speak. It fades out over the last
// `TALK_BLADE_FADE` of that.
#macro TALK_BLADE_H 400
#macro TALK_BLADE_SHORT 250
#macro TALK_BLADE_LONG 640
#macro TALK_BLADE_FADE 330

// The plate: centred on the field's middle column, this far up from its
// foot. Its ends lean as the cut-in's do (`CUTIN_PLATE_LEAN`).
#macro TALK_PLATE_W 1190
#macro TALK_PLATE_H 196
#macro TALK_PLATE_Y (FIELD_Y1 - 34 - TALK_PLATE_H * 0.5)

// The words: the width they are wrapped to, the most rows the plate holds,
// and the rows' pitch.
#macro TALK_TEXT_W 1010
// The bar of the speaker's colour down their end of the plate, and of their
// tab.
#macro TALK_BAR_W 14
#macro TALK_ROWS 3
#macro TALK_ROW_H 50

// The name tab, standing on the plate's top edge at the speaker's end: its
// height, the room either side of the name, and the scale `fnt_spell` is set
// at on it.
#macro TALK_TAB_H 60
#macro TALK_TAB_PAD 58
#macro TALK_TAB_S 0.52

// Where the name card's name is centred while a conversation is round it,
// and the width its writing is kept to: left of the middle, clear of the
// boss's portrait.
#macro TALK_CARD_X (FIELD_X0 + FIELD_W * 0.31)
#macro TALK_CARD_ROOM 610

// ---------------------------------------------------------------------------
// Scripts
// ---------------------------------------------------------------------------

/// @desc One line. `_face` picks the portrait's pose: a portrait holds its
///       poses in pairs of frames, as drawn then with the eyes shut.
function talk_say(_who, _text, _face = 0) {
    return { kind: TalkKind.Say, who: _who, text: _text, face: _face };
}

/// @desc The beat on which the boss is named.
function talk_card() {
    return { kind: TalkKind.Card, who: TalkWho.Boss, text: "", face: 0 };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// @desc An idle conversation. One per run.
function talk_new() {
    return {
        live: false,
        script: [],
        i: -1,                  // the entry being played; -1 while it opens
        t: 0,                   // frames since it began
        out_t: -1,              // frames since it began to leave; -1 until then
        line_t: 0,              // frames on this entry

        // This line: its words wrapped into rows, how many characters that
        // is, how many are shown, and the frames it is resting for.
        rows: [],
        n: 0,
        shown: 0,
        wait: 0,
        rest: 0,                // frames since its last character came

        speaker: -1,            // a `TalkWho`, or -1 for nobody
        said: TalkWho.Player,   // ...and whoever spoke last
        plate: 0,               // how far open the plate is, as a clock

        // The keys. Z does nothing until it has been let go once (the
        // player arrives holding it).
        armed: false,
        hold: 0,
        skip: false,

        cast: [talk_cast_new(-1, undefined, "", c_white),
               talk_cast_new(1, undefined, "", c_white)],
    };
}

/// @desc One speaker: which side they stand on, their portrait, name and
///       colour, and their clocks. A portrait brings its own colour
///       (`talk_art`); `_col` is for a speaker without one.
function talk_cast_new(_side, _spr, _name, _col) {
    if (_spr != undefined) {
        var _tint = talk_art(_spr).tint;
        if (_tint >= 0) _col = _tint;
    }
    return {
        side: _side,
        spr: _spr,
        name: _name,
        col: _col,
        x: (_side < 0) ? TALK_PLAYER_X : TALK_BOSS_X,
        y: TALK_EYE_Y,
        on: false,              // has arrived
        t: 0,                   // frames since arriving
        say_t: 0,               // frames since their line started
        focus: 0,               // how far forward they stand, as a clock
        tab: 0,                 // ...and how far out their name tab is
        face: 0,
    };
}

/// @desc Is a conversation on screen?
function talk_live(_t) {
    return _t != undefined && _t.live;
}

/// @desc Is it still being had (and so holding the keys)? Not once it has
///       begun to leave.
function talk_busy(_t) {
    return _t != undefined && _t.live && _t.out_t < 0;
}

/// @desc Start the conversation the boss `_e` arrives with, if it has one.
///       The boss waits for it, and its theme is held back for its name
///       card. Returns whether one started.
function talk_begin(_g, _e) {
    if (_e == undefined) return false;
    var _t = _g[$ "talk"];
    var _def = _e.boss.def;
    var _make = _def[$ "talk"];
    if (_t == undefined || _make == undefined) return false;

    _t.live = true;
    _t.script = _make();
    _t.i = -1;
    _t.t = 0;
    _t.out_t = -1;
    _t.line_t = 0;
    _t.rows = [];
    _t.n = 0;
    _t.shown = 0;
    _t.wait = 0;
    _t.rest = 0;
    _t.speaker = -1;
    _t.said = TalkWho.Player;
    _t.plate = 0;
    _t.armed = false;
    _t.hold = 0;
    _t.skip = false;
    _t.cast = [
        talk_cast_new(-1, spr_talk_szuix, "SZUIX", COL_SZUIX_LIT),
        talk_cast_new(1, _def[$ "portrait"], string_upper(_def.name),
                      global.bullet_colour[_def.col]),
    ];

    _e.boss.talking = true;
    music_keep();
    return true;
}

/// @desc The text `_str` broken into rows no wider than `_w` in the current
///       font.
function talk_wrap(_str, _w) {
    var _words = string_split(_str, " ", true);
    var _rows = [];
    var _cur = "";
    for (var _i = 0; _i < array_length(_words); _i++) {
        var _try = (_cur == "") ? _words[_i] : (_cur + " " + _words[_i]);
        if (_cur != "" && string_width(_try) > _w) {
            array_push(_rows, _cur);
            _cur = _words[_i];
        } else {
            _cur = _try;
        }
    }
    if (_cur != "") array_push(_rows, _cur);
    return _rows;
}

/// @desc Character `_k` (from 1) of the line being shown, counted across
///       its rows.
function talk_char(_t, _k) {
    for (var _r = 0; _r < array_length(_t.rows); _r++) {
        var _len = string_length(_t.rows[_r]);
        if (_k <= _len) return string_char_at(_t.rows[_r], _k);
        _k -= _len;
    }
    return "";
}

// ---------------------------------------------------------------------------
// Running it
// ---------------------------------------------------------------------------

/// @desc One frame of the conversation, with this frame's input.
function talk_step(_t, _g, _in) {
    if (!_t.live) return;
    _t.t++;

    // Whoever speaks steps forward and their tab comes out; the plate is
    // open on a line and shut through the name card.
    for (var _i = 0; _i < 2; _i++) {
        var _c = _t.cast[_i];
        if (!_c.on) continue;
        _c.t++;
        _c.say_t++;
        var _up = (_t.speaker == _i && _t.out_t < 0);
        _c.focus = clamp(_c.focus + (_up ? 1 : -1) / TALK_FOCUS_TIME, 0, 1);
    }
    var _line = (_t.out_t < 0 && _t.i >= 0
                 && _t.script[_t.i].kind == TalkKind.Say);
    _t.plate = clamp(_t.plate + (_line ? 1 : -1) / TALK_PLATE_TIME, 0, 1);
    for (var _i = 0; _i < 2; _i++) {
        var _c = _t.cast[_i];
        var _out = (_line && _t.speaker == _i);
        _c.tab = clamp(_c.tab + (_out ? 1 : -1) / TALK_PLATE_TIME, 0, 1);
    }

    if (_t.out_t >= 0) {
        _t.out_t++;
        if (_t.out_t >= TALK_CLOSE_TIME) _t.live = false;
        return;
    }

    // The keys: a press of Z, or one every few frames while it is held.
    var _next = false;
    if (!_in.shoot) {
        _t.armed = true;
        _t.hold = 0;
    } else if (_t.armed) {
        _t.hold++;
        _next = (_t.hold == 1)
                || (_t.hold > TALK_HOLD_REPEAT && (_t.hold mod 4) == 0);
    }
    if (_in.bomb) _t.skip = true;

    if (_t.i < 0) {
        if (_t.t >= TALK_OPEN_TIME || _t.skip) talk_advance(_t, _g);
        return;
    }

    _t.line_t++;
    var _boss = _g[$ "boss_ref"];

    // The name card: let go by a key, or by itself in the end. The next line
    // starts once the band has shut, with the name still on its way up.
    if (_t.script[_t.i].kind == TalkKind.Card) {
        if (_boss == undefined || _boss.boss.card_t < 0
            || _boss.boss.card_out >= NAMECARD_FLY_AT + 8) {
            talk_advance(_t, _g);
            return;
        }
        if (_next || _t.skip || _t.line_t >= TALK_CARD_HOLD) {
            boss_namecard_release(_boss.boss);
        }
        return;
    }

    if (_t.skip) {
        talk_skip(_t, _g);
        return;
    }

    // The words come a character a frame once the plate is open, resting at
    // punctuation.
    _t.rest++;
    if (_t.shown < _t.n && _t.plate >= 0.7) {
        if (_t.wait > 0) {
            _t.wait--;
        } else {
            _t.shown++;
            _t.rest = 0;
            if (_t.shown < _t.n) {
                var _ch = talk_char(_t, _t.shown);
                if (_ch == "," || _ch == ";" || _ch == ":") {
                    _t.wait = TALK_PAUSE_SHORT;
                } else if (_ch == "." || _ch == "!" || _ch == "?") {
                    _t.wait = TALK_PAUSE_LONG;
                }
            }
        }
    }

    if (_next) {
        if (_t.shown < _t.n) {
            _t.shown = _t.n;
            _t.wait = 0;
        } else {
            talk_advance(_t, _g);
        }
    }
}

/// @desc Turn to the next entry, or end.
function talk_advance(_t, _g) {
    _t.i++;
    if (_t.i >= array_length(_t.script)) {
        talk_close(_t, _g);
        return;
    }

    var _e = _t.script[_t.i];
    var _c = _t.cast[_e.who];
    _t.line_t = 0;
    _t.speaker = _e.who;
    _t.said = _e.who;
    if (!_c.on) {
        _c.on = true;
        _c.t = 0;
        sfx(Sfx.TalkEnter);
    }
    _c.say_t = 0;
    _c.face = _e.face;

    _t.rows = [];
    _t.n = 0;
    _t.shown = 0;
    _t.wait = 0;
    _t.rest = 0;

    if (_e.kind == TalkKind.Card) {
        var _boss = _g[$ "boss_ref"];
        if (_boss != undefined) boss_namecard_start(_boss.boss);
        return;
    }

    draw_set_font(fnt_talk());
    _t.rows = talk_wrap(_e.text, TALK_TEXT_W);
    for (var _r = 0; _r < array_length(_t.rows); _r++) {
        _t.n += string_length(_t.rows[_r]);
    }
    if (_t.i > 0) sfx(Sfx.TalkNext);
}

/// @desc X: on to the name card if it is still to come, and otherwise out.
function talk_skip(_t, _g) {
    var _boss = _g[$ "boss_ref"];
    if (_boss != undefined && _boss.boss.card_due) {
        for (var _j = _t.i + 1; _j < array_length(_t.script); _j++) {
            if (_t.script[_j].kind == TalkKind.Card) {
                _t.i = _j - 1;
                talk_advance(_t, _g);
                return;
            }
        }
    }
    talk_close(_t, _g);
}

/// @desc End it: everything leaves, and the boss is let go. A boss that has
///       had its name card goes to its first attack after `TALK_HANDOVER`;
///       one that has not is declared in the usual way first.
function talk_close(_t, _g) {
    _t.out_t = 0;
    _t.speaker = -1;
    var _boss = _g[$ "boss_ref"];
    if (_boss == undefined) return;
    var _b = _boss.boss;
    _b.talking = false;
    if (!_b.card_due) _b.declare_t = min(_b.declare_t, TALK_HANDOVER);
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw the conversation (GUI layer, after the field's frame), and the
///       boss's name card with it when that is playing.
function talk_draw(_t, _g) {
    if (!_t.live) return;
    var _boss = _g[$ "boss_ref"];
    var _card = namecard_live(_boss);

    // How much of it is there: arriving, and leaving.
    var _here = card_ramp(_t.t, 0, TALK_OPEN_TIME);
    if (_t.out_t >= 0) _here *= 1 - cutin_smooth(_t.out_t, 4, 24);

    talk_draw_veil(_here);

    // Back to front: the listener and their blade, the name card's band,
    // then the speaker.
    var _front = (_t.speaker == TalkWho.Player) ? TalkWho.Player
                                                : TalkWho.Boss;
    var _back = (_front == TalkWho.Player) ? TalkWho.Boss : TalkWho.Player;
    talk_draw_blade(_t, _t.cast[_back]);
    talk_draw_blade(_t, _t.cast[_front]);
    var _shade = talk_shadowed(_boss);
    talk_draw_portrait(_t, _t.cast[_back], undefined,
                       (_back == TalkWho.Boss) ? _shade : 0);

    var _col = _t.cast[TalkWho.Boss].col;
    var _cg = undefined;
    if (_card) {
        _cg = namecard_geom(_boss.boss);
        namecard_draw_band(_cg, _boss, TALK_CARD_X, _col, TALK_CARD_ROOM);
    }
    talk_draw_portrait(_t, _t.cast[_front], _card ? _boss.boss : undefined,
                       (_front == TalkWho.Boss) ? _shade : 0);

    talk_draw_plate(_t, _g);
    if (_card) {
        namecard_draw_flight(_g.hud, _cg, _boss, TALK_CARD_X, _col,
                             TALK_CARD_ROOM);
    }

    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @desc The field darkened under it all, most at its foot where the words
///       are read.
function talk_draw_veil(_a) {
    if (_a <= 0.004) return;
    var _c = merge_colour(COL_VOID, COL_ARCANE, 0.25);
    var _ys = [FIELD_Y0, FIELD_Y0 + FIELD_H * 0.45, FIELD_Y0 + FIELD_H * 0.74,
               FIELD_Y1];
    var _as = [0.50, 0.40, 0.66, 0.86];
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i < 4; _i++) {
        draw_vertex_colour(FIELD_X0, _ys[_i], _c, _a * _as[_i]);
        draw_vertex_colour(FIELD_X1, _ys[_i], _c, _a * _as[_i]);
    }
    draw_primitive_end();
}

/// @desc How far along a speaker has stepped forward, eased.
function talk_focus(_c) {
    return _c.focus * _c.focus * (3 - 2 * _c.focus);
}

/// @desc A speaker's blade: a band of their colour behind them at the
///       cut-in's tilt, from their edge of the field in toward the middle,
///       fading out as it goes. It opens from a cut of light as they arrive,
///       and runs long while they speak.
function talk_draw_blade(_t, _c) {
    if (!_c.on) return;
    var _f = talk_focus(_c);
    var _open = cutin_back(_c.t, 2, 14);
    if (_t.out_t >= 0) _open *= 1 - cutin_in(_t.out_t, 0, 14);
    if (_open <= 0.004) return;

    var _g = {
        t: _c.t,
        h: TALK_BLADE_H * _open * lerp(0.8, 1, _f),
        open: clamp(_open, 0, 1),
        cx: _c.x,
        cy: _c.y + 54,
        k: -dtan(CUTIN_TILT),
    };
    var _hh = _g.h * 0.5;
    var _reach = lerp(TALK_BLADE_SHORT, TALK_BLADE_LONG, _f);
    var _xe = (_c.side < 0) ? FIELD_X0 : FIELD_X1;      // their edge
    var _xi = clamp(_c.x - _c.side * _reach, FIELD_X0, FIELD_X1);
    var _col = _c.col;
    var _lit = lerp(0.5, 1, _f);

    // A broader, steeper band of the colour behind it, as the cut-in has.
    var _ghost = cutin_quad(_g.cx, _g.cy, _g.k + 0.075, _xe,
                            lerp(_xe, _xi, 0.8), -_hh * 1.4, _hh * 1.4);
    draw_poly_ramp(_ghost, _col, 0.13 * _g.open * _lit, 0, _xe, _g.cy,
                   -_c.side, 0, abs(_xi - _xe) * 0.8);

    // The ground, in columns: dark at the field's edge, lit behind the
    // speaker, and thinned to nothing at its inner end. The gilt lines along
    // it are thinned with it.
    var _n = 10;
    var _dark = merge_colour(_col, COL_VOID, 0.86);
    var _mid = merge_colour(_col, COL_VOID, 0.50);
    var _xs = array_create(_n + 1, 0);
    var _fs = array_create(_n + 1, 0);
    for (var _i = 0; _i <= _n; _i++) {
        _xs[_i] = lerp(_xe, _xi, _i / _n);
        var _k = clamp(abs(_xs[_i] - _xi) / TALK_BLADE_FADE, 0, 1);
        _fs[_i] = _k * _k * (3 - 2 * _k);
    }
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _n; _i++) {
        // (Lit a little inward of them, where their portrait doesn't
        // cover it.)
        var _w = clamp(1 - abs(_xs[_i] - (_c.x - _c.side * 170)) / 560, 0, 1);
        var _cc = merge_colour(_dark, _mid, _w * _w * (3 - 2 * _w));
        var _y = cutin_y(_g, _xs[_i]);
        var _a = 0.86 * _fs[_i] * lerp(0.62, 1, _f);
        draw_vertex_colour(_xs[_i], _y - _hh, _cc, _a);
        draw_vertex_colour(_xs[_i], _y + _hh, _cc, _a * 0.92);
    }
    draw_primitive_end();

    var _band = cutin_strip(_g, -_hh, _hh, min(_xe, _xi), max(_xe, _xi));

    // Their colour gathered behind their head, and rays out from it.
    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    draw_sprite_poly(spr_fx_bloom, 0, _c.x, _c.y + 10, _reach * 1.9 / _bw,
                     520 / _bw, _band, _col, (0.14 + 0.36 * _f) * _g.open);
    gpu_set_blendmode(bm_normal);
    var _burst = exp(-_c.say_t / 8) * _f;
    band_draw_rays(_c.x, _c.y + 10, _band, merge_colour(_col, c_white, 0.45),
                   (0.03 + 0.10 * _f + 0.16 * _burst) * _g.open, _burst,
                   _t.t, 150, lerp(330, 620, _f));
    band_draw_motes(_g, _col, _g.open * lerp(0.35, 1, _f), _t.t,
                    min(_xe, _xi), max(_xe, _xi), 14);

    // The gilt lines along its edges, a dark one outside each, thinned
    // with the ground.
    var _ea = min(1, _g.h / 40) * lerp(0.5, 1, _f);
    for (var _s = -1; _s <= 1; _s += 2) {
        var _e = _s * _hh;
        talk_blade_line(_g, _e + _s * 1.2, _e + _s * 4.0, _xs, _fs,
                        COL_VOID, 0.7 * _ea);
        talk_blade_line(_g, _e - 1.1, _e + 1.1, _xs, _fs, COL_GILT_LIT,
                        0.85 * _ea);
    }

    // The cut it opens from, run in from the field's edge.
    if (_c.t < 16) {
        var _ca = 1 - cutin_in(_c.t, 7, 9);
        var _x1 = lerp(_xe, _xi, card_ramp(_c.t, 0, 7));
        var _len = sqrt(1 + _g.k * _g.k);
        gpu_set_blendmode(bm_add);
        for (var _s = -1; _s <= 1; _s += 2) {
            draw_poly_ramp(cutin_strip(_g, 0, _s * 16, min(_xe, _x1),
                                       max(_xe, _x1)),
                           _col, 0.6 * _ca, 0, _xe, cutin_y(_g, _xe),
                           -_g.k / _len * _s, _s / _len, 16);
        }
        draw_poly(cutin_strip(_g, -1.6, 1.6, min(_xe, _x1), max(_xe, _x1)),
                  c_white, _ca);
        gpu_set_blendmode(bm_normal);
        draw_bloom(_x1, cutin_y(_g, _x1), 120, _col, _ca * 0.8);
        gpu_set_blendmode(bm_add);
        card_draw_glint(_x1, cutin_y(_g, _x1), 70, c_white, _ca);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc A line along a blade, from `_a` to `_b` off its centre line,
///       through the columns `_xs`, its alpha scaled by `_fs` at each. One
///       polygon, so it has no joints.
function talk_blade_line(_g, _a, _b, _xs, _fs, _col, _alpha) {
    var _n = array_length(_xs);
    var _poly = array_create(_n * 4, 0);
    var _as = array_create(_n * 2, 0);
    for (var _i = 0; _i < _n; _i++) {
        var _y = cutin_y(_g, _xs[_i]);
        var _j = _n * 2 - 1 - _i;
        _poly[_i * 2] = _xs[_i];
        _poly[_i * 2 + 1] = _y + _a;
        _poly[_j * 2] = _xs[_i];
        _poly[_j * 2 + 1] = _y + _b;
        _as[_i] = _alpha * _fs[_i];
        _as[_j] = _alpha * _fs[_i];
    }
    draw_poly_shaded(_poly, _col, _as);
}

/// @desc How much of a silhouette the boss `_e`'s portrait is: whole until
///       its name card names it, and gone `TALK_REVEAL_TIME` frames after
///       the name lands.
function talk_shadowed(_e) {
    if (_e == undefined) return 0;
    var _b = _e.boss;
    if (_b.card_t >= 0) {
        return 1 - clamp((_b.card_t - NAMECARD_SLAM_AT) / TALK_REVEAL_TIME,
                         0, 1);
    }
    return _b.named ? 0 : 1;
}

/// @desc A speaker's portrait, cut to the field: a shadow behind it, a rim
///       of their colour round it while they speak, and the portrait, dimmed
///       and stood back while they listen. It slides in from its side with a
///       flash, hops as a line starts, breathes and blinks. `_named` is the
///       boss while its name card plays: the portrait punches in as the
///       name lands, with light through its eyes. `_shade` (0 to 1) covers
///       it with a silhouette (`talk_shadowed`).
function talk_draw_portrait(_t, _c, _named, _shade = 0) {
    if (!_c.on || _c.spr == undefined) return;
    var _f = talk_focus(_c);
    var _in = cutin_quint(_c.t, 0, TALK_ENTER_TIME);
    var _out = (_t.out_t >= 0) ? cutin_in(_t.out_t, 0, 20) : 0;
    var _a = clamp(_c.t / 6, 0, 1) * (1 - _out);
    if (_a <= 0.004) return;

    // Where it stands, and how large.
    var _hop = (_c.say_t < 16) ? sin(_c.say_t / 16 * pi) * 11 * _f : 0;
    var _breath = dsin(_t.t * 2.3 + _c.side * 40);
    var _x = _c.x + _c.side * (480 * (1 - _in) + 44 * (1 - _f) + 560 * _out);
    var _y = _c.y + 12 * (1 - _f) - _hop + _breath * 2.2;
    var _s = lerp(0.955, 1, _f) * (1 + 0.004 * _breath);
    var _u = -1;
    if (_named != undefined) {
        _u = _named.card_t - NAMECARD_SLAM_AT;
        if (_u >= 0) _s += 0.05 * exp(-_u / 6) * cos(_u * 0.55);
    }

    // The pose: its frame as drawn, or with the eyes shut for a blink.
    var _poses = max(1, sprite_get_number(_c.spr) div 2);
    var _fr = clamp(_c.face, 0, _poses - 1) * 2;
    // (The two blink on different beats.)
    var _every = (_c.side < 0) ? 251 : 317;
    var _bt = (_t.t + ((_c.side < 0) ? 0 : 97)) mod _every;
    if (_bt < 5 && sprite_get_number(_c.spr) > _fr + 1) _fr++;

    var _field = cutin_field_poly();
    var _spr = _c.spr;

    // Its shadow, thrown toward the middle of the field.
    gpu_set_fog(true, COL_VOID, 0, 0);
    draw_sprite_poly(_spr, _fr, _x - _c.side * 14, _y + 16, _s, _s, _field,
                     c_white, 0.42 * _a);
    gpu_set_fog(false, c_black, 0, 0);

    // The rim, while they speak.
    if (_f > 0.02) {
        gpu_set_blendmode(bm_add);
        gpu_set_fog(true, merge_colour(_c.col, c_white, 0.3), 0, 0);
        for (var _i = 0; _i < 8; _i++) {
            draw_sprite_poly(_spr, _fr, _x + lengthdir_x(4, _i * 45),
                             _y + lengthdir_y(4, _i * 45), _s, _s, _field,
                             c_white, 0.22 * _f * _a);
        }
        gpu_set_fog(false, c_black, 0, 0);
        gpu_set_blendmode(bm_normal);
    }

    draw_sprite_poly(_spr, _fr, _x, _y, _s, _s, _field,
                     merge_colour(c_white, TALK_DIM, 0.66 * (1 - _f)), _a);

    // Not yet named: a silhouette over it.
    if (_shade > 0.004) {
        gpu_set_fog(true, TALK_SHADOW, 0, 0);
        draw_sprite_poly(_spr, _fr, _x, _y, _s, _s, _field, c_white,
                         _shade * _a);
        gpu_set_fog(false, c_black, 0, 0);
    }

    // Arriving: copies trailing behind it, and a flash as it comes to rest.
    gpu_set_blendmode(bm_add);
    if (_c.t < TALK_ENTER_TIME) {
        gpu_set_fog(true, merge_colour(_c.col, c_white, 0.5), 0, 0);
        for (var _k = 1; _k <= 3; _k++) {
            var _lag = cutin_quint(_c.t - _k * 2, 0, TALK_ENTER_TIME);
            draw_sprite_poly(_spr, _fr, _c.x + _c.side * 480 * (1 - _lag),
                             _y, _s, _s, _field, c_white,
                             0.16 * (1 - _in) * _a);
        }
        gpu_set_fog(false, c_black, 0, 0);
    }
    var _fl = max((_c.t < 22) ? (1 - _c.t / 22) : 0,
                  (_u >= 0 && _u < 14) ? (1 - _u / 14) * 0.5 : 0);
    if (_fl > 0.01) {
        gpu_set_fog(true, c_white, 0, 0);
        draw_sprite_poly(_spr, _fr, _x, _y, _s, _s, _field, c_white,
                         0.75 * _fl * _fl * _a);
        gpu_set_fog(false, c_black, 0, 0);
    }

    // Named: a streak of light through each eye as the name lands.
    if (_u >= 0 && _u < 34) {
        var _art = talk_art(_spr);
        var _len = 300 * ((_u < 4) ? (_u + 1) / 5 : exp(-(_u - 4) / 9));
        var _bw = sprite_get_width(spr_fx_bloom);
        for (var _i = 0; _i < array_length(_art.eyes); _i++) {
            var _e = _art.eyes[_i];
            var _ex = _x + _e[0] * _s;
            var _ey = _y + _e[1] * _s;
            var _sz = _e[2] * 5 * _s / _bw;
            draw_sprite_ext(spr_fx_bloom, 0, _ex, _ey, _sz, _sz * 0.8, 0,
                            _art.glow, min(1, 1.2 * exp(-_u / 8)));
            cutin_draw_streak(_ex, _ey, _len, 6, CUTIN_TILT, _art.glow, 0.9);
            cutin_draw_streak(_ex, _ey, _len * 0.6, 3, CUTIN_TILT, c_white, 1);
            cutin_draw_streak(_ex, _ey, _len * 0.25, 3, CUTIN_TILT + 90,
                              c_white, 0.8);
        }
    }
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The plate
// ---------------------------------------------------------------------------

/// @desc A point on a pane of the cut-in's glass: `_u` along it and `_v`
///       down it from its middle. A pane is `{x, y, ang}`: its middle and its
///       turn. Its ends lean (`CUTIN_PLATE_LEAN`).
function talk_pane_at(_p, _u, _v) {
    var _ax = dcos(_p.ang);
    var _ay = -dsin(_p.ang);
    var _uu = _u - _v * CUTIN_PLATE_LEAN;
    return [_p.x + _uu * _ax - _v * _ay, _p.y + _uu * _ay + _v * _ax];
}

/// @desc A strip of a pane from `_u0` to `_u1` along it and `_v0` to `_v1`
///       down it, as a polygon.
function talk_pane_quad(_p, _u0, _u1, _v0, _v1) {
    var _a = talk_pane_at(_p, _u0, _v0);
    var _b = talk_pane_at(_p, _u1, _v0);
    var _c = talk_pane_at(_p, _u1, _v1);
    var _d = talk_pane_at(_p, _u0, _v1);
    return [_a[0], _a[1], _b[0], _b[1], _c[0], _c[1], _d[0], _d[1]];
}

/// @desc A strip of a pane, `_u0` to `_u1` along it and `_v0` to `_v1` down
///       it, shaded from `_c0` at its top to `_c1` at its foot.
function talk_pane_fill(_p, _u0, _u1, _v0, _v1, _c0, _a0, _c1, _a1) {
    draw_poly_shaded(talk_pane_quad(_p, _u0, _u1, _v0, _v1),
                     [_c0, _c0, _c1, _c1], [_a0, _a0, _a1, _a1]);
}

/// @desc A rule along a pane, `_v0` to `_v1` down it, broken for `_gap`
///       either side of its middle (0 for a whole one).
function talk_pane_rule(_p, _hl, _v0, _v1, _gap, _col, _a) {
    if (_gap <= 0) {
        draw_poly(talk_pane_quad(_p, -_hl, _hl, _v0, _v1), _col, _a);
        return;
    }
    draw_poly(talk_pane_quad(_p, -_hl, -_gap, _v0, _v1), _col, _a);
    draw_poly(talk_pane_quad(_p, _gap, _hl, _v0, _v1), _col, _a);
}

/// @desc A pane of the cut-in's glass, `_len` by `_hgt`: indigo over a
///       shadow, lit at the end `_side` (-1 left, +1 right) with `_col`, a
///       gilt rule along its top and one along its foot, and a bar of `_col`
///       down that end. `_gap_top` and `_gap_foot` break the rules at their
///       middles, for an ornament set into them.
function talk_draw_pane(_p, _len, _hgt, _col, _side, _a, _gap_top = 0,
                        _gap_foot = 0) {
    if (_a <= 0.01 || _hgt <= 1) return;
    var _hl = _len * 0.5;
    var _hh = _hgt * 0.5;

    talk_pane_fill({ x: _p.x + 8, y: _p.y + 10, ang: _p.ang }, -_hl, _hl,
                   -_hh, _hh, COL_VOID, 0.5 * _a, COL_VOID, 0.5 * _a);
    talk_pane_fill(_p, -_hl, _hl, -_hh, _hh,
                   merge_colour(COL_ARCANE, COL_VOID, 0.12), 0.94 * _a,
                   COL_VOID, 0.96 * _a);

    // The speaker's colour, in from their end.
    var _end = talk_pane_at(_p, _side * _hl, 0);
    draw_poly_ramp(talk_pane_quad(_p, 2 - _hl, _hl - 2, -_hh, _hh), _col,
                   0.16 * _a, 0, _end[0], _end[1],
                   -_side * dcos(_p.ang), _side * dsin(_p.ang), _len * 0.45);

    // The rules: a lit one along the top with a dark line under it, and one
    // along the foot.
    talk_pane_rule(_p, _hl, -_hh, -_hh + 2.4, _gap_top, COL_GILT_LIT,
                   0.95 * _a);
    talk_pane_rule(_p, _hl, -_hh + 2.4, -_hh + 4.2, _gap_top, COL_VOID,
                   0.8 * _a);
    talk_pane_rule(_p, _hl, _hh - 2.4, _hh, _gap_foot, COL_GILT, 0.9 * _a);

    // The bar of their colour down that end.
    talk_pane_fill(_p, (_side < 0) ? -_hl : (_hl - TALK_BAR_W),
                   (_side < 0) ? (TALK_BAR_W - _hl) : _hl, -_hh, _hh,
                   _col, 0.95 * _a, _col, 0.95 * _a);
}

/// @desc One of `spr_card_rule`'s ornaments (`band_draw_ornament`), level
///       and centred on (`_x`, `_y`): the middle `_w` of frame `_fr`.
function talk_draw_ornament(_fr, _w, _x, _y, _a) {
    var _sw = sprite_get_width(spr_card_rule);
    var _sh = sprite_get_height(spr_card_rule);
    draw_sprite_part_ext(spr_card_rule, _fr, (_sw - _w) * 0.5, 0, _w, _sh,
                         _x - _w * 0.5, _y - _sh * 0.5, 1, 1, c_white, _a);
}

/// @desc The plate, the words on it, the speaker's name tab, and the mark
///       that says a line is done.
function talk_draw_plate(_t, _g) {
    if (_t.plate <= 0.004) return;
    var _o = cutin_back(_t.plate, 0, 1);
    var _c = _t.cast[_t.said];
    var _hgt = TALK_PLATE_H * _o;
    var _hl = TALK_PLATE_W * 0.5;
    var _p = { x: FIELD_CX, y: TALK_PLATE_Y, ang: 0 };
    var _a = min(1, _t.plate * 3);

    // The name tabs first: they rise from behind the plate.
    for (var _i = 0; _i < 2; _i++) talk_draw_tab(_t, _t.cast[_i], _g, _hgt);

    talk_draw_pane(_p, TALK_PLATE_W, _hgt, _c.col, _c.side, _a,
                   RULE_ORN_CRESCENT * 0.5 + 12, RULE_ORN_LOZENGE * 0.5 + 4);

    // The title card's ornaments set into its rules where they break: the
    // crescent on top, the lozenge under. Each is the middle of its rule's
    // sprite, whose own lines are left out (the plate has its own), centred
    // on the plate's rule.
    var _top = talk_pane_at(_p, 0, -_hgt * 0.5 + 1.2);
    var _bot = talk_pane_at(_p, 0, _hgt * 0.5 - 1.2);
    var _oa = _a * clamp((_t.plate - 0.5) * 2, 0, 1);
    talk_draw_ornament(0, RULE_ORN_CRESCENT, _top[0], _top[1], _oa);
    talk_draw_ornament(1, RULE_ORN_LOZENGE, _bot[0], _bot[1], _oa);

    // The line it opens from, and shuts to (gone before the words show).
    if (_t.plate < 0.7) {
        var _la = 1 - _t.plate / 0.7;
        gpu_set_blendmode(bm_add);
        draw_poly(talk_pane_quad(_p, -_hl * min(1, _t.plate * 2.2),
                                 _hl * min(1, _t.plate * 2.2), -1.6, 1.6),
                  c_white, _la);
        for (var _s = -1; _s <= 1; _s += 2) {
            draw_poly_ramp(talk_pane_quad(_p, -_hl, _hl, 0, _s * 12), _c.col,
                           0.5 * _la, 0, FIELD_CX, TALK_PLATE_Y, 0, _s, 12);
        }
        gpu_set_blendmode(bm_normal);
    }

    // A sheen along the top rule as a line starts.
    if (_t.line_t < 26 && _t.plate >= 1) {
        var _sp = _t.line_t / 26;
        var _sx = _top[0] + _c.side * lerp(_hl, -_hl, _sp);
        draw_bloom(_sx, _top[1], 200, COL_GILT_LIT, 0.5 * sin(_sp * pi));
    }

    var _ta = clamp((_t.plate - 0.7) / 0.3, 0, 1);
    if (_ta > 0.01) talk_draw_words(_t, _ta);

    // What the keys do, along its foot; and a star over that once the line
    // is done.
    var _foot = TALK_PLATE_Y + TALK_PLATE_H * 0.5;
    if (_ta > 0.01) {
        draw_set_font(fnt_small());
        draw_set_valign(fa_middle);
        draw_text_tracked(FIELD_CX + _hl - 62, _foot - 19,
                          "Z  NEXT     X  SKIP", 4, HUD_TAG_COL, 0.6 * _ta, 2,
                          fa_right);
        draw_set_valign(fa_top);
    }
    if (_ta > 0.01 && _t.shown >= _t.n && _t.n > 0) {
        card_draw_star(FIELD_CX + _hl - 54,
                       _foot - 58 + dsin(_t.t * 5) * 3,
                       20 + 6 * dsin(_t.t * 7), 0.9 * _ta);
    }
}

/// @desc The words, as far as they have been typed: the newest letters
///       still bright.
function talk_draw_words(_t, _a) {
    var _rows = array_length(_t.rows);
    if (_rows <= 0) return;
    draw_set_font(fnt_talk());
    draw_set_halign(fa_left);
    draw_set_valign(fa_bottom);
    var _x = FIELD_CX - TALK_TEXT_W * 0.5;
    var _y0 = TALK_PLATE_Y - 4 - (_rows - 1) * TALK_ROW_H * 0.5;
    var _ink = merge_colour(COL_VOID, COL_ARCANE, 0.4);
    var _before = 0;
    for (var _r = 0; _r < _rows; _r++) {
        var _row = _t.rows[_r];
        var _len = string_length(_row);
        var _k = clamp(_t.shown - _before, 0, _len);
        var _y = text_cap_middle_y(_y0 + _r * TALK_ROW_H);
        if (_k > 0) {
            draw_text_outline(_x, _y, string_copy(_row, 1, _k), COL_PARCHMENT,
                              _a, 2, _ink);
            // The last few, lit.
            gpu_set_blendmode(bm_add);
            draw_set_colour(COL_GILT_LIT);
            for (var _j = max(1, _k - 5); _j <= _k; _j++) {
                var _age = _t.shown - (_before + _j) + _t.rest * 0.3;
                var _ga = _a * (1 - _age / 6) * 0.9;
                if (_ga <= 0.01) continue;
                draw_set_alpha(_ga);
                draw_text(_x + string_width(string_copy(_row, 1, _j - 1)), _y,
                          string_char_at(_row, _j));
            }
            gpu_set_blendmode(bm_normal);
            draw_set_alpha(1);
            draw_set_colour(c_white);
        }
        _before += _len;
    }
}

/// @desc A speaker's name on a tab standing on the plate's top edge at their
///       end of it, risen from behind the plate while they speak. `_hgt` is
///       the plate's height this frame. The tab's outer end and its bar of
///       colour carry on the plate's own, in one line. A boss that has not
///       been named yet is `? ? ?`.
function talk_draw_tab(_t, _c, _g, _hgt) {
    if (_c.tab <= 0.004) return;
    var _name = _c.name;
    if (_c.side > 0) {
        var _boss = _g[$ "boss_ref"];
        if (_boss != undefined && !_boss.boss.named
            && _boss.boss.card_t < 0) {
            _name = "? ? ?";
        }
    }

    draw_set_font(fnt_spell());
    var _nw = max(1, string_width(_name)) * TALK_TAB_S;
    var _len = _nw + TALK_TAB_PAD * 2 + TALK_BAR_W;
    // Its middle, measured down from the plate's: standing on the top edge
    // when risen. It keeps to the line of the plate's leaning end as it
    // rises.
    var _v = -(_hgt + TALK_TAB_H) * 0.5
             + (1 - cutin_quint(_c.tab, 0, 1)) * (TALK_TAB_H + 6);
    var _p = {
        x: FIELD_CX + _c.side * (TALK_PLATE_W - _len) * 0.5
           - _v * CUTIN_PLATE_LEAN,
        y: TALK_PLATE_Y + _v,
        ang: 0,
    };
    var _a = min(1, _c.tab * 2.5);
    talk_draw_pane(_p, _len, TALK_TAB_H, _c.col, _c.side, _a);

    // The name in gilt, centred in what the bar leaves, a mark either side
    // of it; a sheen crosses it as its owner's line starts.
    var _mid = talk_pane_at(_p, -_c.side * TALK_BAR_W * 0.5, 1);
    var _sheen = (_c.say_t >= 4 && _c.say_t < 36) ? (_c.say_t - 4) / 32 : -1;
    cutin_draw_gilt_line(_mid[0] - _nw * 0.5, _mid[1], _name, TALK_TAB_S, 0,
                         _a, 0.6 * exp(-_c.say_t / 5), _sheen);
    for (var _s = -1; _s <= 1; _s += 2) {
        draw_sprite_ext(spr_ui_mark, 0,
                        _mid[0] + _s * (_nw * 0.5 + TALK_TAB_PAD * 0.5),
                        _mid[1], 0.36, 0.36, 0, COL_GILT_LIT, 0.85 * _a);
    }
}
