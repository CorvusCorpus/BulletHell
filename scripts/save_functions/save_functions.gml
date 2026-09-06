/// @desc Progress: which stages have been cleared, and how well.
///
/// **Progress is permanent and a stage is played in isolation.** That is the
/// Cuphead shape rather than the Touhou one -- there is no run that starts at
/// stage one, so there is nothing to lose by failing and nothing to save
/// mid-stage. What is stored is a set of *results*, one per stage, and a
/// stage that has been cleared stays cleared.
///
/// **Saving cannot be allowed to destroy a save.** `file_text_open_write`
/// truncates its target the instant it opens, so every save has a window in
/// which the live file is empty and the new contents are not there yet --
/// and anything that kills the process inside that window leaves a half-
/// written file. A crash does it, a force-quit does it, and so does
/// `tools/shot.py`, which runs the game under a timeout and kills it.
///
/// Worse, reading answers `undefined` for both "there is no file" and "the
/// file is corrupt", and every caller reads that as "nothing saved yet" -- so
/// one interrupted write silently takes every stage clear with it, and the
/// only symptom is progress that was there yesterday and is not there today.
/// This is lifted wholesale from the Wordsearch project, where it happened.
///
/// So a save is built beside the live file and swapped in.

#macro SAVE_VERSION 1
#macro SAVE_FILE "progress.json"

function progress_init() {
    global.progress = {
        version: SAVE_VERSION,
        stages: {},     // stage id -> { cleared, best, no_hit, captured }
    };
}

/// @desc Write a struct as JSON, atomically.
///
///       Full file first, then delete, then rename. Whenever the process dies
///       there is always at least one *complete* file on disk.
function save_write_json(_name, _data) {
    var _tmp = _name + ".tmp";
    var _f = file_text_open_write(_tmp);
    file_text_write_string(_f, json_stringify(_data));
    file_text_close(_f);

    if (file_exists(_name)) file_delete(_name);
    file_rename(_tmp, _name);
}

/// @desc Read a struct back, preferring the live file and falling back to the
///       temp one -- which is the *newer* save, not a scrap, since it is only
///       ever left behind by a rename that did not happen.
///
///       A live file that exists and does not parse is renamed to `.bad`
///       rather than left where the next write would replace it. The game
///       carries on as though there were no save, because refusing to start is
///       worse, but the bytes survive for anyone who wants them.
function save_read_json(_name) {
    var _order = [_name, _name + ".tmp"];
    for (var _i = 0; _i < 2; _i++) {
        var _path = _order[_i];
        if (!file_exists(_path)) continue;

        var _f = file_text_open_read(_path);
        var _s = "";
        while (!file_text_eof(_f)) {
            _s += file_text_read_string(_f);
            file_text_readln(_f);
        }
        file_text_close(_f);

        try {
            var _data = json_parse(_s);
            if (is_struct(_data)) return _data;
        } catch (_e) {
            // Only the live file is worth preserving; a bad temp is a scrap.
            if (_i == 0 && !file_exists(_path + ".bad")) {
                file_rename(_path, _path + ".bad");
            }
        }
    }
    return undefined;
}

function save_delete(_name) {
    if (file_exists(_name)) file_delete(_name);
    if (file_exists(_name + ".tmp")) file_delete(_name + ".tmp");
}

// ---------------------------------------------------------------------------

function progress_load() {
    progress_init();
    var _data = save_read_json(SAVE_FILE);
    if (_data == undefined) return;

    // **A file from a future version is left alone rather than migrated.**
    // The one thing worse than losing a save is a downgrade quietly
    // overwriting one it did not understand. Wordsearch has this same guard
    // and a note that it only half works there, because its writer has no
    // matching check; this one does -- `progress_save` refuses too.
    if (!is_struct(_data) || (_data[$ "version"] ?? 0) > SAVE_VERSION) {
        global.progress_readonly = true;
        return;
    }

    global.progress.version = SAVE_VERSION;
    global.progress.stages = _data[$ "stages"] ?? {};
}

function progress_save() {
    if (global.progress_readonly) return;
    save_write_json(SAVE_FILE, global.progress);
}

/// @desc What is known about one stage. Never `undefined` -- an unplayed stage
///       answers a blank record, so every caller can read the fields without
///       asking whether it exists first.
function progress_stage(_id) {
    var _rec = global.progress.stages[$ _id];
    if (_rec == undefined) {
        return { cleared: false, best: 0, no_hit: false, captured: 0 };
    }
    return _rec;
}

function stage_is_cleared(_id) {
    return progress_stage(_id).cleared;
}

/// @desc File a result. **Keeps the best of each field independently**, so a
///       later sloppy clear cannot take away a no-hit that was earned, and a
///       high-scoring run cannot take away a higher capture count. A record
///       that could go backwards is a record players learn not to trust.
function progress_record(_id, _tally, _no_hit, _captured) {
    var _old = progress_stage(_id);
    global.progress.stages[$ _id] = {
        cleared: true,
        best: max(_old.best, _tally),
        no_hit: _old.no_hit || _no_hit,
        captured: max(_old.captured, _captured),
    };
    progress_save();
}

/// @desc How many stages are cleared. What the title screen counts.
function progress_cleared_count() {
    var _n = 0;
    var _names = variable_struct_get_names(global.progress.stages);
    for (var _i = 0; _i < array_length(_names); _i++) {
        if (global.progress.stages[$ _names[_i]].cleared) _n++;
    }
    return _n;
}

/// @desc Is this stage playable yet?
///
///       **Unlocking is by count, not by chain.** A stage needs N clears
///       behind it rather than one *particular* stage, so a player stuck on
///       one boss can go and beat a different one -- which is the whole reason
///       for choosing this progression over Touhou's, and a strict chain would
///       give it straight back.
function stage_is_unlocked(_def) {
    return progress_cleared_count() >= _def.needs;
}
