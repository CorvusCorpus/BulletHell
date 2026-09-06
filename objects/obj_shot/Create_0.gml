/// @desc Pose a scene, wait for it to arrive, photograph it, and quit.
///
/// **The game poses itself, and it poses itself through its own verbs.** Every
/// scene here reaches its state by calling the same functions play calls --
/// `ziggy_spawn`, `boss_enter_phase`, `player_bomb`, `fire` -- and then lets
/// real frames run. A screenshot of a hand-built state proves only that the
/// renderer works on states the game cannot reach, which is the one thing
/// nobody needs to know.
///
/// The one thing that *is* written directly is the stage's own clock: a scene
/// that wanted the third wave would otherwise have to wait fourteen real
/// seconds for it. Winding `stage.t` forward is a fast-forward through the
/// real timeline rather than a fabricated state -- the events still fire
/// through `stage_step`, in order, doing what they do in play.

t = 0;
scene = global.shot_scene;
shutter = 40;           // overwritten per scene, below
posed = false;
