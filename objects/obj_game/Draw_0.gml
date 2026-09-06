/// @desc The world. Back to front, and the order is load-bearing.
///
/// **Bullets and lasers draw over the player, and the hitbox draws over
/// them.** That is the genre's order and it is right for a reason: what the
/// player must never lose track of is the *bullets*, and a character sprite
/// eighty pixels wide sitting on top of them would hide a dozen. The hitbox is
/// four pixels and has to be findable through anything, so it goes last.
///
/// **Screen shake is a world matrix, not a camera.** The GUI layer must not
/// shake with it -- a health bar that jitters on every hit is unreadable at
/// exactly the moment it is being read -- and a matrix here leaves the GUI
/// event untouched for free, with no view to configure and no surface to own.

// **The frame starts from a known draw state.** The GUI event runs *after*
// this one and is full of things that legitimately leave the alpha and the
// blend colour set -- `text_style` exists to do exactly that -- so without
// this line the first thing drawn in the world inherits whatever the HUD
// finished on one frame earlier. That is a full frame and an event boundary
// away from anything that looks like a cause, which is why it took a
// screenshot to find: the stage-name splash faded its text out and the ground
// layer faded out with it.
draw_set_alpha(1);
draw_set_colour(c_white);

matrix_set(matrix_world,
           matrix_build(global.shake_x, global.shake_y, 0, 0, 0, 0, 1, 1, 1));

bg_draw_back(bg);

// The spell wash goes over the stage and under everything that matters, which
// is the whole point of it: the world stops competing, and the field is the
// only lit thing left.
spell_bg_draw(spell_style, spell_col, t, spell_fade);

// Every enemy on the field, bosses included. **The controller does not pick
// which boss gets drawn** -- it used to, through `boss_ref`, and a boss the run
// had stopped pointing at was drawn by nobody while remaining perfectly able to
// shoot the player. See `enemy_draw`.
enemy_draw();

item_draw();
pshot_draw();

player_draw_bomb(player);
player_draw(player);

laser_draw();
bullet_draw();

fx_draw();

// The hitbox last of all, so it is never behind a bullet.
player_draw_hitbox(player);

// **The near layer stands down for a spell.** It is the one piece of scenery
// drawn *over* the field, so during a declaration it was the only thing left
// competing with the pattern -- the wash underneath it had removed the world
// and the spires were still there, over the top, lit. A background that is
// supposed to work by subtraction cannot have a foreground that opted out.
bg_draw_front(bg, spell_fade);

matrix_set(matrix_world, matrix_build_identity());
