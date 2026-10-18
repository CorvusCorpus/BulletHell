/// @desc The title screen, which is the stage select ("the rack").

// `rack_list` is every stage plus the extra cards (old stage three, review
// card, drafting table); `stage_n` counts only real stages, for the cleared
// count.
stages = rack_list();
stage_n = array_length(stage_list());
pick = clamp(global.stage_pick, 0, array_length(stages) - 1);
t = 0;
enter_t = 0;          // > 0 while diving into the chosen stage

// The rack is a grid: a column for each of the roster's zones (`zone` on each
// def), its stages in order down it, then a column of the extra cards. `pick`
// is an index into `stages`; `col_of` and `row_of` say where it sits.
var _zones = stage_zone_names();
columns = [];
for (var _z = 0; _z < array_length(_zones); _z++) {
    array_push(columns, { name: _zones[_z], items: [] });
}
array_push(columns, { name: "EXTRAS", items: [] });
col_of = array_create(array_length(stages), 0);
row_of = array_create(array_length(stages), 0);
for (var _i = 0; _i < array_length(stages); _i++) {
    var _c = stages[_i][$ "zone"] ?? (array_length(columns) - 1);
    col_of[_i] = _c;
    row_of[_i] = array_length(columns[_c].items);
    array_push(columns[_c].items, _i);
}

bg = bg_brimstone();
