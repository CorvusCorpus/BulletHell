/// @desc The field's boundary, the HUD and the ceremony. Drawn on the GUI
///       layer, so none of it shakes with the world -- see the note in Draw.

// **The boundary first, because it is a mask.** The world is drawn across the
// whole screen in the Draw event and this paints out everything that is not
// the field, so it has to come before anything that belongs in the margin.
// It is here rather than in Draw for the same reason the HUD is: Draw carries
// the shake matrix, and a mask that shook would let scenery leak into the
// margin along one edge on every hit.
// The frame carries the damage flash, which is the one readout in the game
// drawn entirely in pixels no bullet can ever be behind. See `field_draw_frame`.
field_draw_frame(hud.life_flare, COL_LIFE);

hud_draw(hud, self);

var _over = (phase == Phase.Won || phase == Phase.Lost);
var _boss = enemy_find_boss();
if (_boss != undefined) {
    if (_boss.boss.declare_t > 0 && _boss.boss.def.final) {
        hud_draw_declare(_boss);
    }
    // **The spell's nameplate goes when a practice attempt does.** The phase
    // index does not move until `clear_t` runs out, so the name under the bar
    // is still live for a second and a half after the attack has ended -- and
    // the practice panel announces the same attack across the same field at
    // the same moment. The same words in two places at once reads as a bug
    // rather than as ceremony, which is the rule `hud_draw_spell_name` is
    // already built on; here it is the attack being *over* that makes the
    // second copy stale rather than duplicated.
    if (!(_over && practice != undefined)) hud_draw_spell(_boss);

    // The count before a practised attack opens. `phase < 0` is what separates
    // the beat practice arrives in from any other pause: nothing has named an
    // attack yet. See `hud_draw_practice_ready`.
    if (practice != undefined && !_over && _boss.boss.phase < 0
        && _boss.boss.clear_t > 0) {
        hud_draw_practice_ready(_boss);
    }
    // The name the spell is still going by outlives the banner, and is drawn
    // by `hud_draw` with the rest of the console -- it is one of three things
    // that can occupy the middle block. See `hud_draw_engagement`.
}

fx_draw_text();

// The stage's own name, across the field at the very start. It is the only
// thing on screen for the first two seconds and it is gone before the first
// wave arrives -- the strip above the field carries it from then on, which is
// why this one is a flourish rather than the only place it appears.
if (t < 190) {
    var _a = min(1, t / 24) * min(1, (190 - t) / 34);
    draw_band(FIELD_CY, 260, 0.55 * _a);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(fnt_title());
    draw_text_outline(FIELD_CX, FIELD_CY - 34, def.name, COL_GRAZE, _a, 3);
    draw_set_font(fnt_head());
    draw_text_outline(FIELD_CX, FIELD_CY + 60, def.subtitle, COL_SILVER,
                      _a * 0.8, 2);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

if (phase == Phase.Paused) hud_draw_pause(self);
if (_over) {
    // Two panels for the two things that can be over. See
    // `hud_draw_practice_result` for why the practice one is a menu.
    if (practice != undefined) hud_draw_practice_result(self);
    else hud_draw_result(self);
}

// Last of everything, including over the HUD: a flash the HUD sat on top of
// would read as the HUD lighting up.
fx_draw_flash();
