/// @desc The title screen, which is the stage select ("the rack").

// `rack_list` is every stage plus the extra cards (old stage three, review
// card, drafting table); `stage_n` counts only real stages, for the cleared
// count.
stages = rack_list();
stage_n = array_length(stage_list());
pick = clamp(global.stage_pick, 0, array_length(stages) - 1);
t = 0;
enter_t = 0;          // > 0 while diving into the chosen stage

// Eases toward `pick` for the scrolling animation.
cursor = pick;

bg = bg_brimstone();
