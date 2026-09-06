t++;

var _g = instance_exists(obj_game) ? instance_find(obj_game, 0) : undefined;

// Posed on the second frame rather than the first, so `obj_game`'s Create has
// run and there is a run to pose. On frame one it does not exist yet.
if (!posed && t >= 2) {
    posed = true;
    shutter = 2 + shot_pose(scene, _g);
}

if (posed) shot_tick(scene, _g, t);

if (posed && t >= shutter) {
    // The window has to have been drawn at least once at the right size, and
    // `screen_save` is sandboxed into the game's own save area -- which is
    // where `tools/shot.py` fetches it from.
    screen_save("shot.png");
    show_debug_message("SHOT SAVED " + scene);
    game_end();
}
