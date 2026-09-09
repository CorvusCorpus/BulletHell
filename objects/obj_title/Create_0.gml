/// @desc The stage select. **Not a main menu with a stage list inside it** --
///       the stage list *is* the menu, because there is no run to start and no
///       difficulty to pick before one. That is the whole shape of the Cuphead
///       progression this game takes over Touhou's: every stage is a thing you
///       go and do, and the screen that lists them is the game's front door.

// **The rack, not the roster.** `rack_list` is every stage plus the drafting
// table, which is a card that is not a place -- see `stage_drafts`. The count
// under the title is kept separately because it counts *stages*, and a
// scratchpad that could never be cleared would make "0 OF 9" wrong the moment
// it appeared.
stages = rack_list();
stage_n = array_length(stage_list());
pick = clamp(global.stage_pick, 0, array_length(stages) - 1);
t = 0;
enter_t = 0;          // > 0 while diving into the chosen stage

// The card the cursor is on eases toward the pick rather than jumping, so a
// held arrow key reads as travel across a rack instead of as a flicker.
cursor = pick;

bg = bg_brimstone();
