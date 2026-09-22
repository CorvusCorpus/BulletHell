/// @desc The world, back to front. Bullets and lasers draw over the player
///       (so the sprite never hides bullets), and the hitbox draws last. Screen
///       shake is applied as a world matrix here, so the GUI layer doesn't
///       shake.

// Reset the draw state: the previous frame's GUI event may have left alpha or
// colour set (e.g. `text_style`), which would otherwise leak into the world.
draw_set_alpha(1);
draw_set_colour(c_white);

matrix_set(matrix_world,
           matrix_build(global.shake_x, global.shake_y, 0, 0, 0, 0, 1, 1, 1));

bg_draw_back(bg);

// The spell background: over the stage background, under everything else.
spell_bg_draw(spell_style, spell_col, t, spell_fade);

// Every enemy in the pool, bosses included (`enemy_draw`).
enemy_draw();

// Rings are opaque, so they draw before bullets, lasers and the player; they
// can hide the boss but never a bullet.
ring_draw();

item_draw();
pshot_draw();

player_draw_bomb(player);
player_draw(player);
// The invulnerability dial, under the bullets.
player_draw_grace(player);

laser_draw();
bullet_draw();

fx_draw();

// The hitbox last of all, so it is never behind a bullet.
player_draw_hitbox(player);

// The foreground scenery layer (drawn over the field); it fades out with the
// spell background.
bg_draw_front(bg, spell_fade);

matrix_set(matrix_world, matrix_build_identity());
