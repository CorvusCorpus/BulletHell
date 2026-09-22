/// @desc The rack of stage cards. Planned stages are drawn locked.

// The rack has no field, so the background is scaled to the whole screen.
bg_draw_back(bg, true);

// An indigo scrim over the background.
draw_scrim(0.62, COL_ARCANE);
bg_draw_front(bg, 0, true);
draw_grain(0, 0, GAME_W, GAME_H,
           merge_colour(COL_PARCHMENT, COL_RUNE, 0.4), 0.07);
fascia_motes(0, 0, GAME_W, GAME_H);

var _n = array_length(stages);

// ---- the title ----------------------------------------------------------
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_font(fnt_title());
draw_text_outline(GAME_CX, 150, "NO MERE PAWN", COL_SZUIX_LIT, 1, 3);

// The console's crest, under the title.
var _cw2 = 520;
var _cs2 = _cw2 / sprite_get_width(spr_ui_crest);
draw_sprite_ext(spr_ui_crest, 0, GAME_CX - _cw2 * 0.5, 190, _cs2, _cs2, 0,
                COL_GILT, 0.9);

draw_set_font(fnt_ui());
draw_text_outline(GAME_CX, 318,
                  string(progress_cleared_count()) + " OF "
                  + string(stage_n) + " STAGES CLEARED",
                  merge_colour(COL_PARCHMENT, COL_GILT, 0.35), 0.85, 2);

// ---- the rack -----------------------------------------------------------
//
// Five across, scrolling horizontally with the cursor.
var _cw = 320;
var _ch = 300;
var _gap = 34;
var _y = 470;
var _shown = 5;
var _first = clamp(round(cursor) - 2, 0, max(0, _n - _shown));
var _slide = (cursor - _first - 2) * 0;      // the rack itself does not slide
var _x0 = GAME_CX - ((_shown * (_cw + _gap)) - _gap) * 0.5;

for (var _i = 0; _i < _shown; _i++) {
    var _idx = _first + _i;
    if (_idx >= _n) break;
    var _def = stages[_idx];
    var _sel = (_idx == pick);
    var _built = stage_is_built(_def);
    // The drafting table is always open and never cleared.
    var _draft = stage_is_draft(_def);
    var _open = _draft || (_built && stage_is_unlocked(_def));
    var _rec = progress_stage(_def.id);

    var _x = _x0 + _i * (_cw + _gap) + _slide;
    // The selected card lifts and bobs.
    var _lift = _sel ? (10 + 4 * dsin(t * 3)) : 0;
    var _cy = _y - _lift;

    // A card is drawn like a console plate (corner pieces when selected).
    draw_plate(_x, _cy, _x + _cw, _cy + _ch, _open ? 1 : 0.72);
    var _edge = _open ? (_sel ? COL_GILT_LIT : COL_GILT)
                      : merge_colour(COL_GILT, COL_ARCANE, 0.55);
    draw_set_alpha(_sel ? 1 : 0.6);
    draw_set_colour(_edge);
    for (var _e = 0; _e < (_sel ? 3 : 1); _e++) {
        draw_rectangle(_x + _e, _cy + _e, _x + _cw - _e, _cy + _ch - _e, true);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
    if (_sel) {
        draw_corners(_x, _cy, _x + _cw, _cy + _ch, COL_GILT_LIT, 0.85, -4,
                     0.5);
    }

    if (_open) {
        draw_set_font(fnt_ui());
        draw_text_fit(_x + _cw * 0.5, _cy + 62, _def.name, _cw - 40,
                      _sel ? COL_GILT_LIT : COL_PARCHMENT, _sel ? 1 : 0.85, 2);
        draw_set_font(fnt_small());
        draw_text_fit(_x + _cw * 0.5, _cy + 108, _def.subtitle, _cw - 30,
                      merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.3),
                      0.8, 1);

        if (_draft) {
            // The number of drafts, and that it is practice-only.
            draw_set_font(fnt_ui());
            draw_text_outline(_x + _cw * 0.5, _cy + 176,
                              string(array_length(draft_list())) + " UNCLAIMED",
                              COL_MANA, 0.9, 2);
            draw_set_font(fnt_small());
            draw_text_outline(_x + _cw * 0.5, _cy + 216, "PRACTICE ONLY",
                              merge_colour(COL_PARCHMENT, COL_ARCANE_LIT,
                                           0.45), 0.8, 1);
        } else if (stage_is_preview(_def)) {
            // No boss, so no "not yet cleared" line.
            draw_set_font(fnt_ui());
            draw_text_outline(_x + _cw * 0.5, _cy + 176, "THE TURN, LOOPED",
                              COL_MANA, 0.9, 2);
            draw_set_font(fnt_small());
            draw_text_outline(_x + _cw * 0.5, _cy + 216, "NOTHING TO CLEAR",
                              merge_colour(COL_PARCHMENT, COL_ARCANE_LIT,
                                           0.45), 0.8, 1);
        } else if (stage_is_old_draft(_def)) {
            // Can't be cleared (empty id).
            draw_set_font(fnt_ui());
            draw_text_outline(_x + _cw * 0.5, _cy + 176, "OLD DRAFT",
                              COL_MANA, 0.9, 2);
            draw_set_font(fnt_small());
            draw_text_outline(_x + _cw * 0.5, _cy + 216, "NOTHING TO CLEAR",
                              merge_colour(COL_PARCHMENT, COL_ARCANE_LIT,
                                           0.45), 0.8, 1);
        } else if (_rec.cleared) {
            draw_set_font(fnt_ui());
            draw_text_outline(_x + _cw * 0.5, _cy + 176,
                              "BEST  " + string(_rec.best), COL_GRAZE, 0.9, 2);
            draw_set_font(fnt_small());
            var _marks = "";
            if (_rec.no_hit) _marks += "NO HIT   ";
            if (_rec.captured > 0) {
                _marks += string(_rec.captured) + " CAPTURED";
            }
            if (_marks != "") {
                draw_text_outline(_x + _cw * 0.5, _cy + 216, _marks,
                                  COL_MANA, 0.8, 1);
            }
        } else {
            draw_set_font(fnt_small());
            draw_text_outline(_x + _cw * 0.5, _cy + 186, "NOT YET CLEARED",
                              merge_colour(COL_PARCHMENT, COL_ARCANE_LIT,
                                           0.45), 0.7, 1);
        }
    } else {
        // Locked and unbuilt cards still show the stage's name.
        draw_set_font(fnt_ui());
        var _dim = merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.62);
        draw_text_fit(_x + _cw * 0.5, _cy + 62, _def.name, _cw - 40,
                      _dim, 0.9, 2);
        draw_set_font(fnt_small());
        draw_text_fit(_x + _cw * 0.5, _cy + 108, _def.subtitle, _cw - 30,
                      _dim, 0.7, 1);
        draw_set_font(fnt_ui());
        draw_text_outline(_x + _cw * 0.5, _cy + 186,
                          _built ? ("NEEDS " + string(_def.needs))
                                 : "NOT YET BUILT",
                          _dim, 0.8, 2);
    }
}

// Page dots under the rack.
var _dy = _y + _ch + 54;
for (var _i = 0; _i < _n; _i++) {
    var _dx = GAME_CX + (_i - (_n - 1) * 0.5) * 26;
    var _on = (_i == pick);
    draw_set_alpha(_on ? 1 : 0.4);
    draw_set_colour(_on ? COL_GILT_LIT : COL_GILT);
    draw_circle(_dx, _dy, _on ? 7 : 4, false);
}
draw_set_alpha(1);
draw_set_colour(c_white);

draw_set_font(fnt_ui());
draw_text_outline(GAME_CX, GAME_H - 110,
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
