/// @desc The attack list, drawn with the same scrim, plate and crest as the
///       rack.

bg_draw_back(bg, true);
draw_scrim(0.66, COL_ARCANE);
bg_draw_front(bg, 0, true);
draw_grain(0, 0, GAME_W, GAME_H,
           merge_colour(COL_PARCHMENT, COL_RUNE, 0.4), 0.07);
fascia_motes(0, 0, GAME_W, GAME_H);

draw_set_halign(fa_center);
draw_set_valign(fa_middle);

draw_set_font(fnt_head());
draw_text_outline(GAME_CX, 96, "ATTACK PRACTICE", COL_GILT_LIT, 1, 3);

var _cw = 460;
var _cs = _cw / sprite_get_width(spr_ui_crest);
draw_sprite_ext(spr_ui_crest, 0, GAME_CX - _cw * 0.5, 124, _cs, _cs, 0,
                COL_GILT, 0.85);

draw_set_font(fnt_ui());
draw_text_fit(GAME_CX, 176, stage.name, 1100,
              merge_colour(COL_PARCHMENT, COL_GILT, 0.3), 0.9, 2);

// ---- the plate -----------------------------------------------------------
//
// Sized to the list, up to a maximum height; longer lists scroll inside it
// (row positions are computed in Create).
var _x1 = 300;
var _x2 = GAME_W - 300;
var _y1 = 220;
// 40 is the margin under the last visible row's centre.
var _y2 = list_top + list_window + 40;
draw_plate(_x1, _y1, _x2, _y2, 1);
draw_corners(_x1, _y1, _x2, _y2, COL_GILT, 0.8, -4, 0.6);

var _pad = 58;
var _lx = _x1 + _pad;               // the left edge of a row's text
var _rx = _x2 - _pad;               // and its right

if (array_length(picks) <= 0) {
    draw_set_font(fnt_ui());
    draw_text_outline(GAME_CX, (_y1 + _y2) * 0.5, "NOTHING TO PRACTISE HERE",
                      merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.5),
                      0.8, 2);
} else {
    // The cursor is a lit band behind the whole row. Rows fade out over half
    // a pitch at the window's edges and aren't drawn beyond that.
    var _top = list_top;
    var _bot = list_top + list_window;
    var _fade = row_pitch * 0.5;

    for (var _i = 0; _i < array_length(rows); _i++) {
        var _r = rows[_i];
        var _y = list_top + row_y[_i] - scroll;
        var _out = max(0, _top - _y, _y - _bot);
        if (_out >= _fade) continue;
        var _a = 1 - _out / _fade;

        if (_r.header) {
            draw_set_halign(fa_left);
            draw_set_font(fnt_small());
            draw_text_tracked(_lx, _y, _r.label, 8, COL_GILT, 0.95 * _a, 2);
            draw_rule((_lx + _rx) * 0.5, _y + 24, _rx - _lx, COL_GILT,
                      0.45 * _a);
            continue;
        }

        var _sel = (picks[pick] == _i);
        var _bc = global.bullet_colour[_r.col];

        if (_sel) {
            draw_set_alpha((0.20 + 0.05 * dsin(t * 3)) * _a);
            draw_set_colour(COL_GILT);
            draw_rectangle(_lx - 26, _y - 24, _rx + 26, _y + 24, false);
            draw_set_alpha(0.55 * _a);
            draw_rectangle(_lx - 26, _y - 24, _rx + 26, _y - 23, false);
            draw_rectangle(_lx - 26, _y + 23, _rx + 26, _y + 24, false);
            draw_set_alpha(1);
            draw_set_colour(c_white);
        }

        // The console's mark sprite in the attack's hue (frame 1 for a spell).
        draw_sprite_ext(spr_ui_mark, _r.spell ? 1 : 0, _lx + 14, _y,
                        0.72, 0.72, 0, _bc, (_sel ? 1 : 0.75) * _a);

        draw_set_halign(fa_left);
        draw_set_font(fnt_ui());
        draw_text_outline(_lx + 50, _y, _r.label,
                          _sel ? COL_GILT_LIT : COL_PARCHMENT,
                          (_sel ? 1 : 0.78) * _a, 2);

        // The attack's clock and its span of the boss's health bar.
        draw_set_halign(fa_right);
        draw_set_font(fnt_small());
        var _dim = merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.4);
        draw_text_outline(_rx - 210, _y,
                          string(floor(_r.time / FPS)) + "s",
                          _sel ? COL_PARCHMENT : _dim,
                          (_sel ? 0.95 : 0.7) * _a, 2);
        draw_text_outline(_rx, _y,
                          string(round(_r.hp_from * 100)) + "% - "
                          + string(round(_r.hp_to * 100)) + "%",
                          _sel ? COL_PARCHMENT : _dim,
                          (_sel ? 0.95 : 0.7) * _a, 2);
    }

    // Arrows at each end that has more list beyond it.
    var _sx = _x2 - 30;
    var _pulse = 0.55 + 0.2 * dsin(t * 4);
    draw_set_colour(COL_GILT);
    if (scroll > 1) {
        draw_set_alpha(_pulse);
        draw_triangle(_sx - 9, _top + 6, _sx + 9, _top + 6, _sx, _top - 8,
                      false);
    }
    if (scroll < list_span - list_window - 1) {
        draw_set_alpha(_pulse);
        draw_triangle(_sx - 9, _bot - 6, _sx + 9, _bot - 6, _sx, _bot + 8,
                      false);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// The control hints sit under the plate.
var _hint_y = min(GAME_H - 84, _y2 + 74);

draw_set_halign(fa_center);
draw_set_font(fnt_ui());
draw_text_outline(GAME_CX, _hint_y,
                  "ARROWS  CHOOSE      Z  BEGIN      X  BACK",
                  merge_colour(COL_PARCHMENT, COL_GILT, 0.4), 0.7, 2);

// Tells the player practice starts with full life and sigil.
draw_set_font(fnt_small());
draw_text_outline(GAME_CX, _hint_y + 44,
                  "FULL LIFE AND FULL SIGIL, EVERY ATTEMPT",
                  merge_colour(COL_PARCHMENT, COL_ARCANE_LIT, 0.4), 0.6, 1);

fx_draw_text();
draw_set_halign(fa_left);
draw_set_valign(fa_top);

if (enter_t > 0) {
    var _p = 1 - enter_t / 26;
    draw_set_alpha(_p * _p);
    draw_set_colour(c_white);
    draw_rectangle(0, 0, GAME_W, GAME_H, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

fx_draw_flash();
