t++;

var _g = instance_exists(obj_game) ? instance_find(obj_game, 0) : undefined;

// Posed on the second frame, once `obj_game`'s Create has run.
if (!posed && t >= 2) {
    posed = true;
    shutter = 2 + shot_pose(scene, _g);
}

if (posed) shot_tick(scene, _g, t);

// Save each requested frame. `screen_save` writes into the game's save area,
// where `tools/shot.py` collects it. The file name depends on whether
// `-burst` was passed (`shot_N.png`), not on how many frames were requested,
// because that is what `shot.py` looks for (a one-frame burst is still
// `shot_0.png`).
if (posed && fired < array_length(frames)) {
    if (t >= shutter + frames[fired]) {
        screen_save(array_length(global.shot_burst) > 0
                    ? "shot_" + string(fired) + ".png" : "shot.png");
        show_debug_message("SHOT SAVED " + scene + " +"
                           + string(frames[fired]));
        fired++;
        if (fired >= array_length(frames)) game_end();
    }
}
