/// @desc The rack of stage cards. Planned stages are drawn locked.

// The rack has no field, so the background is scaled to the whole screen.
bg_draw_back(bg, true);

// An indigo scrim over the background.
draw_scrim(0.62, COL_ARCANE);
bg_draw_front(bg, 0, true);
draw_grain(0, 0, GAME_W, GAME_H,
           merge_colour(COL_PARCHMENT, COL_RUNE, 0.4), 0.07);
fascia_motes(0, 0, GAME_W, GAME_H);

// ---- the title ----------------------------------------------------------
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_font(fnt_title());
draw_text_outline(GAME_CX, 124, "NEXARCHON", COL_SZUIX_LIT, 1, 3);

// The console's crest, under the title.
var _cw2 = 520;
var _cs2 = _cw2 / sprite_get_width(spr_ui_crest);
draw_sprite_ext(spr_ui_crest, 0, GAME_CX - _cw2 * 0.5, 164, _cs2, _cs2, 0,
                COL_GILT, 0.9);

draw_set_font(fnt_ui());
draw_text_outline(GAME_CX, 282,
                  string(progress_cleared_count()) + " OF "
                  + string(stage_n) + " STAGES CLEARED",
                  merge_colour(COL_PARCHMENT, COL_GILT, 0.35), 0.85, 2);

// ---- the rack -----------------------------------------------------------
//
// A column per zone, headed by its name, and the extra cards last. Every card
// is on screen at once.
var _nc = array_length(columns);
var _cw = 276;
var _ch = 130;
var _gap = 20;
var _rgap = 14;
var _hy = 330;
var _y0 = 372;
var _x0 = GAME_CX - (_nc * (_cw + _gap) - _gap) * 0.5;
var _dim = merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.62);
var _quiet = merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.45);

for (var _c = 0; _c < _nc; _c++) {
    var _column = columns[_c];
    var _x = _x0 + _c * (_cw + _gap);
    var _mx = _x + _cw * 0.5;

    // The zone's name over its column, lit while the cursor is in it.
    var _here = (col_of[pick] == _c);
    draw_set_font(fnt_small());
    draw_text_fit(_mx, _hy, _column.name, _cw - 20,
                  _here ? COL_GILT_LIT : COL_GILT, _here ? 1 : 0.7, 2);
    draw_rule(_mx, _hy + 22, _cw - 60, COL_GILT, _here ? 0.7 : 0.35);

    for (var _r = 0; _r < array_length(_column.items); _r++) {
        var _idx = _column.items[_r];
        var _def = stages[_idx];
        var _sel = (_idx == pick);
        var _built = stage_is_built(_def);
        // The drafting table is always open and never cleared.
        var _draft = stage_is_draft(_def);
        var _open = _draft || (_built && stage_is_unlocked(_def));
        var _rec = progress_stage(_def.id);

        // The selected card lifts and bobs.
        var _lift = _sel ? (5 + 3 * dsin(t * 3)) : 0;
        var _cy = _y0 + _r * (_ch + _rgap) - _lift;

        // A card is drawn like a console plate (corner pieces when selected).
        draw_plate(_x, _cy, _x + _cw, _cy + _ch, _open ? 1 : 0.72);
        var _edge = _open ? (_sel ? COL_GILT_LIT : COL_GILT)
                          : merge_colour(COL_GILT, COL_ARCANE, 0.55);
        draw_set_alpha(_sel ? 1 : 0.6);
        draw_set_colour(_edge);
        for (var _e = 0; _e < (_sel ? 3 : 1); _e++) {
            draw_rectangle(_x + _e, _cy + _e, _x + _cw - _e, _cy + _ch - _e,
                           true);
        }
        draw_set_alpha(1);
        draw_set_colour(c_white);
        if (_sel) {
            draw_corners(_x, _cy, _x + _cw, _cy + _ch, COL_GILT_LIT, 0.85, 8,
                         0.22);
        }

        // The name, the subtitle, and one line of status.
        draw_set_font(fnt_ui());
        var _name = _def.name;
        var _nw = _cw - 28;
        var _ncol = _open ? (_sel ? COL_GILT_LIT : COL_PARCHMENT) : _dim;
        var _na = _open ? (_sel ? 1 : 0.85) : 0.9;
        // A name too long to read on one line is set on two, broken at the
        // space that leaves the longer line shortest.
        var _brk = 0;
        if (string_width(_name) * 0.45 > _nw) {
            var _best = infinity;
            for (var _k = 1; _k <= string_length(_name); _k++) {
                if (string_char_at(_name, _k) != " ") continue;
                var _w = max(string_width(string_copy(_name, 1, _k - 1)),
                             string_width(string_delete(_name, 1, _k)));
                if (_w < _best) {
                    _best = _w;
                    _brk = _k;
                }
            }
        }
        if (_brk > 0) {
            var _l1 = string_copy(_name, 1, _brk - 1);
            var _l2 = string_delete(_name, 1, _brk);
            var _s = min(0.7, _nw / max(string_width(_l1), string_width(_l2)));
            draw_text_outline_scaled(_mx, _cy + 20, _l1, _ncol, _na, _s, 2);
            draw_text_outline_scaled(_mx, _cy + 44, _l2, _ncol, _na, _s, 2);
        } else {
            draw_text_fit(_mx, _cy + 32, _name, _nw, _ncol, _na, 2);
        }
        draw_set_font(fnt_small());
        draw_text_fit(_mx, _cy + 66, _def.subtitle, _cw - 24,
                      _open ? merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.3)
                            : _dim,
                      _open ? 0.8 : 0.7, 1);

        // An open stage not yet cleared says so quietly, in the small face.
        var _status = "NOT YET CLEARED";
        var _col = _quiet;
        if (!_open) {
            _status = _built ? ("NEEDS " + string(_def.needs)) : "NOT YET BUILT";
            _col = _dim;
        } else if (_draft) {
            _status = string(array_length(draft_list())) + " UNCLAIMED";
            _col = COL_MANA;
        } else if (stage_is_preview(_def)) {
            // No boss, so nothing to clear.
            _status = "THE TURN, LOOPED";
            _col = COL_MANA;
        } else if (stage_is_old_draft(_def)) {
            // Can't be cleared (empty id).
            _status = "OLD DRAFT";
            _col = COL_MANA;
        } else if (_rec.cleared) {
            _status = "BEST  " + string(_rec.best);
            if (_rec.no_hit) _status += "   NO HIT";
            if (_rec.captured > 0) {
                _status += "   " + string(_rec.captured) + " CAPTURED";
            }
            _col = COL_GRAZE;
        }
        var _quietly = (_col == _quiet);
        draw_set_font(_quietly ? fnt_small() : fnt_ui());
        draw_text_fit(_mx, _cy + 100, _status, _cw - 28, _col,
                      _quietly ? 0.7 : (_open ? 0.9 : 0.8), 2);
    }
}

draw_set_font(fnt_ui());
draw_text_outline(GAME_CX, GAME_H - 86,
                  "ARROWS  CHOOSE      Z  BEGIN      X  PRACTISE      ESC  QUIT",
                  merge_colour(COL_PARCHMENT, COL_GILT, 0.4), 0.7, 2);

fx_draw_text();
draw_set_halign(fa_left);
draw_set_valign(fa_top);

// The dive into a stage: a white wipe out of the middle.
if (enter_t > 0) {
    var _p = 1 - enter_t / 34;
    draw_set_alpha(_p * _p);
    draw_set_colour(c_white);
    draw_rectangle(0, 0, GAME_W, GAME_H, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

fx_draw_flash();
