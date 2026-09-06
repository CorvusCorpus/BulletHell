/// @desc Fonts, text styles, and the pieces every readout in the game is made
///       of: bars, panels, and the rule that gets them out of the player's way.

/// @desc Build the sprite fonts. Called once, from obj_boot.
///
///       The glyph string is assembled rather than written out, because it has
///       to match `tools/make_fonts.py`'s frame order exactly and a typed-out
///       string of ninety-five characters is a typo waiting to shift every
///       glyph in the game by one.
function ui_init() {
    var _glyphs = "";
    for (var _i = 32; _i <= 126; _i++) {
        _glyphs += chr(_i);
    }

    // `prop = true` measures each glyph's real ink, which is what makes the
    // uniform atlas cell invisible. See the note about the space in the
    // generator: a fully transparent frame measures zero and eats every space.
    global.fnt_small = font_add_sprite_ext(spr_fnt_small, _glyphs, true, 1);
    global.fnt_ui    = font_add_sprite_ext(spr_fnt_ui, _glyphs, true, 1);
    global.fnt_num   = font_add_sprite_ext(spr_fnt_num, _glyphs, true, 2);
    global.fnt_head  = font_add_sprite_ext(spr_fnt_head, _glyphs, true, 2);
    global.fnt_spell = font_add_sprite_ext(spr_fnt_spell, _glyphs, true, 3);
    global.fnt_title = font_add_sprite_ext(spr_fnt_title, _glyphs, true, 4);
}

// The fonts are reached through these rather than through `global.fnt_*` at
// every call site, so a font can be re-pointed in one place.
function fnt_small()  { return global.fnt_small; }
function fnt_ui()     { return global.fnt_ui; }
function fnt_num()    { return global.fnt_num; }
function fnt_head()   { return global.fnt_head; }
function fnt_spell()  { return global.fnt_spell; }
function fnt_title()  { return global.fnt_title; }

/// @desc Set font, colour and alpha in one call.
function text_style(_font, _col, _alpha = 1) {
    draw_set_font(_font);
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
}

/// @desc How tall the ink of a line actually is.
///
///       **`string_height` on a sprite font returns the atlas cell, not the
///       ink.** Every glyph sits in a uniform box with room for an ascender
///       and a descender that a row of capitals never touches, and the cell is
///       nearly twice the height of the letters in it. Laying a HUD out
///       against the cell puts a visible and growing gap under everything.
///       `check_font_ink_ratio` re-derives the constant from the shipped PNGs
///       and refuses it if `make_fonts.py` drifts.
function text_ink_height(_str) {
    return string_height(_str) * FONT_INK_RATIO;
}

/// @desc Text with a hard dark outline under it.
///
///       **Every string drawn over the field gets one.** The field is a moving
///       background with up to four thousand lit bullets on it, so there is no
///       colour a string can be that is legible everywhere -- a glow only ever
///       adds light to a bright frame, and a drop shadow only works on one
///       side. An outline works against all of it, and it is the same argument
///       Wordsearch's score preview makes for a hard outline over lit tiles.
///       **It puts the draw state back, and that is not tidiness.** This is a
///       leaf -- it draws one string and returns -- so leaving the alpha it
///       happened to finish on is state escaping into whatever draws next,
///       which is a *different event on the following frame*. It shipped
///       exactly that: the stage-name splash fades its text out over 34
///       frames, so the GUI event ended each of those frames with the alpha
///       wound down toward zero, and the first thing the next frame's Draw
///       event does is lay down the ground layer. The world faded out under
///       the splash and snapped back the frame the splash stopped drawing.
///
///       `draw_band` two functions down already restored, which is what made
///       the leak so hard to see: the band went out clean and the text did
///       not. A leaf that draws restores; `text_style` is the deliberate
///       exception, because setting the state *is* what it is for.
function draw_text_outline(_x, _y, _str, _col, _alpha = 1, _thick = 2,
                           _outline = c_black) {
    draw_set_colour(_outline);
    draw_set_alpha(_alpha * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text(_x + lengthdir_x(_thick, _i * 45),
                  _y + lengthdir_y(_thick, _i * 45), _str);
    }
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    draw_text(_x, _y, _str);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The same, scaled -- for anything that arrives at size and settles.
function draw_text_outline_scaled(_x, _y, _str, _col, _alpha, _scale,
                                  _thick = 2, _outline = c_black) {
    draw_set_colour(_outline);
    draw_set_alpha(_alpha * 0.85);
    for (var _i = 0; _i < 8; _i++) {
        draw_text_transformed(_x + lengthdir_x(_thick, _i * 45),
                              _y + lengthdir_y(_thick, _i * 45), _str,
                              _scale, _scale, 0);
    }
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    draw_text_transformed(_x, _y, _str, _scale, _scale, 0);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc Text shrunk to fit a width, and never grown past its natural size.
///
///       A boss's name is authored and a score is not: six digits at level one
///       becomes nine by the end of a good run, and picking a size that fits
///       the first is how a readout comes to be clipped an hour into a session
///       nobody watched.
function draw_text_fit(_x, _y, _str, _max_w, _col, _alpha = 1, _thick = 2,
                      _extra = 1) {
    var _w = string_width(_str);
    var _s = (_w > _max_w && _w > 0) ? (_max_w / _w) : 1;
    // `_extra` is for something arriving *at* its resting size -- a banner
    // settling onto a nameplate. It multiplies the fit rather than replacing
    // it, so an oversized entrance can still not overflow the box it lands in.
    draw_text_outline_scaled(_x, _y, _str, _col, _alpha, _s * _extra, _thick);
    return _s;
}

/// @desc Text with the letters pushed apart. Every tag in the console.
///
///       **Tracking is what makes a four-letter label read as a label.**
///       `SCORE` set solid at 26px beside a number at 56px is a small word
///       next to a big one; the same word opened out to twice its width is a
///       *caption*, which is what the eye needs it to be -- it stops competing
///       with the value and starts introducing it. It is the oldest trick in
///       game-interface typography and the one that most reliably separates a
///       HUD somebody designed from a HUD somebody wrote.
///
///       A sprite font has no tracking, so the string is drawn a glyph at a
///       time. That is fine at the sizes this is used at -- a tag is five or
///       six characters -- and it is why there is no wrapped or fitted
///       variant: anything long enough to want one should not be tracked.
///
///       `_halign` is honoured by measuring the run first, because
///       `draw_set_halign` cannot know about a gap this function invents.
function draw_text_tracked(_x, _y, _str, _track, _col, _alpha = 1, _thick = 2,
                           _halign = fa_left) {
    var _n = string_length(_str);
    if (_n <= 0) return 0;

    var _w = -_track;
    for (var _i = 1; _i <= _n; _i++) {
        _w += string_width(string_char_at(_str, _i)) + _track;
    }

    var _cx = _x;
    if (_halign == fa_center) _cx -= _w * 0.5;
    else if (_halign == fa_right) _cx -= _w;

    draw_set_halign(fa_left);
    for (var _i = 1; _i <= _n; _i++) {
        var _ch = string_char_at(_str, _i);
        draw_text_outline(_cx, _y, _ch, _col, _alpha, _thick);
        _cx += string_width(_ch) + _track;
    }
    return _w;
}

// ---------------------------------------------------------------------------
// Furniture
// ---------------------------------------------------------------------------

/// @desc A dark panel with a lit edge. The one shape every framed thing in
///       this game is built from.
function draw_panel(_x1, _y1, _x2, _y2, _col, _alpha, _edge = 2) {
    draw_set_alpha(_alpha * 0.72);
    draw_set_colour(COL_VOID);
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    draw_set_alpha(_alpha * 0.9);
    draw_set_colour(_col);
    for (var _i = 0; _i < _edge; _i++) {
        draw_rectangle(_x1 + _i, _y1 + _i, _x2 - _i, _y2 - _i, true);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A number, right-aligned, with an outline. Every counter in the HUD.
function draw_number(_x, _y, _n, _font, _col, _alpha, _pad = 0) {
    var _s = string(_n);
    while (string_length(_s) < _pad) _s = "0" + _s;
    draw_set_font(_font);
    draw_set_halign(fa_right);
    draw_set_valign(fa_middle);
    draw_text_outline(_x, _y, _s, _col, _alpha);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}

/// @desc A scrim across the whole screen. What a pause, a declaration and a
///       result screen all sit on -- and, tinted, what the stage rack washes
///       the world with. `COL_ARCANE` there rather than black, so the scenery
///       reads as seen *through* the interface rather than as a photograph
///       with panels on it.
function draw_scrim(_alpha, _col = c_black) {
    draw_set_alpha(_alpha);
    draw_set_colour(_col);
    draw_rectangle(0, 0, GAME_W, GAME_H, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A band across the screen, dark in the middle and fading out at both
///       ends. What a boss name or a spell name is laid on, so the text has
///       something to sit against without a hard-edged box appearing over the
///       field.
function draw_band(_cy, _h, _alpha, _col = c_black) {
    var _steps = 24;
    // **Across the field, not across the screen.** A band is something laid
    // over the play area for a caption to sit on; run to the screen edges it
    // washes over the HUD margin as well, which puts a dark gradient across
    // the score and the vials every time a spell is declared.
    for (var _i = 0; _i < _steps; _i++) {
        var _t = _i / (_steps - 1);
        var _a = _alpha * (1 - abs(_t - 0.5) * 2);
        draw_set_alpha(_a * _a);
        draw_set_colour(_col);
        draw_rectangle(FIELD_X0 + FIELD_W * _t, _cy - _h * 0.5,
                       FIELD_X0 + FIELD_W * (_t + 1.0 / _steps) + 1,
                       _cy + _h * 0.5, false);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The fascia
//
// **The margin is a surface, not an absence.** For as long as the field had a
// boundary the four margins round it were painted flat `COL_VOID` and left
// there, and photographed at 1:1 that is what came back: a lit picture pasted
// onto a sheet of nothing. It is the same finding `make_bg.py` records about
// the first version of the stage, arriving one layer further out.
//
// What is drawn instead is a dark plate lit from above -- one vertical ramp
// across the *screen's* height, so the four pieces of margin agree with each
// other, plus a tile of mineral glint over the top of it. Neither is bright:
// the console is furniture beside a playfield carrying two thousand lit
// bullets, and every point of value spent here is a point the bullets no
// longer have.
// ---------------------------------------------------------------------------

/// @desc The ramp the whole fascia is lit by, at a height down the screen.
///
///       Sampled from `GAME_H` rather than from the rectangle being filled, so
///       the strip above the field and the column beside it are two windows
///       onto one surface rather than two surfaces that happen to be adjacent.
///
///       **Indigo, and this is where the console stopped being drab.** It was
///       a near-black neutral for two passes, on a rule borrowed from the
///       scenery: every point of value spent on furniture is a point the
///       bullets no longer have. That rule is about *contrast against bullets*
///       and it applies inside the boundary; the fascia is outside it, and a
///       bullet has never had to read against the console. What the borrowing
///       bought was a grey nothing wrapped round a game about a blue imp
///       stealing magic.
///
///       What has to stay low out here is **brightness**, because a bright
///       margin pulls the eye off the field -- and brightness is not the same
///       thing as saturation. A deep indigo at the same value as the old grey
///       is exactly as quiet and reads as a *material* instead of as an
///       absence. See `COL_ARCANE` for why the colour is the player's rather
///       than the stage's.
function fascia_shade(_y) {
    var _t = clamp(_y / GAME_H, 0, 1);
    return merge_colour(merge_colour(COL_VOID, COL_ARCANE, 0.72), COL_VOID,
                        _t * _t * 0.62 + _t * 0.28);
}

/// @desc One rectangle of fascia: the ramp, and the grain over it.
function draw_fascia(_x1, _y1, _x2, _y2) {
    if (_x2 <= _x1 || _y2 <= _y1) return;

    draw_primitive_begin(pr_trianglestrip);
    var _steps = 8;
    for (var _i = 0; _i <= _steps; _i++) {
        var _y = lerp(_y1, _y2, _i / _steps);
        var _c = fascia_shade(_y);
        draw_vertex_colour(_x1, _y, _c, 1);
        draw_vertex_colour(_x2, _y, _c, 1);
    }
    draw_primitive_end();

    draw_grain(_x1, _y1, _x2, _y2, merge_colour(COL_PARCHMENT, COL_RUNE, 0.4),
               0.075);
    fascia_motes(_x1, _y1, _x2, _y2);
}

/// @desc The motes drifting through the fascia.
///
///       **Derived from the clock rather than simulated**, exactly as the
///       stage embers and the vessels bubbles are: each is a phase and a rate,
///       and where it is this frame is `frac` of the two. There is no pool to
///       step and nothing to respawn.
///
///       They are the one thing on the console that moves without being told
///       to, and that is their whole job. A static ornamented panel is a
///       picture of an interface; a panel with something slowly crossing it is
///       a place. They are kept tiny and dim enough that peripheral vision
///       registers motion and nothing else -- anything more would be competing
///       with the danmaku through the boundary.
function fascia_motes(_x1, _y1, _x2, _y2) {
    var _w = _x2 - _x1;
    var _h = _y2 - _y1;
    if (_w < 8 || _h < 8) return;

    gpu_set_blendmode(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 18; _i++) {
        // Seeded off the rectangle so each piece of margin carries its own
        // drift, and off `_i` so no two are in step.
        var _sx = frac(_i * 0.6180339 + _x1 * 0.0013 + _y1 * 0.0007);
        var _p = frac(current_time * (0.000018 + 0.000022 * frac(_i * 0.41))
                      + _i * 0.137 + _sx);
        var _mx = _x1 + _w * _sx;
        var _my = _y2 - _p * (_h + 40) + 20;
        var _a = min(1, _p * 5) * min(1, (1 - _p) * 5)
                 * (0.05 + 0.05 * frac(_i * 0.77));
        var _k = (5 + 5 * frac(_i * 0.31)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _mx, _my, _k, _k, 0,
                        (_i mod 3 == 0) ? COL_RUNE : COL_GILT_LIT, _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc `spr_ui_grain` tiled over a rectangle, additively.
///
///       **Cropped with `draw_sprite_part_ext` rather than clipped**, because
///       there is no clip: the tile is 192 square and almost nothing in this
///       HUD is a multiple of 192, so a whole-tile loop either stops short of
///       the edge or paints over the boundary the mask has just established.
///       Drawing the part of the tile that fits is one call either way.
function draw_grain(_x1, _y1, _x2, _y2, _col, _alpha) {
    if (_alpha <= 0.004) return;
    var _tw = sprite_get_width(spr_ui_grain);
    var _th = sprite_get_height(spr_ui_grain);

    gpu_set_blendmode(bm_add);
    // Phased off the screen origin, not off the rectangle, so the tiling lines
    // up between the margin above the field and the column beside it.
    var _sy = _y1 - (_y1 mod _th);
    while (_sy < _y2) {
        var _sx = _x1 - (_x1 mod _tw);
        var _cy = max(_y1, _sy);
        var _ch = min(_y2, _sy + _th) - _cy;
        while (_sx < _x2) {
            var _cx = max(_x1, _sx);
            var _cw = min(_x2, _sx + _tw) - _cx;
            if (_cw > 0 && _ch > 0) {
                draw_sprite_part_ext(spr_ui_grain, 0, _cx - _sx, _cy - _sy,
                                     _cw, _ch, _cx, _cy, 1, 1, _col, _alpha);
            }
            _sx += _tw;
        }
        _sy += _th;
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The four corner ornaments of a rectangle, drawn from one sprite.
///
///       **One piece, flipped, never four pieces.** Four separately authored
///       corners are four ornaments; the same one at four orientations is a
///       frame. `_out` pushes them outward from the rectangle, which is what
///       keeps the field's own corners off the playfield -- the ornament lives
///       in the margin and points at the picture.
function draw_corners(_x1, _y1, _x2, _y2, _col, _alpha, _out = 0, _scale = 1) {
    if (_alpha <= 0.004) return;
    var _s = _scale;
    for (var _i = 0; _i < 4; _i++) {
        var _fx = (_i == 1 || _i == 3) ? -1 : 1;
        var _fy = (_i >= 2) ? -1 : 1;
        var _px = (_fx > 0) ? (_x1 - _out) : (_x2 + _out);
        var _py = (_fy > 0) ? (_y1 - _out) : (_y2 + _out);
        draw_sprite_ext(spr_ui_corner, 0, _px, _py, _s * _fx, _s * _fy, 0,
                        _col, _alpha);
    }
}

/// @desc A section divider, centred on `_x` and stretched to `_w`.
///
///       **`spr_ui_rule` has a top-left origin**, so a call that wants a
///       centre has to subtract half the width itself. It shipped without
///       that for one screenshot, and the symptom was not a rule that looked
///       off-centre -- it was a rule whose lozenge sat against the console's
///       right edge with half the ornament drawn past it, which reads as the
///       panel having a crack in it rather than as anything being mispositioned.
function draw_rule(_x, _y, _w, _col, _alpha) {
    if (_alpha <= 0.004) return;
    var _sw = sprite_get_width(spr_ui_rule);
    var _sh = sprite_get_height(spr_ui_rule);
    draw_sprite_ext(spr_ui_rule, 0, _x - _w * 0.5, _y - _sh / 2,
                    _w / _sw, 1, 0, _col, _alpha);
}

/// @desc A raised plate: a lifted ground, a lit top edge and a shadowed lower
///       one. What the console is mounted on.
///
///       **Raised rather than recessed, and the two are one line apart.** A
///       recess is lit along its bottom and right; a plate is lit along its
///       top and left, because that is where the light in this fascia comes
///       from. Getting it the wrong way round does not look wrong so much as
///       flat -- the eye reads no relief at all, which is what the flat black
///       margin this replaces already did.
function draw_plate(_x1, _y1, _x2, _y2, _alpha = 1) {
    draw_primitive_begin(pr_trianglestrip);
    var _steps = 8;
    for (var _i = 0; _i <= _steps; _i++) {
        var _y = lerp(_y1, _y2, _i / _steps);
        // A touch lighter than the fascia behind it, at every height, so the
        // plate reads as a plate wherever it is put.
        var _c = merge_colour(fascia_shade(_y), COL_ARCANE_LIT, 0.10);
        draw_vertex_colour(_x1, _y, _c, _alpha);
        draw_vertex_colour(_x2, _y, _c, _alpha);
    }
    draw_primitive_end();

    draw_grain(_x1, _y1, _x2, _y2,
               merge_colour(COL_PARCHMENT, COL_RUNE, 0.4), 0.06 * _alpha);

    // **A gilded edge, not a white one.** The bevel is two hairlines rather
    // than a rectangle outline, because an outline is the same value on all
    // four sides and a plate lit from above is not -- and the lit pair is gold
    // because everything on this console that catches light is gold. A pale
    // grey bevel round a violet plate is the single detail that would make it
    // read as a dialog box.
    draw_set_alpha(_alpha * 0.5);
    draw_set_colour(COL_GILT);
    draw_rectangle(_x1, _y1, _x2, _y1 + 1, false);
    draw_rectangle(_x1, _y1, _x1 + 1, _y2, false);
    draw_set_alpha(_alpha * 0.2);
    draw_rectangle(_x1 + 3, _y1 + 3, _x2 - 3, _y2 - 3, true);
    draw_set_alpha(_alpha * 0.6);
    draw_set_colour(COL_VOID);
    draw_rectangle(_x1, _y2 - 1, _x2, _y2, false);
    draw_rectangle(_x2 - 1, _y1, _x2, _y2, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// The field's boundary
// ---------------------------------------------------------------------------

/// @desc Mask everything outside the field, and draw the frame round it.
///
///       **A mask, not a clip.** GameMaker can be told to scissor, and a
///       surface would do it too; four opaque rectangles do it with no state
///       to restore, nothing to lose on a resize, and no chance of a later
///       draw call escaping the clip because it happened after the reset. The
///       world is drawn across the whole screen and then the parts of it that
///       are not the field are painted out.
///
///       **Called from the GUI event, not from Draw.** Draw carries the screen
///       shake as a world matrix, and a mask that shook would let the world
///       out from behind it along one edge on every hit -- which is a flicker
///       of scenery in the margin at exactly the moment the margin is being
///       read. The GUI event has no matrix, so the boundary is nailed down
///       whatever the field is doing.
///
///       **`_flash` lights the boundary itself, and it is the one piece of
///       damage feedback that costs the player nothing.** A hit already
///       shakes the screen and flashes it white, and both of those make the
///       field momentarily harder to read -- which is defensible once, and is
///       the whole of what the game can say. The frame is the opposite: it is
///       1360 by 992 of outline that no bullet is ever behind, so lighting it
///       red is a message delivered entirely in pixels the player was not
///       using. It is drawn additively over the rule, so it can only ever
///       brighten a border that is already there.
function field_draw_frame(_flash = 0, _flash_col = COL_LIFE) {
    // The margin. Painted as fascia rather than as flat void -- see the note
    // above `fascia_shade`. Still opaque, and still four rectangles: this is
    // the mask, and a mask with a gap in it is a mask that leaks scenery.
    draw_fascia(0, 0, GAME_W, FIELD_Y0 - 1);                        // above
    draw_fascia(0, FIELD_Y1 + 1, GAME_W, GAME_H);                   // below
    draw_fascia(0, FIELD_Y0 - 1, FIELD_X0 - 1, FIELD_Y1 + 1);       // left
    draw_fascia(FIELD_X1 + 1, FIELD_Y0 - 1, GAME_W, FIELD_Y1 + 1);  // right

    // **Light spilling out of the field onto the frame**, drawn inward from
    // each edge. Without it the boundary is a hard line between a lit picture
    // and a dead border, which reads as a screenshot pasted onto a page. With
    // it the field looks like something the margin is a window onto.
    //
    // Drawn as a strip per edge rather than as a blurred sprite, because a
    // gradient a few pixels wide is two triangles and a 1920-wide glow sprite
    // is a texture page.
    gpu_set_blendmode(bm_add);
    // The spill is the field own light leaking out, so it takes the arcane
    // accent rather than a neutral -- a grey glow round a lit picture reads as
    // fog, and this should read as the frame being enchanted.
    var _g = merge_colour(COL_RUNE, COL_ARCANE_LIT, 0.45);
    field_edge_glow(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y0 + FIELD_GLOW,
                    _g, true);     // from the top edge, downward
    field_edge_glow(FIELD_X0, FIELD_Y1, FIELD_X1, FIELD_Y1 - FIELD_GLOW,
                    _g, true);
    field_edge_glow(FIELD_X0, FIELD_Y0, FIELD_X0 + FIELD_GLOW, FIELD_Y1,
                    _g, false);
    field_edge_glow(FIELD_X1, FIELD_Y0, FIELD_X1 - FIELD_GLOW, FIELD_Y1,
                    _g, false);
    gpu_set_blendmode(bm_normal);

    // The rule itself. Two passes: a bright hairline on the field's side and a
    // dimmer one outside it, which is what gives the boundary a thickness
    // without a second colour.
    draw_set_alpha(0.9);
    draw_set_colour(COL_GILT_LIT);
    draw_rectangle(FIELD_X0 - 1, FIELD_Y0 - 1, FIELD_X1 + 1, FIELD_Y1 + 1,
                   true);
    draw_set_alpha(0.5);
    draw_set_colour(COL_GILT);
    for (var _i = 2; _i < 2 + FIELD_EDGE; _i++) {
        draw_rectangle(FIELD_X0 - _i, FIELD_Y0 - _i, FIELD_X1 + _i,
                       FIELD_Y1 + _i, true);
    }

    // **An outer rule, and the corners standing on it.** The boundary on its
    // own is a hairline round a picture; a second rule a few pixels out with
    // ornamented corners is a *frame*, and the margin has the room. Where it
    // runs is derived rather than chosen -- see `FIELD_RULE_OUT` -- because a
    // rule that misses the corner pieces by two pixels reads as a mistake in a
    // way that a rule ten pixels further out would not.
    var _orn = COL_GILT;
    draw_set_alpha(0.55);
    draw_set_colour(_orn);
    draw_rectangle(FIELD_X0 - FIELD_RULE_OUT, FIELD_Y0 - FIELD_RULE_OUT,
                   FIELD_X1 + FIELD_RULE_OUT, FIELD_Y1 + FIELD_RULE_OUT, true);

    // The corners are the one piece of the frame that is a shape rather than a
    // line, and putting them in the margin is what lets them be one without
    // costing the playfield a pixel.
    draw_corners(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, _orn, 0.95,
                 FIELD_ORN_OUT, FIELD_ORN_SCALE);

    // Damage, said on the frame. Three rules of decreasing alpha rather than
    // one thick one, so what travels outward is a *glow* leaving the boundary
    // rather than a red box appearing round it.
    if (_flash > 0.01) {
        gpu_set_blendmode(bm_add);
        draw_set_colour(_flash_col);
        for (var _i = 0; _i < 7; _i++) {
            draw_set_alpha(_flash * 0.5 * (1 - _i / 7));
            draw_rectangle(FIELD_X0 - 1 - _i, FIELD_Y0 - 1 - _i,
                           FIELD_X1 + 1 + _i, FIELD_Y1 + 1 + _i, true);
        }
        gpu_set_blendmode(bm_normal);
        draw_corners(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1,
                     _flash_col, _flash * 0.7, 14, 0.62);
    }

    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc One edge's worth of spill: a strip fading from the boundary inward.
///       `_vertical` means the gradient runs down y rather than across x.
function field_edge_glow(_x0, _y0, _x1, _y1, _col, _vertical) {
    draw_primitive_begin(pr_trianglestrip);
    if (_vertical) {
        draw_vertex_colour(_x0, _y0, _col, 0.16);
        draw_vertex_colour(_x1, _y0, _col, 0.16);
        draw_vertex_colour(_x0, _y1, _col, 0);
        draw_vertex_colour(_x1, _y1, _col, 0);
    } else {
        draw_vertex_colour(_x0, _y0, _col, 0.16);
        draw_vertex_colour(_x0, _y1, _col, 0.16);
        draw_vertex_colour(_x1, _y0, _col, 0);
        draw_vertex_colour(_x1, _y1, _col, 0);
    }
    draw_primitive_end();
}

/// @desc Is this rectangle entirely outside the field?
///
///       **The assertion the fade rule could never be.** With the readouts in
///       a console, "does this box cover the playfield" is a rectangle overlap
///       and `test_hud_layout` checks every box in `hud_box` against it. The
///       old rule -- fade when the player is near -- had no such question: it
///       was true of everything, all the time, to a degree.
function rect_clear_of_field(_x1, _y1, _x2, _y2) {
    return (_x2 <= FIELD_X0) || (_x1 >= FIELD_X1)
        || (_y2 <= FIELD_Y0) || (_y1 >= FIELD_Y1);
}

// ---------------------------------------------------------------------------
// Vessels
//
// **A meter in this game is a glass of something, not a rectangle of colour.**
// The machinery below is lifted from the gauges in the Wordsearch project,
// where the shape of it was worked out, and every comment here that reads like
// a scar is one -- each is a thing that was drawn wrong there first.
//
// The argument for bringing it over is not decoration. A flat bar is read by
// *looking at it*: the eye has to leave the field, find the bar, measure a
// length and come back. A vessel is read peripherally, because the only part
// of it that moves is the surface and the surface is the number. In a genre
// where looking away for a third of a second is how you die, that difference
// is mechanical rather than cosmetic.
//
// **There is one vessel and it lies down.** Life, sigil and the boss's health
// are all `draw_gauge_h`; the upright `draw_gauge_v` is gone. See the note in
// `constants` about why the meters turned on their side.
// ---------------------------------------------------------------------------

// **Nothing in a vessel is a rounded rectangle, the glass included.**
//
// The liquid stopped being one first, because a fill drawn as a roundrect has
// corners of one radius while the glass has corners of another -- and worse, a
// partly full vessel's open end is square: at 100% the old upright meter drew a
// flat-topped body inside a tube with a 66-pixel radius, so the liquid stood
// proud of its own glass by most of a corner.
//
// **That fixed half of it, and the remaining half was the glass.**
// `draw_roundrect_ext` silently clamps its radius. Asked for 26 on a tube 52
// tall it draws about 12, so the trough and its rim were a rounded *rectangle*
// with squarish ends while the liquid inside them was a true stadium -- a dark
// crescent at each corner of the cap where the two shapes disagreed by twelve
// pixels, which is exactly the misalignment this was all supposed to remove and
// is the thing a person looking at the meter actually sees. It reads as the
// liquid being the wrong shape, because the liquid is the part that moves.
//
// So there is one contour and everything is drawn from it: `capsule_half` for
// anything filled along its length, `capsule_ring` for anything outlined. No
// call in this section can be clamped by anything, because none of them hands a
// radius to GameMaker at all.

/// @desc How far the inside of a capsule reaches above and below its centre
///       line at `_x`. Zero outside it.
function capsule_half(_x, _lo, _hi, _r) {
    var _c0 = _lo + _r;
    var _c1 = _hi - _r;
    if (_c1 < _c0) {
        // A capsule shorter than it is tall: the two arcs are all there is.
        var _m = (_lo + _hi) * 0.5;
        _c0 = _m;
        _c1 = _m;
    }
    var _d = 0;
    if (_x < _c0) _d = _c0 - _x;
    else if (_x > _c1) _d = _x - _c1;
    if (_d >= _r) return 0;
    return sqrt(_r * _r - _d * _d);
}

/// @desc The rightmost x the inside of a capsule reaches at `_dy` off its
///       centre line. The same contour read the other way round, for the
///       wavy end, which is sampled down y rather than along x.
function capsule_reach(_dy, _hi, _r) {
    var _a = _r * _r - _dy * _dy;
    return (_hi - _r) + ((_a > 0) ? sqrt(_a) : 0);
}

/// @desc Where to sample a capsule along its length, from `_lo` up to `_to`.
///
///       **Fine inside the caps and coarse across the straight middle**,
///       because that is where the shape is. An evenly spaced walk spends its
///       samples where nothing is happening and crosses a whole cap in one
///       segment -- on the boss's bar that was 30 pixels over a 5-pixel radius,
///       and what it drew was a triangle.
///
///       The positions are returned rather than walked in place because several
///       strips are drawn down the same contour, and a body and a gloss that
///       disagreed about where the edge was would show as a seam.
function capsule_samples(_lo, _hi, _r, _to) {
    var _out = [];
    var _step = max(2, (_to - _lo) / LIQ_BODY_STEPS);
    var _px = _lo;
    while (true) {
        array_push(_out, _px);
        if (_px >= _to - 0.001) break;
        var _in_cap = (_px < _lo + _r) || (_px > _hi - _r - 1);
        _px = min(_to, _px + (_in_cap ? LIQ_CAP_STEP : _step));
    }
    return _out;
}

/// @desc A filled capsule, from its own contour.
function capsule_fill(_x, _y, _w, _h, _col, _alpha) {
    var _r  = _h * 0.5;
    var _lo = _x;
    var _hi = _x + _w;
    var _cy = _y + _r;
    var _xs = capsule_samples(_lo, _hi, _r, _hi);
    var _n  = array_length(_xs);

    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i < _n; _i++) {
        var _px = _xs[_i];
        var _hh = capsule_half(_px, _lo, _hi, _r);
        draw_vertex_colour(_px, _cy - _hh, _col, _alpha);
        draw_vertex_colour(_px, _cy + _hh, _col, _alpha);
    }
    draw_primitive_end();
}

/// @desc A capsule outline: the ring between radius `_ro` and radius `_ri`,
///       around the two cap centres `_cx0` and `_cx1`.
///
///       **A stadium inset by `d` is a stadium with the same cap centres and a
///       radius smaller by `d`**, which is what makes an outline of any
///       thickness one loop rather than two shapes to reconcile. The joins are
///       at exactly 90 and 270 degrees so the straight top and bottom runs come
///       out as single segments between the two caps' corner points.
function capsule_ring(_cx0, _cx1, _cy, _ro, _ri, _col, _alpha, _steps = 12) {
    if (_alpha <= 0.004 || _ro <= 0) return;
    draw_primitive_begin(pr_trianglestrip);
    for (var _half = 0; _half < 2; _half++) {
        var _cx = (_half == 0) ? _cx1 : _cx0;
        var _a0 = (_half == 0) ? -90 : 90;
        for (var _i = 0; _i <= _steps; _i++) {
            var _a = _a0 + (_i * 180 / _steps);
            var _dx = dcos(_a);
            var _dy = -dsin(_a);
            draw_vertex_colour(_cx + _dx * _ro, _cy + _dy * _ro, _col, _alpha);
            draw_vertex_colour(_cx + _dx * _ri, _cy + _dy * _ri, _col, _alpha);
        }
    }
    // **Close onto the point the loop started from, which is the BOTTOM of the
    // right cap.** The walk runs -90 to 90 around the right centre and 90 to
    // 270 around the left, so it starts at the bottom right and ends at the
    // bottom left; closing to the *top* right instead lays one more quad from
    // the bottom-left corner to the top-right one, which is a rim-coloured
    // diagonal band straight across the vessel. It shipped for exactly one
    // screenshot and was reported as "a weird diagonal line through it", which
    // is precisely what it was.
    draw_vertex_colour(_cx1, _cy + _ro, _col, _alpha);
    draw_vertex_colour(_cx1, _cy + _ri, _col, _alpha);
    draw_primitive_end();
}

/// @desc How far the surface is displaced at `_along` pixels across it.
///
///       Two sine waves at unrelated frequencies running in opposite
///       directions, which is the cheapest thing that never visibly repeats.
///       `_slosh` is a nudge from outside -- a hit taken, a sigil spent --
///       that swells the whole surface briefly.
function liquid_wave(_along, _seed, _slosh = 0) {
    var _a = 1 + _slosh * 2.2;
    return dsin(_along * LIQ_WAVE_K1 + current_time * LIQ_WAVE_S1 + _seed)
           * LIQ_WAVE_A1 * _a
         + dsin(_along * LIQ_WAVE_K2 + current_time * LIQ_WAVE_S2
                + _seed * 137) * LIQ_WAVE_A2 * _a;
}

/// @desc A soft round light. Every glow in the HUD goes through this, so the
///       one sprite is scaled in one place.
function draw_bloom(_x, _y, _size, _col, _alpha) {
    if (_alpha <= 0.004) return;
    gpu_set_blendmode(bm_add);
    var _s = _size / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0, _col, _alpha);
    gpu_set_blendmode(bm_normal);
}

/// @desc Bubbles rising through the liquid, between `_bot` and `_surf`.
///
///       **Derived from the clock rather than simulated**, exactly as the
///       background embers are: each bubble is a phase and a rate, and where
///       it is this frame is `frac` of the two. There is no pool to step and
///       nothing to respawn, and a vessel that has been off screen for a
///       minute is already correct on the frame it comes back.
function draw_liquid_bubbles(_x0, _x1, _bot, _surf, _seed, _col, _alpha) {
    if (abs(_bot - _surf) < 12) return;
    if (_x1 - _x0 < 10) return;
    gpu_set_blendmode(bm_add);
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 7; _i++) {
        var _p = frac(current_time * (0.00007 + 0.00005 * frac(_i * 0.37))
                      + _i * 0.143 + _seed * 0.01);
        var _bx = lerp(_x0 + 4, _x1 - 4, frac(_i * 0.61 + _seed * 0.07));
        var _by = lerp(_bot, _surf, _p);
        // Bigger as it rises, and gone before it reaches the surface.
        var _s = (5 + 5 * frac(_i * 0.83)) * (0.6 + 0.7 * _p);
        var _a = _alpha * min(1, _p * 6) * (1 - power(_p, 3));
        var _k = _s / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _bx, _by, _k, _k, 0, _col, _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The glass a gauge is drawn in: the trough and its lengthwise
///       highlight.
function draw_gauge_trough(_x, _y, _w, _h, _alpha) {
    capsule_fill(_x, _y, _w, _h, COL_VOID, _alpha * 0.88);

    // A band down the *length* of the glass, a little in from its lit edge.
    // Written for an upright vessel once and used on a tube, it became a slab
    // standing in the middle of the vessel -- a second half-empty container
    // inside the first. There is only one orientation now, so there is only
    // one band and it cannot be the wrong one.
    //
    // **Inset by a full radius rather than by six pixels.** It is additive, and
    // at six it ran past the cap centres and out through the curved ends -- a
    // faint pale smear on the fascia either side of the glass, which is the one
    // thing a highlight *inside* a vessel must never do.
    var _r = _h * 0.5;
    gpu_set_blendmode(bm_add);
    draw_set_colour(c_white);
    draw_set_alpha(_alpha * 0.06);
    draw_rectangle(_x + _r, _y + _h * 0.15, _x + _w - _r, _y + _h * 0.34,
                   false);
    gpu_set_blendmode(bm_normal);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc The rim of a gauge, drawn **after** what is in it.
///
///       **A vessel's rim is in front of its contents.** The other way round
///       is what leaves the fill with a jagged edge where it meets the rounded
///       end of the glass: `draw_roundrect_ext` tessellates a corner into a
///       fixed number of segments whatever its radius, so the fill's arc and
///       the trough's arc do not agree to the pixel -- and with the rim
///       underneath, the disagreement *is* the outline of the liquid.
function draw_gauge_rim(_x, _y, _w, _h, _ready, _alpha,
                        _col = COL_SILVER) {
    // **A ready rim is the vessel's own hue lit, not white.** White is what
    // every selected control in every menu is drawn in, so a white outline
    // round a meter reads as "this thing has focus" rather than as "there is
    // enough in here to spend" -- and it is the brightest thing on a console
    // that is deliberately dim everywhere else.
    var _rim = _ready
        ? merge_colour(merge_colour(_col, COL_SILVER, 0.45), c_white,
                       0.1 + 0.3 * dsin(current_time * 0.25))
        : COL_SLATE;
    // One ring two pixels thick, from the same contour the liquid is drawn
    // from -- so the rim covers the seam it is there to cover rather than
    // tracing a differently-shaped outline near it.
    var _r = _h * 0.5;
    capsule_ring(_x + _r, _x + _w - _r, _y + _r, _r, _r - 2, _rim,
                 _alpha * (_ready ? 0.9 : 0.78));
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A horizontal tube, filling from the left. Every meter in the game.
///
///       **The liquid is sampled off the glass's contour**, not drawn as a
///       rounded rectangle -- see `capsule_half`, which is where the argument
///       is. The body runs along x and the surface runs down y, so the wave
///       displaces in x: the same `liquid_wave` with its axes swapped, and a
///       meniscus that lurches every time a phase threshold is crossed.
///
///       `_opts`: `ready`, `slosh`, `seed`, `quadrants`, `glow`.
function draw_gauge_h(_x, _y, _w, _h, _fraction, _colour, _alpha, _opts = {}) {
    _fraction = clamp(_fraction, 0, 1);
    if (_alpha <= 0.004) return;

    var _ready = _opts[$ "ready"] ?? false;
    var _slosh = _opts[$ "slosh"] ?? 0;
    var _seed  = _opts[$ "seed"] ?? 0;
    var _glow  = _opts[$ "glow"] ?? 0;
    var _rad   = _h / 2;

    draw_gauge_trough(_x, _y, _w, _h, _alpha);

    // Two pixels, matching the rim drawn over the top of it at the end.
    var _in   = 2;
    var _lo   = _x + _in;                   // the closed end
    var _hi   = _x + _w - _in;
    var _r    = _rad - _in;
    var _cy   = _y + _h * 0.5;
    var _len  = _hi - _lo;
    var _fill = _len * _fraction;
    var _surf = _lo + _fill;

    // **The liquid is dark and the light is a highlight on it**, which is the
    // difference between glass with something in it and a moulded plastic
    // capsule. The first pass had the body running from a 30%-white top edge
    // to a 62%-void bottom and then added a gloss, a meniscus and a bloom over
    // the whole of it: what came back was a pale pink lozenge -- the exact
    // sweet-shop look this HUD is meant to be the opposite of. Every additive
    // pass below is roughly half what it was, and the body's own top edge is
    // now the colour itself rather than a lightened one.
    var _deep = merge_colour(_colour, COL_VOID, 0.80);
    var _lit  = merge_colour(_colour, c_white, 0.16);
    // Even the top of the body is taken down. `COL_LIFE` is a bright pink-red
    // -- it has to be, because it is also what a health shard is drawn in
    // against a lit stage -- and 416 by 52 pixels of it at full saturation is
    // a large bright lozenge on a dark console, which is the sweet-shop look
    // this HUD exists to be the opposite of. The colour still says which meter
    // this is; the *light* on it is what says how full it is.
    var _face = merge_colour(_colour, COL_VOID, 0.22);

    if (_fill > 0.6) {
        // **The wave only exists where there is room for it.** Inside a
        // radius of either end the surface is inside the glass's own rounding,
        // and a strip there is a strip poking out of the vessel -- so a nearly
        // empty tube is a lens in the cap and a nearly full one is simply
        // full, both of which are what those look like anyway.
        var _wavy = (_fill > LIQ_WAVE_AMP + 2)
                    && (_fill < _len - LIQ_WAVE_AMP - 2);
        var _body = _wavy ? (_surf - LIQ_WAVE_AMP) : _surf;

        var _xs = capsule_samples(_lo, _hi, _r, _body);
        var _ns = array_length(_xs);

        // The body. Top edge lit, bottom edge dark: a tube lying on its side
        // has its surface along the *top*, so that is where the light is, and
        // the gradient is per-vertex rather than a second pass over a flat
        // fill. Without it the body is a slab with a wavy end.
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _ns; _i++) {
            var _bx = _xs[_i];
            var _hh = capsule_half(_bx, _lo, _hi, _r);
            draw_vertex_colour(_bx, _cy - _hh, _face, _alpha);
            draw_vertex_colour(_bx, _cy + _hh, _deep, _alpha);
        }
        draw_primitive_end();

        if (_wavy) {
            // The wavy region, between the body and the surface. Sampled down
            // y, because that is the axis the wave displaces across -- and
            // bounded by the contour at `_body`, so the two strips meet on the
            // same edge instead of the second one overshooting the first.
            //
            // **Shaded by depth rather than by distance from the meniscus.**
            // Shading it toward the surface instead put a straight vertical
            // seam a few pixels in from the end of the liquid: two halves of
            // one body of water disagreeing about which way was up.
            var _hb = capsule_half(_body, _lo, _hi, _r);
            draw_primitive_begin(pr_trianglestrip);
            for (var _i = 0; _i <= LIQ_WAVE_STEPS; _i++) {
                var _t = _i / LIQ_WAVE_STEPS;
                var _dy = lerp(-_hb, _hb, _t);
                var _py = _cy + _dy;
                var _sx = clamp(_surf + liquid_wave(_dy + _r, _seed, _slosh),
                                _body, capsule_reach(_dy, _hi, _r));
                var _c = merge_colour(_face, _deep, _t);
                draw_vertex_colour(_body, _py, _c, _alpha);
                draw_vertex_colour(_sx, _py, _c, _alpha);
            }
            draw_primitive_end();

            // The meniscus: a thin bright band riding the wave. Additive, so
            // it reads as the surface catching the light rather than as an
            // edge drawn on.
            gpu_set_blendmode(bm_add);
            draw_primitive_begin(pr_trianglestrip);
            for (var _i = 0; _i <= LIQ_WAVE_STEPS; _i++) {
                var _t = _i / LIQ_WAVE_STEPS;
                var _dy = lerp(-_hb, _hb, _t);
                var _py = _cy + _dy;
                var _sx = clamp(_surf + liquid_wave(_dy + _r, _seed, _slosh),
                                _body, capsule_reach(_dy, _hi, _r));
                draw_vertex_colour(_sx, _py, _lit, _alpha * 0.34);
                draw_vertex_colour(_sx - 7, _py, _lit, 0);
            }
            draw_primitive_end();
            gpu_set_blendmode(bm_normal);
        }

        // A gloss along the ceiling of the tube, following the contour so it
        // curls into the cap rather than ending square inside it. Kept low: at
        // three times this the top went to a pale wash and the bar stopped
        // reading as anything but its own tint.
        gpu_set_blendmode(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i < _ns; _i++) {
            var _gx = _xs[_i];
            var _hh = capsule_half(_gx, _lo, _hi, _r);
            draw_vertex_colour(_gx, _cy - _hh, _lit, _alpha * 0.13);
            draw_vertex_colour(_gx, _cy - _hh * 0.52, _lit, 0);
        }
        draw_primitive_end();
        gpu_set_blendmode(bm_normal);

        // Bubbles rise to the *ceiling* of the tube rather than to the far
        // end, because that is where the top of a liquid is when the vessel is
        // lying down. Passing the tube's own top and bottom as the rise does
        // it.
        draw_liquid_bubbles(_lo, _body, _cy + _r * 0.7, _cy - _r * 0.7, _seed,
                            merge_colour(_colour, c_white, 0.5), _alpha * 0.42);
        draw_bloom(_surf, _cy, _h * 1.5, _colour,
                   _alpha * (0.11 + 0.16 * _slosh + 0.45 * _glow));
    }

    // **The divisions, etched across the glass.** Health is spent a quarter at
    // a time and the sigil is spent a quarter at a time, so the one question
    // either meter is really asked is "how many more" -- and a count is read
    // off marks, not off a length.
    //
    // Drawn over the liquid and under the rim, because a division is a mark in
    // the glass rather than something floating in front of it. **An unreached
    // division has to be visible**, which the Wordsearch version got backwards
    // first: drawn in the trough's own colour, the marks past the liquid were
    // invisible, and the next one along is the whole thing the player is
    // aiming at. So it is etched pale and dim -- a scratch in the glass, which
    // is what it is. Each is trimmed to the contour, so one near the end is
    // short instead of standing out of the cap.
    var _divs = _opts[$ "quadrants"] ?? 0;
    for (var _i = 1; _i < _divs; _i++) {
        var _dx = _lo + _len * (_i / _divs);
        var _hh = capsule_half(_dx, _lo, _hi, _r) * 0.72;
        if (_hh <= 1) continue;
        var _passed = (_fraction >= _i / _divs - 0.001);

        // **Engraved, not painted.** A one-pixel dark line with a one-pixel
        // pale line beside it is a groove cut into the glass; a single bright
        // bar across the liquid is a bar drawn on top of it, and at three
        // quarters full that is what the first version looked like -- three
        // white stripes laid over a pink lozenge. Two pixels of opposed value
        // cost the same and read as tooling.
        draw_set_colour(COL_VOID);
        draw_set_alpha(_alpha * (_passed ? 0.85 : 0.45));
        draw_rectangle(_dx - 2, _cy - _hh, _dx, _cy + _hh, false);
        draw_set_colour(_passed ? merge_colour(_colour, c_white, 0.75)
                                : COL_SILVER);
        draw_set_alpha(_alpha * (_passed ? 0.75 : 0.38));
        draw_rectangle(_dx, _cy - _hh, _dx + 1, _cy + _hh, false);
        draw_set_alpha(1);
    }

    // **A sheen travelling the length of a ready vessel.** The sigil meter
    // answers one question -- is there enough to spend -- and a colour that
    // merely brightens answers it in a way the player has to already be
    // looking to see. Something *moving* along the glass is caught by the
    // periphery, which is the whole argument for a vessel over a bar, applied
    // to the one state the vessel cannot express by its level.
    if (_ready && _fill > 1) {
        var _p = frac(current_time * 0.00035);
        var _sx = lerp(_lo - _h, _lo + _fill + _h, _p);
        gpu_set_blendmode(bm_add);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i <= 10; _i++) {
            var _t = _i / 10;
            var _px = _sx + lerp(-_h * 0.9, _h * 0.9, _t);
            var _hh = capsule_half(_px, _lo, _hi, _r);
            if (_px > _lo + _fill) _hh = 0;
            var _a = _alpha * 0.16 * (1 - abs(_t - 0.5) * 2)
                     * min(1, (1 - _p) * 5) * min(1, _p * 5);
            draw_vertex_colour(_px, _cy - _hh, c_white, _a);
            draw_vertex_colour(_px, _cy + _hh, c_white, 0);
        }
        draw_primitive_end();
        gpu_set_blendmode(bm_normal);
    }

    draw_gauge_rim(_x, _y, _w, _h, _ready, _alpha, _colour);
    draw_set_alpha(1);
    draw_set_colour(c_white);
}
