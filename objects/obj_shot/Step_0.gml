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
//
// **Which name it saves under is decided by whether a burst was *asked for*,
// not by how long it is.** The tool looks for `shot_0.png` whenever it passed
// `-burst` and for `shot.png` when it did not, so a burst of exactly one frame
// -- which is a perfectly reasonable thing to ask for, and the shortest way to
// photograph one moment of a long attack -- had the game write one name and
// the tool wait for the other. What came back was "no screenshot", with the
// picture sitting on disk beside the one it was looking for.
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
