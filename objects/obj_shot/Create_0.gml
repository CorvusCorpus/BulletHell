/// @desc The screenshot harness (`-shot <scene>`): pose a scene, let it run,
///       save a screenshot, and quit.
///
/// Scenes are posed with the game's own functions (`shot_scenes`) and then
/// real frames run. A scene may wind `stage.t` forward; the timeline events
/// still fire through `stage_step` in order.

t = 0;
scene = global.shot_scene;
shutter = 40;           // overwritten per scene, below
posed = false;

// Frame offsets from the scene's shutter to photograph (`[0]` unless
// `-burst` was passed), and how many have been taken.
frames = (array_length(global.shot_burst) > 0) ? global.shot_burst : [0];
fired = 0;
