t++;

var _g = instance_exists(obj_game) ? instance_find(obj_game, 0) : undefined;

// Posed on the second frame rather than the first, so `obj_game`'s Create has
// run and there is a run to pose. On frame one it does not exist yet.
if (!posed && t >= 2) {
    posed = true;
    shutter = 2 + shot_pose(scene, _g);
}

if (posed) shot_tick(scene, _g, t);

// **One shutter, or several.** A burst photographs the same posed scene at
// several frames in one launch -- which is the only way to see whether a
// thing that happens *over time* reads, and the ordinary run is the burst
// with one frame in it. `screen_save` is sandboxed into the game's own save
// area, which is where `tools/shot.py` fetches these from.
if (posed && fired < array_length(frames)) {
    if (t >= shutter + frames[fired]) {
        screen_save(array_length(frames) > 1
                    ? "shot_" + string(fired) + ".png" : "shot.png");
        show_debug_message("SHOT SAVED " + scene + " +"
                           + string(frames[fired]));
        fired++;
        if (fired >= array_length(frames)) game_end();
    }
}
