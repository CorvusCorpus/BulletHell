/// @desc Progress: which stages have been cleared, and how well. One result
///       per stage; a clear is permanent.
///
/// Saves are atomic: the new file is written beside the live one and then
/// swapped in, because `file_text_open_write` truncates immediately and a
/// process killed mid-write (a crash, or `tools/shot.py`'s timeout) would
/// otherwise leave a half-written save that loads as "no progress".

#macro SAVE_VERSION 1
#macro SAVE_FILE "progress.json"

function progress_init() {
    global.progress = {
        version: SAVE_VERSION,
        stages: {},     // stage id -> { cleared, best, no_hit, captured }
    };
}

/// @desc Write a struct as JSON, atomically: full temp file, delete, rename,
///       so there is always at least one complete file on disk.
function save_write_json(_name, _data) {
    var _tmp = _name + ".tmp";
    var _f = file_text_open_write(_tmp);
    file_text_write_string(_f, json_stringify(_data));
    file_text_close(_f);

    if (file_exists(_name)) file_delete(_name);
    file_rename(_tmp, _name);
}

/// @desc Read a struct back, preferring the live file and falling back to the
///       temp file (left behind only when the rename didn't happen, so it is
///       the newer save). A live file that doesn't parse is renamed to `.bad`
///       so the next write can't destroy it, and the game carries on unsaved.
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

    // A save from a newer version is left untouched: `progress_save` refuses
    // to write while `progress_readonly` is set.
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

/// @desc One stage's record; an unplayed stage returns a blank record rather
///       than `undefined`.
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

/// @desc File a clear, keeping the best of each field independently.
function progress_record(_id, _tally, _no_hit, _captured) {
    // Runs that aren't stages (practice, drafting table, review card, the old
    // stage three) have an empty id and file nothing. The old stage three is
    // a full run with a boss, so it does reach this line.
    if (_id == "") return;
    var _old = progress_stage(_id);
    global.progress.stages[$ _id] = {
        cleared: true,
        best: max(_old.best, _tally),
        no_hit: _old.no_hit || _no_hit,
        captured: max(_old.captured, _captured),
    };
    progress_save();
}

/// @desc How many stages are cleared.
function progress_cleared_count() {
    var _n = 0;
    var _names = variable_struct_get_names(global.progress.stages);
    for (var _i = 0; _i < array_length(_names); _i++) {
        if (global.progress.stages[$ _names[_i]].cleared) _n++;
    }
    return _n;
}

/// @desc Is this stage playable yet? Unlocking is by number of clears
///       (`needs`), not by clearing a particular stage.
function stage_is_unlocked(_def) {
    return progress_cleared_count() >= _def.needs;
}
