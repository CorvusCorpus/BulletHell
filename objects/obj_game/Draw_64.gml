/// @desc The field's frame, the HUD and the ceremony, on the GUI layer (so
///       none of it shakes).

// The boss's health rail is drawn before the frame: the frame's mask covers
// the margins, which cuts off the rail's chains at the field edge and hides
// the rail when it is raised above the field between bosses.
hud_draw_boss_line(hud, self);

// The frame paints the margins opaque (masking the world, which is drawn
// full-screen) and flashes red on damage.
field_draw_frame(hud.life_flare, COL_LIFE);

hud_draw(hud, self);

var _over = (phase == Phase.Won || phase == Phase.Lost);
var _boss = enemy_find_boss();
if (_boss != undefined) {
    if (_boss.boss.declare_t > 0 && _boss.boss.def.final) {
        hud_draw_declare(_boss);
    }
    // Hidden under the practice result panel, which already names the attack
    // (the phase index doesn't change until `clear_t` runs out).
    if (!(_over && practice != undefined)) hud_draw_spell(_boss);

    // The READY count before a practised attack (`phase < 0` only then).
    if (practice != undefined && !_over && _boss.boss.phase < 0
        && _boss.boss.clear_t > 0) {
        hud_draw_practice_ready(_boss);
    }
}

// Szuix's eye card when he bombs; after the boss's so it is on top.
player_draw_card(player);

fx_draw_text();

// The stage name splash over the field for the first 190 frames (the console
// shows the name after that).
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
    if (practice != undefined) hud_draw_practice_result(self);
    else hud_draw_result(self);
}

// The full-screen flash, last (over the HUD too).
fx_draw_flash();
