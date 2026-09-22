/// @desc Stage two's background, the Hollow Grove: a wood flown through at
///       night under a moon that turns to blood, built on `bg_corridor`.
///
/// Back to front: the sky and stars, the moon, the far canopy bands, the
/// treeline (the far wood), the ground, floor texture, path, dappled light,
/// the hedgerow ("scrub") on the horizon, ground fog, mist, then the
/// depth-sorted props (trees with hanging charms, trunks with ivy, bushes,
/// boughs overhead, undergrowth), wisps, the opening fog veil and a vignette.
/// The front pass (over the field) is additive only.
///
/// The turn (`bg_set_omen`, over `BG_OMEN_TIME` frames): the stars go out and
/// the mist stills; a shadow crosses the moon and the wood goes dark; the moon
/// comes out red and a ring leaves it; then a red wavefront travels down the
/// corridor toward the camera, and the flight speeds up. The wavefront is a
/// depth (`_b.wave`), so each prop and ground row compares its own z against
/// it and far things turn red first.

// ---------------------------------------------------------------------------
// The stage's backdrop
// ---------------------------------------------------------------------------

/// @desc Build the grove background. The art is luminance only (see
///       `tools/make_grove.py`); every colour is chosen at draw time by
///       lerping a night palette (`*_n`) toward a blood palette (`*_b`).
function bg_grove() {
    var _b = bg_new(undefined, undefined, undefined,
                    make_colour_rgb(9, 14, 22), 0);
    _b.kind = BGKIND_CORRIDOR;

    // Night and blood palettes. Saturated, not grey: darkness is carried by
    // value, not by removing colour.
    _b.air_n    = make_colour_rgb(7, 17, 23);      // the deep of the wood
    _b.air_b    = make_colour_rgb(18, 6, 9);
    _b.sky_n    = make_colour_rgb(17, 50, 68);     // the lit part of the sky
    _b.sky_b    = make_colour_rgb(52, 11, 16);
    _b.haze_n   = make_colour_rgb(34, 122, 140);   // mist with moon in it
    _b.haze_b   = make_colour_rgb(128, 30, 28);
    _b.moon_n   = make_colour_rgb(146, 166, 170);
    _b.moon_b   = make_colour_rgb(196, 44, 32);
    _b.tree_n   = make_colour_rgb(6, 19, 25);      // a silhouette in fog
    _b.tree_b   = make_colour_rgb(21, 8, 11);
    // What distance fades a tree toward: lighter than the trees (aerial
    // perspective).
    _b.fog_n    = make_colour_rgb(22, 66, 80);
    _b.fog_b    = make_colour_rgb(50, 17, 17);
    _b.rim_n    = make_colour_rgb(76, 164, 186);   // moonlight on an edge
    _b.rim_b    = make_colour_rgb(232, 72, 46);
    _b.grnd_n   = make_colour_rgb(9, 22, 21);
    _b.grnd_b   = make_colour_rgb(20, 9, 10);
    _b.moss_n   = make_colour_rgb(26, 62, 46);     // what the ground bands are
    _b.moss_b   = make_colour_rgb(58, 20, 18);
    // The floor texture's brightest value (the texture supplies the rest).
    _b.floor_n  = make_colour_rgb(38, 66, 46);
    _b.floor_b  = make_colour_rgb(54, 21, 18);
    // Ivy is the one green in the wood; it browns with the turn.
    _b.ivy_n    = make_colour_rgb(48, 126, 78);
    _b.ivy_b    = make_colour_rgb(78, 32, 24);
    _b.charm_n  = make_colour_rgb(150, 240, 190);  // a witch-light, cold
    _b.charm_b  = make_colour_rgb(255, 128, 56);
    _b.wisp_n   = make_colour_rgb(104, 232, 202);
    _b.wisp_b   = make_colour_rgb(255, 92, 48);

    _b.dist = 0;
    _b.drift = 0;          // how far the fog has travelled on the wind
    _b.spd = GROVE_SPEED;

    // The opening: 0 is still in the fog, 1 is open (`GROVE_INTRO_TIME`).
    _b.intro = 0;

    // The camera. `swell` multiplies the speed, `rush` is what the world
    // advances by this frame, and `cam_x` / `cam_y` are the yaw and pitch in
    // screen pixels (for `corridor_view`). `spd` is the stage's own flight
    // speed (set by the turn), kept separate from `rush` so it can be
    // checked.
    _b.swell = 1;
    _b.rush = GROVE_SPEED;
    _b.cam_x = 0;
    _b.cam_y = 0;

    // How far the camera has leaned toward the player so far (a lagging copy
    // of the player's position; see `GROVE_LEAN`).
    _b.lean = 0;
    _b.lat = 0;            // ...the same number, once the arrival has eased

    // How much moonlight there is (one number, since the moon is the one
    // source). At totality the mist, rims and floor go dark; only the charms
    // and wisps still glow.
    _b.light = GROVE_NIGHT_LIGHT;

    // The wavefront's depth; beyond the far plane means it hasn't started.
    _b.wave = GROVE_WAVE_Z0 * 4;

    _b.trees = corridor_ring(GROVE_TREE_N, CORRIDOR_Z_NEAR, CORRIDOR_Z_FAR,
                             grove_make_tree);
    // Trunks: tall fragments close to the path that pass the camera.
    _b.trunks = corridor_ring(GROVE_TRUNK_N, CORRIDOR_Z_NEAR - 30,
                              GROVE_TRUNK_Z, grove_make_trunk);
    _b.bushes = corridor_ring(GROVE_BUSH_N, CORRIDOR_Z_NEAR - 40,
                              GROVE_BUSH_Z, grove_make_bush);

    // The undergrowth, out past the trees and back to the far plane.
    _b.verge = corridor_ring(GROVE_VERGE_N, CORRIDOR_Z_NEAR - 20,
                             CORRIDOR_Z_FAR, grove_make_verge);

    // Boughs overhead: props anchored above the camera with the sprite hung
    // downward, so they sweep off the top of the frame as they pass.
    _b.boughs = corridor_ring(GROVE_BOUGH_N, CORRIDOR_Z_NEAR, GROVE_BOUGH_Z,
                              grove_make_bough);

    // One depth-sorted pass over every ring (`corridor_merge_new`).
    _b.merge = corridor_merge_new([_b.trees, _b.trunks, _b.bushes,
                                   _b.boughs, _b.verge]);

    // The struct `corridor_draw_ground` writes each row's colour into.
    _b.grnd_out = { col: c_black, a: 1 };
    return _b;
}

/// @desc Which side of the path (-1 or 1) the prop recycled on lap `_lap`
///       stands on. Laps are taken in pairs, one prop per side, with the
///       hash choosing which goes left; so a side never gets more than two in
///       a row. (Independent random choices left one edge of the frame empty
///       for seconds at a time, and `corridor_hash` is too correlated across
///       consecutive integers to balance it any other way.)
function grove_side(_lap, _salt) {
    var _first = (corridor_hash(floor(_lap / 2), _salt) < 0.5) ? -1 : 1;
    return ((_lap mod 2) == 0) ? _first : -_first;
}

/// @desc Set up a tree for lap `_lap`. Everything comes from `corridor_hash`
///       of the lap, so the wood is the same on every attempt.
function grove_make_tree(_p, _lap) {
    var _side = grove_side(_lap, 11);
    _p.wx = _side * (GROVE_PATH_HALF
                     + corridor_hash(_lap, 23) * (GROVE_TREE_OUT
                                                  - GROVE_PATH_HALF));
    _p.frame = floor(corridor_hash(_lap, 37) * sprite_get_number(spr_scn_tree));
    // Mirrored per side so the lit edge faces the moon in the middle.
    _p.flip = _side;
    _p.a = 0.86 + 0.14 * corridor_hash(_lap, 53);
    _p.scale = 1 + (corridor_hash(_lap, 59) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 67) - 0.5) * 2 * GROVE_VARY_W;

    // A charm hanging from one of its branch tips, or -1 for none (also for
    // frames with no downward-pointing branches; `grove_hang_count`).
    _p.kind = GROVE_KIND_TREE;
    _p.tag = -1;
    var _n = grove_hang_count(_p.frame);
    if (_n > 0 && corridor_hash(_lap, 71) < GROVE_CHARM_ODDS) {
        _p.tag = floor(corridor_hash(_lap, 83)
                       * sprite_get_number(spr_scn_charm));
        _p.hang = floor(corridor_hash(_lap, 97) * _n);    // which branch
        _p.sway = corridor_hash(_lap, 101) * 360;         // the pendulum phase
    }
}

/// @desc Set up a trunk for lap `_lap`.
function grove_make_trunk(_p, _lap) {
    _p.kind = GROVE_KIND_TRUNK;
    var _side = grove_side(_lap, 3);
    _p.frame = floor(corridor_hash(_lap, 27)
                     * sprite_get_number(spr_scn_trunk));
    _p.scale = 1 + (corridor_hash(_lap, 31) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 37) - 0.5) * 2 * GROVE_VARY_W;

    // Placed by its inner edge: `GROVE_TRUNK_HALF` is the clearance the
    // nearest edge keeps from the centre line, so the prop's own half-width
    // is added (trunks vary in width).
    var _hw = corridor_prop_half_w(spr_scn_trunk, GROVE_TRUNK_H,
                                   _p.scale, _p.aspect);
    _p.wx = _side * (GROVE_TRUNK_HALF + _hw
                     + corridor_hash(_lap, 13) * GROVE_TRUNK_OUT);
    _p.flip = _side;
    _p.a = 1;
    // Ivy on about half of them, at its own height up the trunk.
    _p.tag = (corridor_hash(_lap, 39) < 0.55)
             ? floor(corridor_hash(_lap, 47) * sprite_get_number(spr_scn_leaf))
             : -1;
    _p.sway = 0.18 + corridor_hash(_lap, 51) * 0.55;   // how far up it is
}

function grove_make_bush(_p, _lap) {
    _p.kind = GROVE_KIND_BUSH;
    var _side = grove_side(_lap, 7);
    _p.wx = _side * (140 + corridor_hash(_lap, 19) * 1000);
    _p.frame = floor(corridor_hash(_lap, 29) * sprite_get_number(spr_scn_bush));
    _p.flip = (corridor_hash(_lap, 43) < 0.5) ? -1 : 1;
    _p.a = 0.74 + 0.26 * corridor_hash(_lap, 59);
    _p.scale = 1 + (corridor_hash(_lap, 71) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 79) - 0.5) * 2 * GROVE_VARY_W;
}

/// @desc Set up an undergrowth clump for lap `_lap`. Its distance from the
///       path is biased outward (a power below 1), since clumps near the path
///       leave the frame almost at once.
function grove_make_verge(_p, _lap) {
    _p.kind = GROVE_KIND_VERGE;
    var _side = grove_side(_lap, 9);
    _p.wx = _side * (GROVE_VERGE_IN
                     + power(corridor_hash(_lap, 17), 0.55)
                       * (GROVE_VERGE_OUT - GROVE_VERGE_IN));
    _p.frame = floor(corridor_hash(_lap, 33)
                     * sprite_get_number(spr_scn_brush));
    _p.flip = (corridor_hash(_lap, 41) < 0.5) ? -1 : 1;
    _p.a = 0.78 + 0.22 * corridor_hash(_lap, 57);
    // More size variation than other props.
    _p.scale = 1 + (corridor_hash(_lap, 63) - 0.5) * 2 * GROVE_VARY_H * 1.8;
    _p.aspect = 1 + (corridor_hash(_lap, 73) - 0.5) * 2 * GROVE_VARY_W;
    _p.tag = -1;
}

/// @desc Set up a bough for lap `_lap`.
function grove_make_bough(_p, _lap) {
    _p.kind = GROVE_KIND_BOUGH;
    _p.frame = floor(corridor_hash(_lap, 15)
                     * sprite_get_number(spr_scn_bough));
    _p.flip = (corridor_hash(_lap, 25) < 0.5) ? -1 : 1;
    _p.a = 0.80 + 0.20 * corridor_hash(_lap, 35);
    _p.scale = 1 + (corridor_hash(_lap, 45) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 55) - 0.5) * 2 * GROVE_VARY_W;
    // Either side of the moon, never across it, placed by its inner edge
    // (`GROVE_BOUGH_IN`).
    var _hw = corridor_prop_half_w(spr_scn_bough, GROVE_BOUGH_H,
                                   _p.scale, _p.aspect);
    _p.wx = grove_side(_lap, 5)
            * (GROVE_BOUGH_IN + _hw
               + corridor_hash(_lap, 61) * (GROVE_BOUGH_OUT - GROVE_BOUGH_IN));
    // How far above the camera it hangs: a narrow range, high up, so the
    // boughs stay at the top of the frame.
    _p.hang = GROVE_BOUGH_UP * (0.85 + 0.40 * corridor_hash(_lap, 65));
    _p.tag = -1;
}

// ---------------------------------------------------------------------------
// The clock
// ---------------------------------------------------------------------------

function grove_step(_b) {
    _b.t++;

    // The opening eases in: it drives the speed, the fog veil and how much of
    // the camera movement applies.
    if (_b.intro < 1) _b.intro = min(1, _b.intro + 1 / GROVE_INTRO_TIME);
    var _in = grove_ease(_b.intro);

    // The speed and the light follow the (eased) turn.
    var _e = grove_ease(_b.omen);
    _b.spd = lerp(GROVE_SPEED, GROVE_SPEED_FAST, _e)
             * lerp(GROVE_INTRO_SPD, 1, _in);
    _b.light = GROVE_NIGHT_LIGHT * (1 - 0.80 * grove_totality(_b));

    // The swell: a slow sinusoid on the speed (`GROVE_SWELL`), applied to
    // `rush` rather than `spd`.
    _b.swell = 1 + GROVE_SWELL_SURGE * dsin(_b.t * 360 / GROVE_SWELL) * _in;
    _b.rush = _b.spd * _b.swell;

    // A slow wander in yaw and pitch, two periods per axis with no shared
    // factors, so it never repeats.
    var _meander = GROVE_SWAY * _in
                   * (0.72 * dsin(_b.t * 360 / GROVE_SWAY_P1)
                      + 0.28 * dsin(_b.t * 360 / GROVE_SWAY_P2 + 47));

    // Leaning toward the player's side of the field (`GROVE_LEAN`): eased
    // and capped per frame, so dodging doesn't shake the camera.
    var _want = GROVE_LEAN * _b.aim * _in;
    _b.lean += clamp((_want - _b.lean) * GROVE_LEAN_EASE,
                     -GROVE_LEAN_SPD, GROVE_LEAN_SPD);

    // The lean is a sideways slide (parallax, via `lat`); the wander is a
    // yaw (`cam_x`).
    _b.lat = _b.lean;
    _b.cam_x = _meander;
    _b.cam_y = GROVE_RISE * _in
               * (0.74 * dsin(_b.t * 360 / GROVE_RISE_P1 + 23)
                  + 0.26 * dsin(_b.t * 360 / GROVE_RISE_P2 + 131));

    _b.dist += _b.rush;
    // The wind; only the mist drifts (everything else rooted is fixed to the
    // camera, `grove_rooted_x`).
    _b.drift += _b.rush * 0.10;

    // Step every ring (`test_corridor` checks each ring recycles).
    corridor_ring_step(_b.trees, _b.rush);
    corridor_ring_step(_b.trunks, _b.rush);
    corridor_ring_step(_b.bushes, _b.rush);
    corridor_ring_step(_b.boughs, _b.rush);
    corridor_ring_step(_b.verge, _b.rush);

    // The wavefront launches at totality and runs the corridor's whole depth.
    var _w = grove_wave_t(_b);
    _b.wave = (_w <= 0) ? GROVE_WAVE_Z0 * 4
                        : GROVE_WAVE_Z0 * (1 - _w) - GROVE_WAVE_FEATHER;
}

/// @desc The eased turn, 0..1. Slow at both ends.
function grove_ease(_o) {
    return _o * _o * (3 - 2 * _o);
}

/// @desc How far through the wavefront's own travel the turn is, 0..1.
///       Negative before it launches.
function grove_wave_t(_b) {
    if (_b.omen <= GROVE_WAVE_START) return 0;
    return (_b.omen - GROVE_WAVE_START) / (1 - GROVE_WAVE_START);
}

/// @desc 0..1: how red something at depth `_z` has become (the wavefront has
///       passed it).
function grove_blood_at(_b, _z) {
    return clamp((_z - _b.wave) / GROVE_WAVE_FEATHER, 0, 1);
}

/// @desc 0..1: a bump where the wavefront is passing depth `_z` (charms flare
///       as it reaches them).
function grove_flare_at(_b, _z) {
    if (_b.wave > GROVE_WAVE_Z0 * 2) return 0;
    return clamp(1 - abs(_z - _b.wave) / GROVE_WAVE_FLARE, 0, 1);
}

/// @desc 0..1: how total the eclipse is, peaking half way through the
///       shadow's transit.
function grove_totality(_b) {
    return clamp(1 - abs(grove_eclipse(_b) - 0.5) * 4.4, 0, 1);
}

/// @desc Darken a colour by the current moonlight (`_b.light`). Used on
///       everything the moon lights.
function grove_dim(_b, _col, _blood) {
    return merge_colour(_col, merge_colour(_b.air_n, _b.air_b, _blood),
                        1 - _b.light);
}

/// @desc The shadow's transit across the moon, 0..1 (half is totality).
function grove_eclipse(_b) {
    return clamp(_b.omen / GROVE_WAVE_START, 0, 1);
}

/// @desc How far the sky, moon and stars have turned red. These follow the
///       turn directly rather than the wavefront, since they are at infinity.
function grove_sky_blood(_b) {
    return grove_ease(clamp((_b.omen - 0.18) / 0.34, 0, 1));
}

// ---------------------------------------------------------------------------
// Drawing: behind the field
// ---------------------------------------------------------------------------

function grove_draw_back(_b, _fill) {
    // The view carries the camera's yaw, pitch and slide.
    var _v = corridor_view(_fill, _b.cam_x, _b.cam_y, _b.lat);
    var _sb = grove_sky_blood(_b);

    draw_clear(merge_colour(_b.air_n, _b.air_b, _sb));

    grove_draw_sky(_b, _v, _sb);
    grove_draw_moon(_b, _v, _sb);
    grove_draw_horizon_glow(_b, _v, _sb);

    // The far canopy: two bands across the top, over the sky and under
    // everything else, at two depths.
    var _tree_far = merge_colour(_b.tree_n, _b.tree_b, _sb);
    var _csc = _v.w / sprite_get_width(spr_scn_canopy);
    // Rooted to the camera (they only move when it turns or slides). The
    // passing boughs are what move overhead.
    corridor_draw_band(_v, spr_scn_canopy, grove_rooted_x(_v, 0, 1300),
                       _v.y0 + _v.oy,
                       _csc, merge_colour(_tree_far, _b.fog_n, 0.42), 0.9);
    corridor_draw_band(_v, spr_scn_canopy, grove_rooted_x(_v, 317, 700),
                       _v.y0 + _v.oy - _v.h * 0.06, _csc * 1.34, _tree_far, 1);

    grove_draw_treeline(_b, _v, _sb);
    corridor_draw_ground(_v, _b, grove_ground_shade, _b.grnd_out);
    grove_draw_floor(_b, _v);
    grove_draw_path(_b, _v);
    grove_draw_dapple(_b, _v, _sb);
    // The hedgerow is drawn over the floor, which lets it break up the
    // horizon line.
    grove_draw_scrub(_b, _v, _sb);
    grove_draw_ground_fog(_b, _v, _sb);
    grove_draw_mist(_b, _v, _sb, false);

    // All props, far to near, in one merged pass.
    corridor_merge_step(_b.merge);
    for (var _i = 0; _i < _b.merge.total; _i++) {
        grove_draw_one(_b, _v, _b.merge.out[_i]);
    }

    grove_draw_wisps(_b, _v, 40, 3200, 15.0, 0.46);
    // The veil goes under the vignette so the corners stay dark.
    grove_draw_veil(_b, _v, _sb);
    grove_draw_vignette(_b, _v);
}

/// @desc The opening fog. The stage starts in fog and nearly still; the fog
///       lifts as the flight speeds up (both driven by `intro`). Opaque, which
///       is fine in the back pass (bullets draw over it, and none have been
///       fired yet). The moon shows through as a bloom.
function grove_draw_veil(_b, _v, _sb) {
    if (_b.intro >= 1) return;
    // Stays dense at first, then thins.
    var _a = power(1 - _b.intro, 1.35);

    draw_set_colour(grove_dim(_b, merge_colour(_b.fog_n, _b.fog_b, _sb), _sb));
    draw_set_alpha(_a);
    draw_rectangle(_v.x0, _v.y0, _v.x1, _v.y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    // The moon's glow through the fog, growing as the fog clears.
    var _bw = sprite_get_width(spr_fx_bloom);
    var _sz = _v.w * (1.5 - 0.6 * _b.intro) / _bw;
    gpu_set_blendmode(bm_add);
    draw_sprite_ext(spr_fx_bloom, 0, _v.cx,
                    corridor_horizon(_v) - GROVE_MOON_RISE, _sz, _sz * 0.5, 0,
                    merge_colour(_b.moon_n, _b.moon_b, _sb), _a * 0.30);
    gpu_set_blendmode(bm_normal);
}

/// @desc The hedgerow along the horizon: two rows of `spr_scn_scrub` drawn
///       over the ground, each as a mass and an additive moonward rim. It
///       breaks up the straight line where the ground meets the far wood,
///       crosses the foot of the moon, and dips where the path meets it
///       (`GROVE_SCRUB_DIP`).
function grove_draw_scrub(_b, _v, _sb) {
    var _hy = corridor_horizon(_v);
    var _blood = grove_blood_at(_b, 2400);
    // The far row is closer to the fog colour. Sized to read as a silhouette
    // against the moon.
    grove_scrub_row(_b, _v, _hy, grove_rooted_x(_v, 311, 3000),
                    GROVE_SCRUB_FAR, 0.70, _blood, 91);
    grove_scrub_row(_b, _v, _hy, grove_rooted_x(_v, 0, 2000),
                    GROVE_SCRUB_NEAR, 0.34, _blood, 47);
}

/// @desc The tiling offset for a band rooted to the camera: `_phase` (so two
///       copies of a sprite don't line up), minus the camera's yaw, plus
///       `corridor_k(_z)` of its sideways slide, which gives each band
///       parallax by its depth `_z`. Rooted bands never drift on their own:
///       a far wood or canopy sliding sideways while the camera flies straight
///       reads wrong. Only the mist drifts. (`check_bands_are_rooted`.)
function grove_rooted_x(_v, _phase = 0, _z = CORRIDOR_Z_FAR) {
    return _phase - _v.ox + corridor_k(_z) * _v.lat;
}

/// @desc One hedgerow row: the mass, then the rim on its crown. `_k` is the
///       row's size relative to the band's width.
function grove_scrub_row(_b, _v, _hy, _drift, _k, _fog, _blood, _seed) {
    var _sc = _v.w / sprite_get_width(spr_scn_scrub) * _k;
    var _h = sprite_get_height(spr_scn_scrub) * _sc;
    // `GROVE_SCRUB_RISE` places the band so its crown covers the horizon
    // (`check_scrub_covers_horizon`); its foot is faded out in the art.
    var _sy = _hy - _h * GROVE_SCRUB_RISE;

    var _col = grove_dim(_b, merge_colour(
        merge_colour(_b.tree_n, _b.tree_b, _blood),
        merge_colour(_b.fog_n, _b.fog_b, _blood), _fog), _blood);
    corridor_draw_band_wave(_v, spr_scn_scrub, _drift, _sy, _sc, _col, 1,
                            GROVE_SCRUB_WAVE, _seed, GROVE_SCRUB_DIP,
                            GROVE_SCRUB_DIP_W);

    // The rim sprite is half resolution; its scale is derived from the two
    // widths.
    var _rs = _sc * sprite_get_width(spr_scn_scrub)
              / sprite_get_width(spr_scn_scrub_rim);
    var _rim = grove_dim(_b, merge_colour(_b.rim_n, _b.rim_b, _blood), _blood);
    gpu_set_blendmode(bm_add);
    corridor_draw_band_wave(_v, spr_scn_scrub_rim, _drift, _sy, _rs, _rim,
                            (0.30 + 0.26 * (1 - _fog)) * _b.light,
                            GROVE_SCRUB_WAVE, _seed, GROVE_SCRUB_DIP,
                            GROVE_SCRUB_DIP_W);
    gpu_set_blendmode(bm_normal);
}

/// @desc The sky: a vertical gradient strip, and stars that fade out as the
///       eclipse begins (positions from `corridor_hash`).
function grove_draw_sky(_b, _v, _sb) {
    var _hy = corridor_horizon(_v);
    var _top = merge_colour(_b.air_n, _b.air_b, _sb);
    var _lit = grove_dim(_b, merge_colour(_b.sky_n, _b.sky_b, _sb), _sb);

    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(_v.x0, _v.y0, _top, 1);
    draw_vertex_colour(_v.x1, _v.y0, _top, 1);
    draw_vertex_colour(_v.x0, _hy, _lit, 1);
    draw_vertex_colour(_v.x1, _hy, _lit, 1);
    draw_primitive_end();
    draw_set_alpha(1);
    draw_set_colour(c_white);

    var _a = (1 - grove_eclipse(_b)) * 0.5;
    if (_a <= 0.01) return;
    var _sw = sprite_get_width(spr_fx_bloom);
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 90; _i++) {
        var _x = _v.x0 + corridor_hash(_i, 3) * _v.w;
        var _y = _v.y0 + corridor_hash(_i, 5) * (_hy - _v.y0) * 0.94;
        var _s = (3 + 5 * corridor_hash(_i, 7)) / _sw;
        // Each twinkles at its own rate.
        var _tw = 0.55 + 0.45 * dsin(_b.t * (0.5 + corridor_hash(_i, 13))
                                     + _i * 47);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        make_colour_rgb(206, 224, 236), _a * _tw);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The moon (additive), its corona, and the eclipse. The shadow is drawn
///       by redrawing the moon in vertical slices of its own sprite with a
///       per-slice alpha (a soft band sweeping left to right), so it only ever
///       covers the moon; it is copper-red, as in a real total eclipse.
///
///       Two approaches that failed: `bm_subtract` drew a grey rectangle
///       (the subtract blend ignores source alpha, and the PNG's transparent
///       pixels still hold colour), and a black disc darkened the sky around
///       the moon as well.
function grove_draw_moon(_b, _v, _sb) {
    var _cx = _v.cx;
    var _cy = corridor_horizon(_v) - GROVE_MOON_RISE;
    var _r = GROVE_MOON_R * (_v.w / FIELD_W);
    var _col = merge_colour(_b.moon_n, _b.moon_b, _sb);
    var _ecl = grove_eclipse(_b);
    var _total = clamp(1 - abs(_ecl - 0.5) * 4.4, 0, 1);

    gpu_set_blendmode(bm_add);

    // The corona shrinks during the eclipse and returns larger and redder.
    var _bw = sprite_get_width(spr_fx_bloom);
    var _cs = _r * (7.0 - 4.4 * _total) * (1 + 0.30 * _sb) / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _cx, _cy, _cs, _cs, 0, _col,
                    (0.15 + 0.13 * _sb) * (1 - _total * 0.86)
                    * (0.9 + 0.1 * dsin(_b.t * 0.7)));

    var _ms = _r * 2 / sprite_get_width(spr_scn_moon);
    draw_sprite_ext(spr_scn_moon, 0, _cx, _cy, _ms, _ms, 0, _col,
                    0.80 * (1 + 0.25 * _sb));

    // The shadow: one pass, left to right.
    if (_ecl > 0 && _ecl < 1) {
        gpu_set_blendmode(bm_normal);
        var _ramp = _r * GROVE_UMBRA_RAMP;
        var _half = _r + _ramp;              // so it covers exactly at totality
        var _c0 = _cx + (_ecl * 2 - 1) * (2 * _r + _ramp);
        var _sw = sprite_get_width(spr_scn_moon);
        var _sh = sprite_get_height(spr_scn_moon);
        var _step = _sw / GROVE_UMBRA_SLICES;
        for (var _i = 0; _i < GROVE_UMBRA_SLICES; _i++) {
            var _u0 = _i / GROVE_UMBRA_SLICES;
            var _x0 = _cx - _r + _u0 * _r * 2;
            var _mid = _x0 + _r / GROVE_UMBRA_SLICES;
            var _sa = clamp((_mid - (_c0 - _half)) / _ramp, 0, 1)
                      * clamp(((_c0 + _half) - _mid) / _ramp, 0, 1);
            if (_sa <= 0.008) continue;
            draw_sprite_part_ext(spr_scn_moon, 0, _i * _step, 0, _step, _sh,
                                 _x0, _cy - _r, (_r * 2) / _sw, (_r * 2) / _sh,
                                 GROVE_UMBRA_COL, _sa * 0.96);
        }
        gpu_set_blendmode(bm_add);
        // The rim of light round the moon at totality.
        if (_total > 0.01) {
            var _rs = _r * 2.16 / sprite_get_width(spr_fx_ring);
            draw_sprite_ext(spr_fx_ring, 0, _cx, _cy, _rs, _rs, 0,
                            merge_colour(_col, _b.moon_b, 0.8), _total * 0.55);
        }
    }

    // A ring leaving the moon as it comes out of the shadow...
    var _w = grove_wave_t(_b);
    if (_w > 0 && _w < 0.62) {
        var _p = _w / 0.62;
        var _rr = (_r + _p * _v.w * 1.5) * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _cx, _cy, _rr, _rr, 0, _b.moon_b,
                        (1 - _p) * 0.42);
        // ...and a brief red flash over the view.
        if (_p < 0.14) {
            draw_set_alpha((1 - _p / 0.14) * 0.22);
            draw_set_colour(_b.moon_b);
            draw_rectangle(_v.x0, _v.y0, _v.x1, _v.y1, false);
            draw_set_alpha(1);
            draw_set_colour(c_white);
        }
    }

    gpu_set_blendmode(bm_normal);
}

/// @desc The moon's light spread along the horizon, so the far wood has
///       something to be silhouetted against.
function grove_draw_horizon_glow(_b, _v, _sb) {
    var _hy = corridor_horizon(_v);
    var _col = merge_colour(_b.haze_n, _b.haze_b, _sb);
    var _bw = sprite_get_width(spr_fx_bloom);
    gpu_set_blendmode(bm_add);
    draw_sprite_ext(spr_fx_bloom, 0, _v.cx, _hy - 10,
                    _v.w * 2.4 / _bw, _v.h * 0.62 / _bw, 0, _col,
                    (0.15 + 0.08 * _sb) * _b.light);
    draw_sprite_ext(spr_fx_bloom, 0, _v.cx, _hy - GROVE_MOON_RISE,
                    _v.w * 0.9 / _bw, _v.h * 0.30 / _bw, 0, _col,
                    (0.11 + 0.06 * _sb) * _b.light);
    gpu_set_blendmode(bm_normal);
}

/// @desc The far wood on the horizon: two copies of `spr_scn_treeline` at two
///       scales, opaque, rooted to the camera, each with an undulating
///       baseline (different amplitudes and seeds, so the two don't line up).
function grove_draw_treeline(_b, _v, _sb) {
    var _hy = corridor_horizon(_v);
    var _far = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _sb),
                            _b.air_n, 0.55);
    var _near = merge_colour(_b.tree_n, _b.tree_b, _sb);
    var _sc = _v.w / sprite_get_width(spr_scn_treeline);
    var _h = sprite_get_height(spr_scn_treeline) * _sc;

    corridor_draw_band_wave(_v, spr_scn_treeline, grove_rooted_x(_v, 0, 5200),
                            _hy - _h * 0.92, _sc * 0.92, _far, 1,
                            GROVE_RIDGE_H, 137);
    corridor_draw_band_wave(_v, spr_scn_treeline, grove_rooted_x(_v, 611, 3400),
                            _hy - _h * 1.16 + 8, _sc * 1.16, _near, 1,
                            GROVE_RIDGE_H * 0.62, 313);
}

/// @desc The ground colour at depth `_z` (the shade function for
///       `corridor_draw_ground`): faint bands of moss periodic in depth,
///       fading into the sky colour toward the horizon (so the ground meets
///       the sky without a visible line), and darker near the camera. Now
///       mostly the air under the floor texture.
function grove_ground_shade(_b, _z, _out, _step) {
    var _blood = grove_blood_at(_b, _z);
    var _base = merge_colour(_b.grnd_n, _b.grnd_b, _blood);
    var _moss = merge_colour(_b.moss_n, _b.moss_b, _blood);

    // The bands fade out with distance.
    var _k = corridor_haze(_z);

    // Two unrelated periods (one alone reads as water). Each fades out once a
    // row covers more than half its period, to avoid aliasing flicker.
    var _p1 = GROVE_GROUND_BAND;
    var _p2 = GROVE_GROUND_BAND * 0.31;
    var _n1 = clamp(_p1 / max(0.001, _step * 2), 0, 1);
    var _n2 = clamp(_p2 / max(0.001, _step * 2), 0, 1);
    var _c1 = 0.5 - 0.5 * dcos(((_z + _b.dist) / _p1) * 360);
    var _c2 = 0.5 - 0.5 * dcos(((_z + _b.dist) / _p2) * 360);
    // Kept faint.
    var _band = (power(_c1, 2.4) * 0.66 * _n1
                 + power(_c2, 2.8) * 0.34 * _n2) * _k * 0.24;

    // Darker near the camera.
    var _near = clamp((600 - _z) / 420, 0, 1);

    // Toward the horizon the ground fades to the sky's own colour, so the two
    // meet without a step.
    _out.col = grove_dim(_b, merge_colour(
        merge_colour(merge_colour(_base, _moss, _band),
                     merge_colour(_b.sky_n, _b.sky_b, _blood),
                     power(1 - _k, 1.3)),
        merge_colour(_b.air_n, _b.air_b, _blood),
        _near * 0.55), _blood);
    // Opaque: a translucent ground let the lower half of the moon show
    // through below the horizon.
    _out.a = 1;
}

/// @desc The forest floor: one tile of litter, roots and moss (periodic in
///       both axes; `make_floor`) laid down the corridor in bands of
///       `GROVE_FLOOR_ROW` screen pixels, each tiled sideways at its own
///       scale. Coarser copies of the tile (a hand-made mip chain,
///       `GROVE_FLOOR_MIPS`) are cross-faded in with distance to avoid
///       aliasing; the floor fades into the haze beyond that.
function grove_draw_floor(_b, _v) {
    var _hy = corridor_horizon(_v);
    var _th = sprite_get_height(spr_scn_floor);

    // Bottom to top.
    var _y = _v.y1;
    var _guard = 0;
    while (_y > _hy + 2 && _guard++ < 90) {
        var _y1 = _y;                          // the near edge of this band
        var _y0 = max(_hy + 2, _y - GROVE_FLOOR_ROW);
        _y = _y0;
        var _zn = corridor_depth_at(_v, _y1);
        var _zf = corridor_depth_at(_v, _y0);
        var _span = _zf - _zn;
        if (_span <= 0) continue;

        // Opaque, except for fading with distance.
        var _zm = (_zn + _zf) * 0.5;
        var _a = corridor_haze(_zm);
        if (_a <= 0.01) continue;

        var _blood = grove_blood_at(_b, _zm);
        var _near = clamp((600 - _zm) / 420, 0, 1);
        // Tinted by the floor's brightest value; the texture supplies the
        // darker values.
        var _col = grove_dim(_b,
            merge_colour(merge_colour(_b.floor_n, _b.floor_b, _blood),
                         merge_colour(_b.air_n, _b.air_b, _blood),
                         _near * 0.42), _blood);

        // Which mip level this band wants; the two neighbouring levels are
        // cross-faded.
        var _lvl = clamp(log2(max(0.001, _span)
                              / (GROVE_FLOOR_Z * GROVE_FLOOR_NYQ)),
                         0, GROVE_FLOOR_MIPS);
        var _l0 = floor(_lvl);
        var _mix = _lvl - _l0;
        grove_floor_level(_b, _v, _y0, _y1, _zn, _zf, _l0, _col,
                          _a * (1 - _mix));
        grove_floor_level(_b, _v, _y0, _y1, _zn, _zf, _l0 + 1, _col,
                          _a * _mix);
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc One floor band at mip level `_lvl`: the tile laid out at `2^_lvl`
///       times its world size (valid because the tile is periodic).
function grove_floor_level(_b, _v, _y0, _y1, _zn, _zf, _lvl, _col, _a) {
    if (_a <= 0.004) return;
    var _scale = power(2, _lvl);
    var _fz = GROVE_FLOOR_Z * _scale;
    var _fw = GROVE_FLOOR_W * _scale;
    var _th = sprite_get_height(spr_scn_floor);

    var _k = corridor_k((_zn + _zf) * 0.5);
    var _bw = _k * _fw;
    if (_bw < 2) return;
    var _m0 = floor((_v.x0 - _v.cx) / _bw) - 1;
    var _m1 = ceil((_v.x1 - _v.cx) / _bw) + 1;

    // Which slice of the tile, by depth travelled. The row is one minus the
    // fraction, so deeper is higher up the texture.
    var _sn = (1 - frac((_zn + _b.dist) / _fz)) * _th;
    var _sf = (1 - frac((_zf + _b.dist) / _fz)) * _th;

    if (_sf <= _sn) {
        grove_floor_band(_v, _m0, _m1, _bw, _y0, _y1, _sf, _sn, _col, _a);
        return;
    }

    // A band that crosses a tile boundary is drawn as two parts, split where
    // the source runs off the bottom of the texture.
    var _run = _sn + (_th - _sf);
    var _cut = _y1 + (_y0 - _y1) * (_sn / max(1, _run));
    grove_floor_band(_v, _m0, _m1, _bw, _cut, _y1, 0, _sn, _col, _a);
    grove_floor_band(_v, _m0, _m1, _bw, _y0, _cut, _sf, _th, _col, _a);
}

/// @desc One floor band tiled across the view: tile rows `_sf`..`_sn` drawn
///       between screen rows `_y0`..`_y1`.
function grove_floor_band(_v, _m0, _m1, _bw, _y0, _y1, _sf, _sn, _col, _a) {
    var _h = _y1 - _y0;
    var _sh = _sn - _sf;
    if (_h <= 0.4 || _sh <= 0.4) return;
    var _tw = sprite_get_width(spr_scn_floor);
    for (var _m = _m0; _m <= _m1; _m++) {
        var _x = _v.cx + _m * _bw;
        if (_x > _v.x1 || _x + _bw < _v.x0) continue;
        draw_sprite_part_ext(spr_scn_floor, 0, 0, _sf, _tw, _sh,
                             _x, _y0, _bw / _tw, _h / _sh, _col, _a);
    }
}

/// @desc The path down the middle: five nested translucent wedges, darker
///       than the floor, converging on the vanishing point (stacked for a
///       softer edge).
function grove_draw_path(_b, _v) {
    var _hy = corridor_horizon(_v);
    var _y0 = _hy + 2;
    if (_y0 >= _v.y1) return;

    for (var _n = 0; _n < 5; _n++) {
        var _wide = GROVE_PATH_HALF * (0.98 - _n * 0.17);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i <= 20; _i++) {
            var _sy = _y0 + (_v.y1 - _y0) * (_i / 20);
            var _z = corridor_depth_at(_v, _sy);
            var _k = corridor_k(_z);
            var _hw = _k * _wide;
            // Fades out with distance and also near the camera.
            var _a = 0.09 * corridor_haze(_z) * clamp((_z - 260) / 500, 0, 1);
            var _c = merge_colour(_b.air_n, _b.air_b,
                                  grove_blood_at(_b, _z));
            draw_vertex_colour(_v.cx - _hw, _sy, _c, _a);
            draw_vertex_colour(_v.cx + _hw, _sy, _c, _a);
        }
        draw_primitive_end();
    }
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc Pools of moonlight on the floor: additive ellipses projected onto the
///       ground, positions derived from the clock. They go out with the moon.
function grove_draw_dapple(_b, _v, _sb) {
    if (_b.light <= 0.02) return;
    var _bw = sprite_get_width(spr_fx_bloom);
    var _hy = corridor_horizon(_v);
    var _span = 2600;
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 18; _i++) {
        var _u = frac(corridor_hash(_i, 22) + _b.dist / _span);
        var _z = _span * (1 - _u) + 220;
        var _lap = floor(corridor_hash(_i, 22) + _b.dist / _span);
        var _k = corridor_k(_z);
        var _wx = (corridor_hash(_i + _lap * 13, 26) - 0.5) * 2200;
        var _x = _v.cx + _k * _wx;
        var _y = _hy + _k * CORRIDOR_CAM_H;
        if (_y > _v.y1 + 300 || _x < _v.x0 - 500 || _x > _v.x1 + 500) continue;

        // Flattened to a fifth of their width (light lying on the ground).
        var _w = _k * (240 + 320 * corridor_hash(_i + _lap * 13, 28)) / _bw;
        var _a = 0.10 * _b.light * min(1, _u * 5) * min(1, (1 - _u) * 3);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _w, _w * 0.22, 0,
                        merge_colour(_b.moon_n, _b.moon_b, _sb), _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Banks of fog on the floor rushing past: additive, flat ellipses
///       projected onto the ground, positions derived from the clock.
function grove_draw_ground_fog(_b, _v, _sb) {
    var _bw = sprite_get_width(spr_fx_bloom);
    var _hy = corridor_horizon(_v);
    var _col = grove_dim(_b, merge_colour(_b.haze_n, _b.haze_b, _sb), _sb);
    var _span = 3000;
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 15; _i++) {
        var _u = frac(corridor_hash(_i, 8) + _b.dist / _span);
        var _z = _span * (1 - _u) + 240;
        var _lap = floor(corridor_hash(_i, 8) + _b.dist / _span);
        var _k = corridor_k(_z);
        var _wx = (corridor_hash(_i + _lap * 17, 12) - 0.5) * 2600;
        var _x = _v.cx + _k * _wx;
        var _y = _hy + _k * (CORRIDOR_CAM_H - 20);
        if (_y > _v.y1 + 200 || _x < _v.x0 - 700 || _x > _v.x1 + 700) continue;
        // Wide and flat.
        var _w = _k * (700 + 600 * corridor_hash(_i + _lap * 17, 14)) / _bw;
        var _h = _w * 0.20;
        var _a = 0.085 * min(1, _u * 5) * min(1, (1 - _u) * 3);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _w, _h, 0, _col, _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The mist bands. The back pass is normal-blended (adding the bank
///       lying across the moon would brighten the moon); the front pass, over
///       the field, is additive so it can't hide bullets.
function grove_draw_mist(_b, _v, _sb, _front) {
    var _hy = corridor_horizon(_v);
    var _col = merge_colour(_b.haze_n, _b.haze_b, _sb);
    var _sc = _v.w / sprite_get_width(spr_scn_mist);
    var _h = sprite_get_height(spr_scn_mist) * _sc;
    // The mist fades with the moonlight.
    var _still = _b.light;

    if (_front) {
        gpu_set_blendmode(bm_add);
        corridor_draw_band(_v, spr_scn_mist, grove_rooted_x(_v, 210, 500) - _b.drift * 3.4,
                           _v.y1 - _h * 0.72, _sc * 1.7, _col, 0.10 * _still);
        gpu_set_blendmode(bm_normal);
        return;
    }
    gpu_set_blendmode(bm_normal);
    // Thickest at the vanishing point and thinner nearer the camera. The bank
    // at the vanishing point undulates like the ground under it.
    corridor_draw_band_wave(_v, spr_scn_mist, grove_rooted_x(_v, 0, 4000) + _b.drift * 0.5,
                            _hy - _h * 0.42, _sc, _col, 0.17 * _still,
                            GROVE_MIST_WAVE, 421);
    corridor_draw_band(_v, spr_scn_mist, grove_rooted_x(_v, 400, 2600) - _b.drift * 0.9,
                       _hy + _v.h * GROVE_MIST_Y - _h * 0.5, _sc * 1.25, _col,
                       0.13 * _still);
    corridor_draw_band(_v, spr_scn_mist, grove_rooted_x(_v, 830, 1200) + _b.drift * 1.6,
                       _hy + _v.h * GROVE_MIST_Y * 2.6 - _h * 0.5, _sc * 1.5,
                       _col, 0.07 * _still);
}

/// @desc Draw one prop (from the merged pass), with the litter mound at its
///       foot and whatever hangs on it.
function grove_draw_one(_b, _v, _p) {
    // Sprite, height and rim strength by kind.
    var _spr, _rim, _wh, _rim_k, _anchor, _yflip;
    switch (_p.kind) {
        case GROVE_KIND_TRUNK:
            _spr = spr_scn_trunk; _rim = spr_scn_trunk_rim;
            // Trunks get a stronger rim: on a wide trunk it is a thin
            // highlight, where on thin branches a strong rim overwhelms them.
            _wh = GROVE_TRUNK_H; _rim_k = 3.0;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
        case GROVE_KIND_BUSH:
            _spr = spr_scn_bush; _rim = spr_scn_bush_rim;
            _wh = GROVE_BUSH_H; _rim_k = 1;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
        case GROVE_KIND_VERGE:
            // Its own six plants (`make_brush`).
            _spr = spr_scn_brush; _rim = spr_scn_brush_rim;
            _wh = GROVE_VERGE_H; _rim_k = 1.2;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
        case GROVE_KIND_BOUGH:
            // The tree sprite hung upside down, with the foot of the trunk
            // faded out (`bough_from` in `tools/make_grove.py`).
            _spr = spr_scn_bough; _rim = spr_scn_bough_rim;
            _wh = GROVE_BOUGH_H; _rim_k = 1.4;
            _anchor = -_p.hang; _yflip = -1;
            break;
        default:
            _spr = spr_scn_tree; _rim = spr_scn_tree_rim;
            _wh = GROVE_TREE_H; _rim_k = 1;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
    }

    var _k = corridor_k(_p.z);
    var _sx = _v.cx + _k * _p.wx;
    // This prop's height; the rim, mound and hanging things are measured
    // from it.
    var _h = _wh * _p.scale;

    // Skip props entirely off the side of the view.
    var _half = _k * _h * 0.6;
    if (_sx + _half < _v.x0 || _sx - _half > _v.x1) return;

    var _haze = corridor_haze(_p.z);
    // Fade near the camera and near its own ring's far plane.
    var _fade = corridor_near_fade(_p.z) * corridor_prop_fade(_p);
    var _blood = grove_blood_at(_b, _p.z);
    var _flare = grove_flare_at(_b, _p.z);

    // Farther trees are lifted toward the fog colour.
    var _col = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _blood),
                            merge_colour(_b.fog_n, _b.fog_b, _blood),
                            power(1 - _haze, 1.4));
    var _rc = grove_dim(_b, merge_colour(_b.rim_n, _b.rim_b, _blood), _blood);

    // The rim is kept faint (strong rims turned thin branches into glowing
    // wire).
    corridor_draw_prop(_v, _spr, _rim, _p.frame, _p.z, _p.wx, _h,
                       _p.flip, _col, _rc, _p.a * _fade,
                       (0.10 + 0.20 * _haze + 0.7 * _flare) * _rim_k * _fade,
                       _p.aspect, _anchor, _yflip);

    // Only props standing on the ground get a mound.
    if (_yflip > 0) grove_draw_mound(_b, _v, _p, _spr, _h, _col, _fade);

    if (_p.tag < 0) return;
    if (_p.kind == GROVE_KIND_TREE) {
        grove_draw_charm(_b, _v, _p, _h, _haze, _fade, _blood, _flare);
    } else if (_p.kind == GROVE_KIND_TRUNK) {
        grove_draw_ivy(_b, _v, _p, _h, _haze, _fade, _blood);
    }
}

/// @desc A dark bank of litter at a prop's foot, hiding the straight bottom
///       edge of the billboard. Normal-blended (it removes light), which is
///       fine in the back pass.
function grove_draw_mound(_b, _v, _p, _spr, _wh, _col, _a) {
    if (_a <= 0.01) return;
    var _k = corridor_k(_p.z);
    var _y = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    // Only when the foot is on screen.
    if (_y < _v.y0 - 40 || _y > _v.y1 + 40) return;

    var _w = _k * 2 * corridor_prop_half_w(_spr, _wh, 1, _p.aspect);
    if (_w < 8) return;
    var _x = _v.cx + _k * _p.wx;
    if (_x + _w < _v.x0 - 40 || _x - _w > _v.x1 + 40) return;

    // A triangle strip: opaque along the ground line, fading downward, and
    // tapering at both ends. (A bloom sprite is too faint away from its centre
    // to cover the edge.)
    var _hw = _w * 0.72;
    var _hh = _w * 0.24;
    var _n = 12;
    draw_primitive_begin(pr_trianglestrip);
    for (var _i = 0; _i <= _n; _i++) {
        var _t = _i / _n;
        var _e = 1 - power(_t * 2 - 1, 2);     // 0 at the ends, 1 in the middle
        var _cx = _x + (_t - 0.5) * _hw * 2;
        draw_vertex_colour(_cx, _y - _hh * 0.35 * _e, _col, _a * 0.95);
        draw_vertex_colour(_cx, _y + _hh * _e, _col, 0);
    }
    draw_primitive_end();
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

/// @desc A charm hanging from one of a tree's branch tips. The tip positions
///       come from `scripts/grove_table`, written by `tools/make_grove.py`
///       when it draws the trees.
function grove_draw_charm(_b, _v, _p, _wh, _haze, _fade, _blood, _flare) {
    var _hang = grove_hang_at(_p.frame, _p.hang);
    var _k = corridor_k(_p.z);
    var _ts = _k * _wh / sprite_get_height(spr_scn_tree);

    // The tree sprite's origin is the foot of its trunk.
    var _bx = _v.cx + _k * _p.wx;
    var _by = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    var _x = _bx + (_hang[0] - 0.5) * sprite_get_width(spr_scn_tree)
                   * _ts * _p.aspect * _p.flip;
    var _y = _by + (_hang[1] - 1) * sprite_get_height(spr_scn_tree) * _ts;

    var _cs = _k * GROVE_CHARM_H / sprite_get_height(spr_scn_charm);
    // It swings: the charm's origin is the top of its cord, so rotating it is
    // a pendulum.
    var _ang = dsin(_b.t * 1.1 + _p.sway) * GROVE_CHARM_SWAY;

    var _wood = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _blood),
                             merge_colour(_b.air_n, _b.air_b, _blood),
                             1 - _haze);
    draw_sprite_ext(spr_scn_charm, _p.tag, _x, _y, _cs, _cs, _ang,
                    merge_colour(_wood, c_white, 0.22 * _haze), _fade);

    // Its glow: the one second hue in the wood (and it flares as the
    // wavefront passes).
    var _lit = merge_colour(_b.charm_n, _b.charm_b, _blood);
    var _a = (0.45 + 0.55 * _haze) * _fade * (0.82 + 0.18 * dsin(_b.t * 2.3
                                                                + _p.sway))
             + _flare * 0.8;
    gpu_set_blendmode(bm_add);
    var _bw = sprite_get_width(spr_fx_bloom);
    var _bs = _k * GROVE_CHARM_H * (1.5 + _flare) / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _x, _y + _cs
                    * sprite_get_height(spr_scn_charm) * 0.5,
                    _bs, _bs, 0, _lit, min(1, _a) * 0.30);
    draw_sprite_ext(spr_scn_charm_lit, _p.tag, _x, _y, _cs, _cs, _ang,
                    _lit, min(1, _a));
    gpu_set_blendmode(bm_normal);
}

/// @desc Two clusters of ivy on the moonward side of a trunk.
function grove_draw_ivy(_b, _v, _p, _wh, _haze, _fade, _blood) {
    var _k = corridor_k(_p.z);
    var _bx = _v.cx + _k * _p.wx;
    var _by = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    var _ts = _k * _wh / sprite_get_height(spr_scn_trunk);
    var _tw = sprite_get_width(spr_scn_trunk) * _ts * _p.aspect;
    var _ls = _k * GROVE_IVY_H / sprite_get_height(spr_scn_leaf);

    // The moonward side is the inner one, which `flip` already encodes.
    var _col = merge_colour(merge_colour(_b.ivy_n, _b.ivy_b, _blood),
                            merge_colour(_b.fog_n, _b.fog_b, _blood),
                            power(1 - _haze, 1.4));
    for (var _i = 0; _i < 2; _i++) {
        var _up = _p.sway + _i * 0.24;
        var _x = _bx + _tw * 0.30 * _p.flip;
        var _y = _by - _k * _wh * _up;
        draw_sprite_ext(spr_scn_leaf, (_p.tag + _i) mod
                        sprite_get_number(spr_scn_leaf),
                        _x, _y, _ls * _p.flip, _ls,
                        dsin(_b.t * 0.6 + _i * 120) * 3, _col, _fade);
    }
}

/// @desc Wisps streaming past the camera: additive, positions derived from
///       the clock and the distance flown.
function grove_draw_wisps(_b, _v, _n, _zmax, _size, _alpha) {
    var _bw = sprite_get_width(spr_fx_bloom);
    var _hy = corridor_horizon(_v);
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < _n; _i++) {
        var _u = frac(corridor_hash(_i, 2) + _b.dist / _zmax);
        var _z = _zmax * (1 - _u) + CORRIDOR_Z_MIN;
        var _lap = floor(corridor_hash(_i, 2) + _b.dist / _zmax);
        var _k = corridor_k(_z);
        var _wx = (corridor_hash(_i + _lap * 31, 4) - 0.5) * 2400;
        var _wy = CORRIDOR_CAM_H
                  - corridor_hash(_i + _lap * 31, 6) * 420
                  + dsin(_b.t * 0.9 + _i * 37) * 26;
        var _x = _v.cx + _k * _wx;
        var _y = _hy + _k * _wy;
        if (_x < _v.x0 - 60 || _x > _v.x1 + 60) continue;

        var _s = _k * _size / _bw;
        // Fades in and out at the ends of its run.
        var _a = _alpha * min(1, _u * 6) * min(1, (1 - _u) * 3.5)
                 * (0.6 + 0.4 * dsin(_b.t * 2.1 + _i * 61));
        // Not dimmed by the eclipse (they are their own light).
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        merge_colour(_b.wisp_n, _b.wisp_b,
                                     grove_blood_at(_b, _z)), _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Darken the view inward from its edges.
function grove_draw_vignette(_b, _v) {
    var _c = merge_colour(make_colour_rgb(4, 6, 11),
                          make_colour_rgb(11, 3, 5), grove_sky_blood(_b));
    var _d = _v.h * 0.34;
    grove_vig_strip(_v.x0, _v.y0, _v.x1, _v.y0, _v.x0, _v.y0 + _d,
                    _v.x1, _v.y0 + _d, _c, 0.62);
    grove_vig_strip(_v.x0, _v.y1, _v.x1, _v.y1, _v.x0, _v.y1 - _d,
                    _v.x1, _v.y1 - _d, _c, 0.45);
    grove_vig_strip(_v.x0, _v.y0, _v.x0, _v.y1, _v.x0 + _d, _v.y0,
                    _v.x0 + _d, _v.y1, _c, 0.50);
    grove_vig_strip(_v.x1, _v.y0, _v.x1, _v.y1, _v.x1 - _d, _v.y0,
                    _v.x1 - _d, _v.y1, _c, 0.50);
}

function grove_vig_strip(_ax, _ay, _bx, _by, _cx, _cy, _dx, _dy, _col, _a) {
    draw_primitive_begin(pr_trianglestrip);
    draw_vertex_colour(_ax, _ay, _col, _a);
    draw_vertex_colour(_bx, _by, _col, _a);
    draw_vertex_colour(_cx, _cy, _col, 0);
    draw_vertex_colour(_dx, _dy, _col, 0);
    draw_primitive_end();
    draw_set_alpha(1);
    draw_set_colour(c_white);
}

// ---------------------------------------------------------------------------
// Drawing: in front of the field
// ---------------------------------------------------------------------------

/// @desc The pass drawn over the field: every draw here is additive, so it
///       can never hide a bullet. It fades with the spell background.
function grove_draw_front(_b, _spell, _fill) {
    var _a = 1 - 0.86 * clamp(_spell, 0, 1);
    if (_a <= 0.02) return;
    // The same view as the back pass, so the rims line up with the trees.
    var _v = corridor_view(_fill, _b.cam_x, _b.cam_y, _b.lat);
    var _sb = grove_sky_blood(_b);

    gpu_set_blendmode(bm_add);

    // Rim light of the nearest trees.
    var _r = _b.trees;
    var _order = corridor_ring_order(_r);
    for (var _j = 0; _j < _r.n; _j++) {
        var _p = _r.props[_order[_j]];
        if (_p.z > GROVE_NEAR_Z) continue;
        var _k = corridor_k(_p.z);
        var _sx = _v.cx + _k * _p.wx;
        var _h = GROVE_TREE_H * _p.scale;
        var _half = _k * _h * 0.6;
        if (_sx + _half < _v.x0 || _sx - _half > _v.x1) continue;

        var _rs = _k * _h / sprite_get_height(spr_scn_tree_rim);
        var _near = 1 - clamp((_p.z - CORRIDOR_Z_NEAR)
                              / (GROVE_NEAR_Z - CORRIDOR_Z_NEAR), 0, 1);
        draw_sprite_ext(spr_scn_tree_rim, _p.frame, _sx,
                        corridor_horizon(_v) + _k * CORRIDOR_CAM_H,
                        _rs * _p.flip * _p.aspect, _rs, 0,
                        merge_colour(_b.rim_n, _b.rim_b,
                                     grove_blood_at(_b, _p.z)),
                        _near * 0.34 * _a);
    }
    gpu_set_blendmode(bm_normal);

    grove_draw_mist(_b, _v, _sb, true);
    // Fast wisps close to the lens.
    grove_draw_wisps(_b, _v, 22, 900, 9.0, 0.30 * _a);
}

// ---------------------------------------------------------------------------
// The caster's spell background
// ---------------------------------------------------------------------------

/// @desc Velka's spell background (doesn't use `_col`): a dark wash, a large
///       blood moon behind her station, two counter-turning rune circles,
///       rings pushing outward, her antlers rising out of the bottom corners
///       (drawn larger than the frame), and rising leaves and ash. Then a
///       vignette.
function spell_bg_grove(_col, _t, _fade) {
    var _bone = make_colour_rgb(206, 200, 176);
    var _blood = make_colour_rgb(190, 44, 40);
    var _ivy = make_colour_rgb(58, 122, 88);

    draw_set_alpha(_fade);
    draw_set_colour(make_colour_rgb(9, 7, 12));
    draw_rectangle(FIELD_X0, FIELD_Y0, FIELD_X1, FIELD_Y1, false);
    draw_set_alpha(1);
    draw_set_colour(c_white);

    var _fx = FIELD_CX;
    var _fy = BOSS_HOME_Y;

    gpu_set_blendmode(bm_add);

    // The moon behind her.
    var _ms = (FIELD_W * 0.62) / sprite_get_width(spr_scn_moon);
    draw_sprite_ext(spr_scn_moon, 0, _fx, _fy + 40, _ms, _ms, 0, _blood,
                    0.30 * _fade * (0.9 + 0.1 * dsin(_t * 0.8)));

    var _bw = sprite_get_width(spr_fx_bloom);
    var _bs = (FIELD_W * 1.1) / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _fx, _fy, _bs, _bs, 0, _blood,
                    0.13 * _fade * (0.84 + 0.16 * dsin(_t * 1.2)));

    // Two rune circles, counter-turning slowly.
    var _ss = 1420 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, _fx, _fy, _ss, _ss, _t * 0.09, _bone,
                    0.10 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, _fx, _fy, _ss * 0.58, _ss * 0.58,
                    -_t * 0.17, _ivy, 0.09 * _fade);

    // Rings pushing outward every four seconds.
    for (var _i = 0; _i < 3; _i++) {
        var _p = frac(_t / 240 + _i / 3);
        var _rr = (140 + _p * 1400) * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _fx, _fy, _rr, _rr, 0, _bone,
                        (1 - _p) * 0.11 * _fade);
    }

    // Her antlers from the bottom corners, mirrored.
    var _as = 1.9;
    var _aa = 0.46 * _fade * (0.88 + 0.12 * dsin(_t * 0.9));
    draw_sprite_ext(spr_scn_antler, 0, FIELD_X0 - 60, FIELD_Y1 + 150,
                    -_as, _as, 0, _bone, _aa);
    draw_sprite_ext(spr_scn_antler, 0, FIELD_X1 + 60, FIELD_Y1 + 150,
                    _as, _as, 0, _bone, _aa);

    // Rising leaves and ash.
    var _sw = sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < 38; _i++) {
        var _p = frac(_t * (0.0014 + 0.0010 * frac(_i * 0.37)) + _i * 0.117);
        var _x = FIELD_X0 + frac(_i * 0.618) * FIELD_W
                 + dsin(_t * 0.7 + _i * 47) * (50 + 70 * frac(_i * 0.23));
        var _y = FIELD_Y1 + 60 - _p * (FIELD_H + 120);
        var _a = min(1, _p * 6) * (1 - _p) * _fade;
        var _leaf = (_i mod 3) != 0;
        var _s = ((_leaf ? 18 : 11) + 12 * frac(_i * 0.71)) / _sw;
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        _leaf ? _ivy : _bone, _a * (_leaf ? 0.30 : 0.34));
    }

    gpu_set_blendmode(bm_normal);
    spell_bg_vignette(_fade * 0.55);
}
