/// @desc The Hollow Grove: a wood flown through at night, under a moon that
///       turns to blood.
///
/// **The projection is `bg_corridor`'s and everything here is what is arranged
/// in it.** That split is the same one `stage_ziggy` keeps from
/// `danmaku_functions`: one file is the machinery and one is the content, and
/// the content is meant to read as a paragraph.
///
/// What is in the picture, back to front
/// -------------------------------------
///
/// | | |
/// |---|---|
/// | the sky | a vertical ramp, and stars that go out |
/// | the moon | on the horizon, centred, eclipsed once |
/// | the canopy | branches closing the top of the frame |
/// | the treeline | the far wall of wood, sliding sideways |
/// | the ground | bands of root and moss, read off the projection |
/// | the mist | three drifting bands at the vanishing point |
/// | the trees | forty billboards, hung with charms |
/// | the ferns | twenty-six more, close and fast |
/// | the wisps | spirit lights streaming past the camera |
///
/// Eight layers at seven rates. It is the same argument the forge is built on
/// -- each of them is cheap, and the depth is in there being eight of them.
///
/// **One rule holds all of it together and it is subtraction.** The scenery
/// does not get brighter to be seen; the only lit things in this wood are the
/// moon, the charms hanging in the trees and the wisps, and every one of them
/// is small. Two thousand bullets have to read against this, and the moon sits
/// exactly where the boss stands and exactly where the danmaku is thickest --
/// which is why it is a *dark* disc with structure in it rather than a lamp.
///
/// The turn
/// --------
///
/// Half way through, the stage changes. `bg_set_omen` starts it and it runs
/// for `BG_OMEN_TIME` frames in four movements:
///
/// 1. **The quiet.** The mist stills, the stars begin to go out.
/// 2. **The eclipse.** An umbra crosses the moon, left to right, and the wood
///    loses its only light for about a second.
/// 3. **The relighting.** The moon comes out of the shadow red, brighter than
///    it went in, and a ring leaves it.
/// 4. **The wavefront.** The red travels *down the corridor* toward the
///    player -- the far trees first, the near ones last, every charm flaring
///    as it passes -- and the world speeds up behind it.
///
/// **The wave is a depth, not a screen radius**, and that is the whole trick.
/// Every prop and every row of ground already knows its own z, so "has the
/// wave reached this yet" is one compare, and what it draws is red arriving
/// out of the distance and rolling over the wood toward the camera. A ring
/// expanding across the screen would have been the obvious version and it
/// would have been wrong: it would have turned the *near* trees first.

// ---------------------------------------------------------------------------
// The stage's backdrop
// ---------------------------------------------------------------------------

/// @desc The Hollow Grove.
///
///       **The palette is two palettes and every draw call lerps between
///       them.** Nothing in the art has a hue in it -- see the note at the
///       top of `tools/make_grove.py` -- so the whole stage turns by moving
///       one number, and a tree half way through the turn is genuinely half
///       way rather than being cross-faded between two copies of itself.
function bg_grove() {
    var _b = bg_new(undefined, undefined, undefined,
                    make_colour_rgb(9, 14, 22), 0);
    _b.kind = BGKIND_CORRIDOR;

    // Night, and then blood. Read once, here, rather than at four hundred
    // call sites a frame.
    //
    // **Saturated, and that took a correction.** The first pass of this
    // palette was built by taking the brimstone stage's rule -- scenery stays
    // dark, because every point of value spent on it is a point the bullets
    // no longer have -- and applying it to the *chroma* as well. What came
    // back was reported as "all black and white". Value and saturation are
    // not the same budget: a deep teal at the same value as a neutral grey
    // costs the danmaku exactly nothing and is the difference between a wood
    // at night and a photocopy of one. It is the same finding the console
    // records about gilt on indigo, one layer further in.
    _b.air_n    = make_colour_rgb(7, 17, 23);      // the deep of the wood
    _b.air_b    = make_colour_rgb(18, 6, 9);
    _b.sky_n    = make_colour_rgb(17, 50, 68);     // the lit part of the sky
    _b.sky_b    = make_colour_rgb(52, 11, 16);
    _b.haze_n   = make_colour_rgb(34, 122, 140);   // mist with moon in it
    _b.haze_b   = make_colour_rgb(128, 30, 28);
    // **The moon is held at about half of white and that is a fairness
    // number.** It sits behind the middle of the playfield, where the boss
    // stands and the danmaku is thickest, and the first pass of it was a pale
    // disc at nearly full value -- which photographed as the brightest thing
    // on the screen with bullets crossing it. It carries its reading in maria
    // and craters instead; a moon that has to be a lamp to be a moon is a
    // moon this stage cannot have.
    _b.moon_n   = make_colour_rgb(146, 166, 170);
    _b.moon_b   = make_colour_rgb(196, 44, 32);
    _b.tree_n   = make_colour_rgb(6, 19, 25);      // a silhouette in fog
    _b.tree_b   = make_colour_rgb(21, 8, 11);
    // **What distance fades a tree *toward*, and it is lighter than the tree
    // is.** The first pass hazed toward the air, which is darker than the
    // wood -- so the far trees came out blacker than the near ones and the
    // corridor had no aerial perspective in it at all. Fog lifts what is
    // behind it; that is the whole of what makes a distance read.
    _b.fog_n    = make_colour_rgb(22, 66, 80);
    _b.fog_b    = make_colour_rgb(50, 17, 17);
    _b.rim_n    = make_colour_rgb(76, 164, 186);   // moonlight on an edge
    _b.rim_b    = make_colour_rgb(232, 72, 46);
    _b.grnd_n   = make_colour_rgb(9, 22, 21);
    _b.grnd_b   = make_colour_rgb(20, 9, 10);
    _b.moss_n   = make_colour_rgb(26, 62, 46);     // what the ground bands are
    _b.moss_b   = make_colour_rgb(58, 20, 18);
    // The floor texture's *peak*: leaf litter with the moon on it. Everything
    // below it in the tile comes out darker on its own.
    _b.floor_n  = make_colour_rgb(38, 66, 46);
    _b.floor_b  = make_colour_rgb(54, 21, 18);
    // **The ivy is the one thing in this wood that is a hue rather than a
    // temperature**, and it is why the stage is not two colours. It goes
    // brown when the moon does, because a wood under a blood moon with
    // healthy green ivy in it is a wood the turn did not reach.
    _b.ivy_n    = make_colour_rgb(48, 126, 78);
    _b.ivy_b    = make_colour_rgb(78, 32, 24);
    _b.charm_n  = make_colour_rgb(150, 240, 190);  // a witch-light, cold
    _b.charm_b  = make_colour_rgb(255, 128, 56);
    _b.wisp_n   = make_colour_rgb(104, 232, 202);
    _b.wisp_b   = make_colour_rgb(255, 92, 48);

    _b.dist = 0;
    _b.drift = 0;          // how far the distant wood has slid sideways
    _b.spd = GROVE_SPEED;

    // **How much light there is in the wood at all**, and it is one number
    // because there is one source. At totality the moon is behind a shadow,
    // so the mist stops glowing, the rims go out, the floor goes to the
    // colour of the air and the only things left burning are the hexes in the
    // trees -- which is the whole of what makes the second and third
    // movements of the turn land. Dimming the *moon* alone, which is what the
    // first pass did, photographed as a wood in full moonlight with the moon
    // missing.
    _b.light = GROVE_NIGHT_LIGHT;

    // The wavefront's depth. Past the far plane means "nothing has happened",
    // which is the honest reading and needs no second flag.
    _b.wave = GROVE_WAVE_Z0 * 4;

    _b.trees = corridor_ring(GROVE_TREE_N, CORRIDOR_Z_NEAR, CORRIDOR_Z_FAR,
                             grove_make_tree);
    // **The layer that makes it a forest rather than a clearing.** The wood
    // was six frames of whole tree at every distance, and reported as looking
    // like a pond: at any depth where a *whole* tree fits inside the frame
    // nothing in the picture is near, so however many of them there were the
    // camera was always across a field from all of them. These are trunks --
    // fragments, taller than the screen, close to the path -- and they pass
    // the camera rather than standing in front of it.
    _b.trunks = corridor_ring(GROVE_TRUNK_N, CORRIDOR_Z_NEAR - 30,
                              GROVE_TRUNK_Z, grove_make_trunk);
    _b.bushes = corridor_ring(GROVE_BUSH_N, CORRIDOR_Z_NEAR - 40,
                              GROVE_BUSH_Z, grove_make_bush);

    // **Boughs overhead, and they are the tree sprite upside down.** A canopy
    // drawn as a band sliding sideways is the one piece of this stage that
    // could not be right, because in a corridor nothing distant slides: it
    // grows. These are ordinary props with their anchor *above* the camera
    // instead of on the ground and their sprite hung downward from it, so they
    // come at the lens and sweep off the top of the frame exactly as the
    // trunks sweep off the sides. It costs no new art -- a tree flipped in y
    // about its own root is a bough.
    _b.boughs = corridor_ring(GROVE_BOUGH_N, CORRIDOR_Z_NEAR, GROVE_BOUGH_Z,
                              grove_make_bough);

    // **One depth-sorted pass over all four rings.** See `corridor_merge_new`:
    // depth order is a property of the frame, not of a ring, and drawing the
    // rings one after another put every trunk in the wood in front of every
    // tree in it.
    _b.merge = corridor_merge_new([_b.trees, _b.trunks, _b.bushes, _b.boughs]);

    // The one struct `corridor_draw_ground` writes a row's colour into. Owned
    // here so the ground costs no allocation a frame.
    _b.grnd_out = { col: c_black, a: 1 };
    return _b;
}

/// @desc What a tree becomes when it comes round again.
///
///       **Everything is a hash of the lap, never `random`.** A wood whose
///       trees stand somewhere else on the second attempt is a wood nobody can
///       build a memory of -- the same argument `hex_spray_dir` makes one file
///       over, and the reason the scatter there is a hash of a bead's index.
function grove_make_tree(_p, _lap) {
    var _side = (corridor_hash(_lap, 11) < 0.5) ? -1 : 1;
    _p.wx = _side * (GROVE_PATH_HALF
                     + corridor_hash(_lap, 23) * (GROVE_TREE_OUT
                                                  - GROVE_PATH_HALF));
    _p.frame = floor(corridor_hash(_lap, 37) * sprite_get_number(spr_scn_tree));
    // **Trees on the left are lit on their right.** The moon is a single
    // source in the middle of the frame, so the sprite's own lit edge is
    // mirrored per side rather than drawn twice -- which is also why the
    // rim ships as one sprite and not two.
    _p.flip = _side;
    _p.a = 0.86 + 0.14 * corridor_hash(_lap, 53);
    _p.scale = 1 + (corridor_hash(_lap, 59) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 67) - 0.5) * 2 * GROVE_VARY_W;

    // What is hanging in it, and where. `-1` is a tree with nothing in it,
    // and so is a frame whose branches all point upward -- see
    // `grove_hang_count`.
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

/// @desc What a trunk becomes when it comes round again.
function grove_make_trunk(_p, _lap) {
    _p.kind = GROVE_KIND_TRUNK;
    var _side = (corridor_hash(_lap, 3) < 0.5) ? -1 : 1;
    _p.frame = floor(corridor_hash(_lap, 27)
                     * sprite_get_number(spr_scn_trunk));
    _p.scale = 1 + (corridor_hash(_lap, 31) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 37) - 0.5) * 2 * GROVE_VARY_W;

    // **Placed by its inner edge, not by its middle.** `GROVE_TRUNK_HALF` is
    // the clearance the nearest edge of a trunk keeps from the centre line,
    // and adding the prop's own half-width to it is what keeps that promise
    // once trunks come in eight silhouettes at a range of sizes. Measured
    // from the middle instead, the widest of them would stand exactly where
    // the narrowest does and wall the field -- which is the bug this constant
    // was already rewritten once to fix, waiting to come back the moment the
    // widths stopped being uniform.
    var _hw = corridor_prop_half_w(spr_scn_trunk, GROVE_TRUNK_H,
                                   _p.scale, _p.aspect);
    _p.wx = _side * (GROVE_TRUNK_HALF + _hw
                     + corridor_hash(_lap, 13) * GROVE_TRUNK_OUT);
    _p.flip = _side;
    _p.a = 1;
    // Ivy on about half of them, at a height of its own up the trunk.
    _p.tag = (corridor_hash(_lap, 39) < 0.55)
             ? floor(corridor_hash(_lap, 47) * sprite_get_number(spr_scn_leaf))
             : -1;
    _p.sway = 0.18 + corridor_hash(_lap, 51) * 0.55;   // how far up it is
}

function grove_make_bush(_p, _lap) {
    _p.kind = GROVE_KIND_BUSH;
    var _side = (corridor_hash(_lap, 7) < 0.5) ? -1 : 1;
    _p.wx = _side * (140 + corridor_hash(_lap, 19) * 1000);
    _p.frame = floor(corridor_hash(_lap, 29) * sprite_get_number(spr_scn_bush));
    _p.flip = (corridor_hash(_lap, 43) < 0.5) ? -1 : 1;
    _p.a = 0.74 + 0.26 * corridor_hash(_lap, 59);
    _p.scale = 1 + (corridor_hash(_lap, 71) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 79) - 0.5) * 2 * GROVE_VARY_W;
}

/// @desc What a bough becomes when it comes round again.
///
///       Spread right across the corridor rather than kept off the path: these
///       hang *over* the camera, so the one place a bough is most wanted is
///       directly ahead.
function grove_make_bough(_p, _lap) {
    _p.kind = GROVE_KIND_BOUGH;
    _p.wx = (corridor_hash(_lap, 5) - 0.5) * 2 * GROVE_BOUGH_OUT;
    _p.frame = floor(corridor_hash(_lap, 15) * sprite_get_number(spr_scn_tree));
    _p.flip = (corridor_hash(_lap, 25) < 0.5) ? -1 : 1;
    _p.a = 0.80 + 0.20 * corridor_hash(_lap, 35);
    _p.scale = 1 + (corridor_hash(_lap, 45) - 0.5) * 2 * GROVE_VARY_H;
    _p.aspect = 1 + (corridor_hash(_lap, 55) - 0.5) * 2 * GROVE_VARY_W;
    // How far above the camera this one hangs. Varied, or the canopy is a
    // ceiling at one height.
    // **A narrow band of heights, high up.** At a wide spread the lowest
    // boughs hung to the middle of the field and the layer stopped reading as
    // a canopy the camera is under -- it read as trees growing downward. What
    // is wanted is branches at the top of the frame that sweep up and out of
    // it, so they vary by a fifth rather than by a half.
    _p.hang = GROVE_BOUGH_UP * (0.85 + 0.40 * corridor_hash(_lap, 65));
    _p.tag = -1;
}

// ---------------------------------------------------------------------------
// The clock
// ---------------------------------------------------------------------------

function grove_step(_b) {
    _b.t++;

    // **The speed follows the turn, and the turn is eased.** A stage that
    // changed pace on one frame would read as a dropped frame rather than as
    // an event; the ease is the same shape the spell wash uses.
    var _e = grove_ease(_b.omen);
    _b.spd = lerp(GROVE_SPEED, GROVE_SPEED_FAST, _e);
    _b.light = GROVE_NIGHT_LIGHT * (1 - 0.80 * grove_totality(_b));
    _b.dist += _b.spd;
    // The far wood slides sideways at a fraction of the flight, which is what
    // stops the vanishing point reading as a photograph pinned to the screen.
    _b.drift += _b.spd * 0.10;

    // **Every ring, and there is a suite that counts them.** The trunks were
    // built, drawn, depth-sorted and lit for several passes without this line
    // -- so the nearest and largest things in the wood held station while the
    // whole world went past them, which was reported as static images slapped
    // over the background. Nothing about a prop's *drawing* says whether it is
    // moving; the only thing that does is whether something steps its ring.
    // See `test_corridor`, which now walks the background and refuses one that
    // has not.
    corridor_ring_step(_b.trees, _b.spd);
    corridor_ring_step(_b.trunks, _b.spd);
    corridor_ring_step(_b.bushes, _b.spd);
    corridor_ring_step(_b.boughs, _b.spd);

    // The wavefront. It launches once the eclipse is total and runs the whole
    // depth of the corridor and out the back of the camera.
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

/// @desc How red something at depth `_z` has become, 0..1.
///
///       **The one function the whole turn is expressed through.** A tree, a
///       fern, a hanging charm and a row of ground all ask it the same
///       question with their own depth, so the red genuinely arrives out of
///       the distance and rolls forward rather than being cross-faded
///       everywhere at once.
function grove_blood_at(_b, _z) {
    return clamp((_z - _b.wave) / GROVE_WAVE_FEATHER, 0, 1);
}

/// @desc ...and how brightly the wavefront itself is passing over it. A bump
///       at the front and nothing either side of it, which is what makes a
///       charm flare as the light reaches it.
function grove_flare_at(_b, _z) {
    if (_b.wave > GROVE_WAVE_Z0 * 2) return 0;
    return clamp(1 - abs(_z - _b.wave) / GROVE_WAVE_FLARE, 0, 1);
}

/// @desc How total the eclipse is right now: a bump at the middle of the
///       umbra's transit and nothing either side of it.
///
///       **Half way through the transit, not the end of it.** An eclipse is a
///       body going past, so its coverage rises and falls once -- which is
///       one movement to write where "darken, then reverse" is two, and one
///       of them would have been got wrong.
function grove_totality(_b) {
    return clamp(1 - abs(grove_eclipse(_b) - 0.5) * 4.4, 0, 1);
}

/// @desc Take the light out of a colour. Used on everything the moon lights,
///       which is everything in the wood except the hexes hanging in it.
function grove_dim(_b, _col, _blood) {
    return merge_colour(_col, merge_colour(_b.air_n, _b.air_b, _blood),
                        1 - _b.light);
}

/// @desc The umbra's transit across the moon, 0..1. Half way is totality.
function grove_eclipse(_b) {
    return clamp(_b.omen / GROVE_WAVE_START, 0, 1);
}

/// @desc How much of the *sky's* colour has turned. Screen-space things --
///       the sky, the moon, the stars -- follow this rather than the
///       wavefront, because the sky is at infinity and the wave starts there.
function grove_sky_blood(_b) {
    return grove_ease(clamp((_b.omen - 0.18) / 0.34, 0, 1));
}

// ---------------------------------------------------------------------------
// Drawing: behind the field
// ---------------------------------------------------------------------------

function grove_draw_back(_b, _fill) {
    var _v = corridor_view(_fill);
    var _sb = grove_sky_blood(_b);

    draw_clear(merge_colour(_b.air_n, _b.air_b, _sb));

    grove_draw_sky(_b, _v, _sb);
    grove_draw_moon(_b, _v, _sb);
    grove_draw_horizon_glow(_b, _v, _sb);

    // The canopy closes the top of the frame. **Over the sky and under
    // everything else**: it is the farthest thing in the wood that is still
    // wood, and without it the moon sits in an empty rectangle -- which is
    // what the first three screenshots of this stage were.
    // **Two of them, and the near one is what closes the wood in.** A
    // single band of thin branches across the top of the sky is a fringe; a
    // heavy one over it, drifting at three times the rate and hanging a third
    // of the way down the frame, is a canopy the camera is flying *under*.
    var _tree_far = merge_colour(_b.tree_n, _b.tree_b, _sb);
    var _csc = _v.w / sprite_get_width(spr_scn_canopy);
    // **Slow, because in a corridor nothing distant slides.** These drifted
    // at a third and at very nearly the whole of the flight speed, which is
    // motion the camera is not making: flying straight down a path moves what
    // is overhead *toward* you, and the boughs ring is what does that now.
    // What is left here is a sway, which is the wind.
    corridor_draw_band(_v, spr_scn_canopy, _b.drift * 0.09, _v.y0,
                       _csc, merge_colour(_tree_far, _b.fog_n, 0.42), 0.9);
    corridor_draw_band(_v, spr_scn_canopy, -_b.drift * 0.13 + 317,
                       _v.y0 - _v.h * 0.06, _csc * 1.34, _tree_far, 1);

    grove_draw_treeline(_b, _v, _sb);
    corridor_draw_ground(_v, _b, grove_ground_shade, _b.grnd_out);
    grove_draw_floor(_b, _v);
    grove_draw_path(_b, _v);
    grove_draw_dapple(_b, _v, _sb);
    grove_draw_ground_fog(_b, _v, _sb);
    grove_draw_mist(_b, _v, _sb, false);

    // **One pass, everything, far to near.** Not one pass per ring: see
    // `corridor_merge_new` for what four sequential loops looked like.
    corridor_merge_step(_b.merge);
    for (var _i = 0; _i < _b.merge.total; _i++) {
        grove_draw_one(_b, _v, _b.merge.out[_i]);
    }

    grove_draw_wisps(_b, _v, 40, 3200, 15.0, 0.46);
    grove_draw_vignette(_b, _v);
}

/// @desc The sky: a ramp, and stars in the top of it.
///
///       Drawn as a strip rather than as a sprite, because a gradient is four
///       numbers and a sprite is a megabyte -- and because the two ends of it
///       have to lerp independently as the stage turns, which one tinted
///       sprite cannot do.
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

    // **The stars go out before the eclipse does**, which is the first thing
    // the player is given to notice. They are derived from a hash rather than
    // stored, so there is nothing to seed and nothing to step -- the same
    // bargain `bg_draw_embers` makes.
    var _a = (1 - grove_eclipse(_b)) * 0.5;
    if (_a <= 0.01) return;
    var _sw = sprite_get_width(spr_fx_bloom);
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < 90; _i++) {
        var _x = _v.x0 + corridor_hash(_i, 3) * _v.w;
        var _y = _v.y0 + corridor_hash(_i, 5) * (_hy - _v.y0) * 0.94;
        var _s = (3 + 5 * corridor_hash(_i, 7)) / _sw;
        // A slow twinkle at a rate of its own, so no two are in step.
        var _tw = 0.55 + 0.45 * dsin(_b.t * (0.5 + corridor_hash(_i, 13))
                                     + _i * 47);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        make_colour_rgb(206, 224, 236), _a * _tw);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The moon, and the shadow that crosses it.
///
///       **Drawn additively, and that is what makes the eclipse exact.** A
///       moon composited normally over a sky gradient can only be occluded by
///       something painted in the sky's own colour, which is a different
///       colour at every row; a moon *added* to the sky is undone by
///       subtracting the same sprite, whatever is behind it. The umbra is
///       therefore a shadow drawn *on* the moon, in slices of the moon's own
///       sprite, and it never touches the sky.
///
///       **Two versions of this were wrong before the third.** The first
///       subtracted the moon's disc from itself with `bm_subtract`, which
///       shipped a grey rectangle gliding across the screen: GameMaker's
///       subtract blend does not weight the source by its alpha, and a PNG
///       keeps its colour channels in fully transparent pixels, so a luminance
///       field with a disc-shaped alpha channel is -- to that blend -- a
///       bright grey *square*. Found by rendering the frame twice with the
///       umbra on and off and differencing it; the affected region came back
///       a filled rectangle rather than a circle.
///
///       The second drew the same disc in black through normal blending. That
///       is artefact-free and it was reported as looking weird in motion, and
///       it does: the disc darkens the *sky* wherever it is not over the moon,
///       so what actually travels across the frame is a black circle. An
///       eclipse is not a black circle passing in front of a wood.
///
///       What passes is a shadow, and it is only ever on the moon. So the
///       moon is drawn again in vertical slices of its own sprite -- one
///       `draw_sprite_part_ext` each -- with a per-slice alpha, and the
///       shadow is a soft-edged band in x sweeping across them. Clipped to
///       the disc by construction, because the disc *is* the thing being
///       drawn, and there is nothing to get wrong at the edges.
///
///       **And the shadow is copper, not black.** A total lunar eclipse turns
///       the moon a dark red, because the only light reaching it has been bent
///       through the whole of an atmosphere -- which is to say the eclipse is
///       not something that happens *before* the blood moon, it is the reason
///       for it. Two movements of the turn become one fact.
function grove_draw_moon(_b, _v, _sb) {
    var _cx = _v.cx;
    var _cy = corridor_horizon(_v) - GROVE_MOON_RISE;
    var _r = GROVE_MOON_R * (_v.w / FIELD_W);
    var _col = merge_colour(_b.moon_n, _b.moon_b, _sb);
    var _ecl = grove_eclipse(_b);
    // Totality is a bump at the middle of the transit, not the end of it.
    var _total = clamp(1 - abs(_ecl - 0.5) * 4.4, 0, 1);

    gpu_set_blendmode(bm_add);

    // The corona. It collapses through the eclipse and comes back bigger and
    // redder, which is most of what makes the relighting land.
    var _bw = sprite_get_width(spr_fx_bloom);
    var _cs = _r * (7.0 - 4.4 * _total) * (1 + 0.30 * _sb) / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _cx, _cy, _cs, _cs, 0, _col,
                    (0.15 + 0.13 * _sb) * (1 - _total * 0.86)
                    * (0.9 + 0.1 * dsin(_b.t * 0.7)));

    var _ms = _r * 2 / sprite_get_width(spr_scn_moon);
    draw_sprite_ext(spr_scn_moon, 0, _cx, _cy, _ms, _ms, 0, _col,
                    0.80 * (1 + 0.25 * _sb));

    // The umbra: one pass, left to right, over about two and a half seconds
    // of the turn. Nothing reverses -- an eclipse is a body going past, and
    // the body has a leading edge that covers and a trailing edge that
    // uncovers, which is one interval sliding rather than two movements.
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
        // The limb left burning round the edge at totality. It is the one
        // thing on screen during the darkest second of the stage.
        if (_total > 0.01) {
            var _rs = _r * 2.16 / sprite_get_width(spr_fx_ring);
            draw_sprite_ext(spr_fx_ring, 0, _cx, _cy, _rs, _rs, 0,
                            merge_colour(_col, _b.moon_b, 0.8), _total * 0.55);
        }
    }

    // The shockwave: one ring leaving the moon as it comes out of the shadow.
    var _w = grove_wave_t(_b);
    if (_w > 0 && _w < 0.62) {
        var _p = _w / 0.62;
        var _rr = (_r + _p * _v.w * 1.5) * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _cx, _cy, _rr, _rr, 0, _b.moon_b,
                        (1 - _p) * 0.42);
        // ...and the flash it leaves on the whole field for a few frames.
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

/// @desc The moon's light spread along the horizon behind the far wood.
///
///       **The treeline needs something to be a silhouette against**, and
///       without this it had nothing: the far wood is near-black, the sky at
///       the horizon was near-black, and the whole band simply was not in the
///       picture -- which left the ground meeting the sky along a ruled
///       horizontal line straight across the field, with the bottom of the
///       moon cut off flat by it.
///
///       It is also what a moon low over a wood actually does. One wide,
///       squashed bloom is the entire implementation.
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

/// @desc The far wall of wood, standing on the horizon.
///
///       Two copies at two scales and two drift rates: the near one is the
///       edge of the clearing and the far one is everything behind it. It is
///       the cheapest depth in the stage -- one sprite, two draws -- and it
///       is what stops the ground meeting the sky along a ruled line.
function grove_draw_treeline(_b, _v, _sb) {
    var _hy = corridor_horizon(_v);
    var _far = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _sb),
                            _b.air_n, 0.55);
    var _near = merge_colour(_b.tree_n, _b.tree_b, _sb);
    var _sc = _v.w / sprite_get_width(spr_scn_treeline);
    var _h = sprite_get_height(spr_scn_treeline) * _sc;

    // **Barely moving, and opaque.** This was reported as flat transparent
    // branches sliding horizontally in front of the moon, and both halves of
    // that were true: it ran at a fifth and two fifths of the flight speed --
    // a *sideways* motion the camera is not making, which the eye reads as a
    // sheet of acetate pulled across the picture -- and it was drawn under
    // one, so the moon came through it. A far wall of wood does not slide and
    // you cannot see through it. What is left is a drift slow enough to read
    // as the path bending.
    corridor_draw_band(_v, spr_scn_treeline, _b.drift * 0.05,
                       _hy - _h * 0.92, _sc * 0.92, _far, 1);
    corridor_draw_band(_v, spr_scn_treeline, _b.drift * 0.09 + 611,
                       _hy - _h * 1.16 + 8, _sc * 1.16, _near, 1);
}

/// @desc The colour of the ground at depth `_z`.
///
///       **Bands of root and moss, and they are periodic in *depth*.** That is
///       the whole reason the floor sells the speed: a stripe every couple of
///       hundred world units, evaluated per screen row through the inverse
///       projection, comes out already bunched at the vanishing point and
///       stretched under the camera -- and it rushes toward the player at
///       exactly the rate the trees do, because it is the same number moving.
///
///       The banding is faded out with distance rather than being drawn to
///       the horizon: at the far end a stripe is thinner than a row and what
///       that draws is a shimmering moire.
function grove_ground_shade(_b, _z, _out, _step) {
    var _blood = grove_blood_at(_b, _z);
    var _base = merge_colour(_b.grnd_n, _b.grnd_b, _blood);
    var _moss = merge_colour(_b.moss_n, _b.moss_b, _blood);

    // How much of the band survives the air in front of it. Faded out with
    // distance rather than drawn to the horizon: at the far end a stripe is
    // thinner than a row of the strip and what that draws is a moire.
    var _k = corridor_haze(_z);

    // **Two periods, because one is water.** A single sinusoid in depth draws
    // a set of smooth horizontal bands of one width, evenly spaced, filling
    // the bottom half of the screen -- which is a very good picture of a
    // calm lake and a very poor one of a forest floor. The second period is
    // not a harmonic of the first, so the two never line up and the floor has
    // ridges of two sizes on it, which is what ground does. Same finding as
    // the two-scale grain on the brimstone rock, one axis over.
    // **Each period is faded out once a row of the strip is wider than it
    // is, and that is the whole of the flicker fix.** A band a hundred and
    // thirty world units across is many rows wide under the camera and a
    // fraction of one near the horizon -- and a pattern sampled below its own
    // Nyquist rate does not draw finely, it draws a *coarse* pattern that
    // crawls and shimmers as the camera moves. It was reported as the ground
    // flickering, and it was worst for the second period, which is a third of
    // the first and so aliases three times as far down the screen.
    //
    // `_step` is how deep a row is; a period is safe once it is about twice
    // that. There is no texture to mip here, so the fade lives in the
    // function that makes the pattern.
    var _p1 = GROVE_GROUND_BAND;
    var _p2 = GROVE_GROUND_BAND * 0.31;
    var _n1 = clamp(_p1 / max(0.001, _step * 2), 0, 1);
    var _n2 = clamp(_p2 / max(0.001, _step * 2), 0, 1);
    var _c1 = 0.5 - 0.5 * dcos(((_z + _b.dist) / _p1) * 360);
    var _c2 = 0.5 - 0.5 * dcos(((_z + _b.dist) / _p2) * 360);
    // Held at two thirds, because the moss is three times the value of the
    // earth it is growing on and a band that reached it would be a stripe
    // rather than a ridge.
    // **Quiet, because it is no longer the ground.** These bands were the
    // whole floor for three passes; what they are now is the air over it, and
    // a hint of ridging where the texture has faded out with distance, so
    // they run at a third of the strength they were tuned at.
    var _band = (power(_c1, 2.4) * 0.66 * _n1
                 + power(_c2, 2.8) * 0.34 * _n2) * _k * 0.24;

    // ...and darkened again as it comes under the camera. **The bottom of the
    // frame is where the player lives**, so it is where a bullet most has to
    // read, and the nearest ground is also the ground the moon reaches least.
    var _near = clamp((600 - _z) / 420, 0, 1);

    // **The ground at infinity is the sky, because that is what a horizon
    // is.** Aerial perspective removes most of the join on its own -- what is
    // far away is the colour of what is between you and it -- but "most" is
    // not enough for a line the full width of the field: the first version
    // faded the far floor toward the *fog*, which is a slightly different
    // colour from the lit sky above it, and what that left was a nine-unit
    // step running straight across the picture at the vanishing point. Fading
    // it toward the same colour the sky is drawn in makes the two meet by
    // construction rather than by tuning, which is the only way a join like
    // this stays closed the next time either end is re-coloured.
    _out.col = grove_dim(_b, merge_colour(
        merge_colour(merge_colour(_base, _moss, _band),
                     merge_colour(_b.sky_n, _b.sky_b, _blood),
                     power(1 - _k, 1.3)),
        merge_colour(_b.air_n, _b.air_b, _blood),
        _near * 0.55), _blood);
    // **Opaque, and that had to be found by looking.** It was faded toward
    // the air at the horizon on the reasoning that a floor should dissolve
    // into distance -- and what a translucent floor let through was the
    // bottom half of the *moon*, which sits behind the horizon. A bright disc
    // with a straight cut across it and the ground showing through the lower
    // half is not something anybody reads as a moon. The dissolving is the
    // mist's job, and the mist is drawn over the top of this.
    _out.a = 1;
}

/// @desc The forest floor: a texture laid down the corridor.
///
///       **This is the layer the ground actually is; the colour ramp under it
///       is only the air.** A ground plane shaded per screen row can draw
///       nothing but horizontal bands, because in this projection a row *is* a
///       depth -- so however carefully those bands are tuned, what they draw is
///       a set of stripes across the screen, and what the eye makes of that is
///       water. It was reported twice, first as a pond and then as a flat
///       expanse with props tossed on it, and both were right: there was
///       nothing on the floor that had a *position*.
///
///       So the floor is one tile of leaf litter, roots, moss and twigs --
///       periodic in both axes, see `make_floor` -- laid down the corridor in
///       bands. Each band shows a slice of the tile stretched between two
///       screen rows and tiled sideways at that band's own scale, which is
///       perspective-correct sideways and near enough vertically at
///       `GROVE_FLOOR_ROW` pixels a band.
///
///       **A band fades out once its own depth span approaches a whole tile**,
///       which is the same Nyquist argument the colour bands make one function
///       down: past that it is showing more than a tile in a few pixels, and
///       what that draws is not fine detail, it is a coarse pattern that
///       crawls. Beyond it there is fog, which is what a forest floor at that
///       distance is anyway.
function grove_draw_floor(_b, _v) {
    var _hy = corridor_horizon(_v);
    var _th = sprite_get_height(spr_scn_floor);

    // Bottom to top, because the near bands are the ones worth spending on
    // and the far ones are the ones that get refused.
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

        // How much of this band survives the air in front of it and being
        // asked to show more of the tile than it has pixels for.
        var _zm = (_zn + _zf) * 0.5;
        // **Opaque where it is drawn at all.** The colour ramp under this is
        // the *air*, not the ground -- so a floor laid over it at half alpha
        // is a floor seen through half a screen of fog, which photographed as
        // a flat green expanse with a suggestion of something under it. What
        // fades here is distance and nothing else.
        var _a = corridor_haze(_zm);
        if (_a <= 0.01) continue;

        var _blood = grove_blood_at(_b, _zm);
        var _near = clamp((600 - _zm) / 420, 0, 1);
        // **The tint is the floor's brightest value, not its average.** The
        // texture carries its own range -- litter and stones near white,
        // twigs near black -- so multiplying it by a mid colour halves the
        // contrast the texture was drawn to have. This is the peak; the
        // texture does the rest.
        var _col = grove_dim(_b,
            merge_colour(merge_colour(_b.floor_n, _b.floor_b, _blood),
                         merge_colour(_b.air_n, _b.air_b, _blood),
                         _near * 0.42), _blood);

        // Which level of the chain this band wants, and the two either side
        // of it. Cross-faded rather than switched: a step in texture scale
        // across the floor is the same visible line the whole chain is here
        // to remove.
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

/// @desc One band of floor at one level of the chain.
///
///       Level `_lvl` lays the tile out at `2^_lvl` times its world size,
///       which is legal only because the tile is periodic in both axes -- see
///       `fbm2` and `_floor_marks` in `tools/make_grove.py`. A coarser level
///       is the same picture of the same wood at a distance where the leaves
///       in it would be a pixel across.
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

    // Which slice of the tile. `q` counts tiles travelled, so the row in the
    // sprite is one *minus* its fraction -- deeper is higher up the texture,
    // which is the orientation that keeps the litter the right way up and the
    // roots running away from the camera rather than at it.
    var _sn = (1 - frac((_zn + _b.dist) / _fz)) * _th;
    var _sf = (1 - frac((_zf + _b.dist) / _fz)) * _th;

    if (_sf <= _sn) {
        grove_floor_band(_v, _m0, _m1, _bw, _y0, _y1, _sf, _sn, _col, _a);
        return;
    }

    // **The band crosses a tile boundary, and then it is two draws.**
    // Wrapping the source rectangle instead would fold the top of the tile
    // onto the bottom of the band, which at this speed is a visible tear
    // sweeping up the screen once a second. The split is where the source
    // runs off the bottom of the texture, which is `_sn` of the
    // `_sn + (_th - _sf)` rows the band covers in total.
    var _run = _sn + (_th - _sf);
    var _cut = _y1 + (_y0 - _y1) * (_sn / max(1, _run));
    grove_floor_band(_v, _m0, _m1, _bw, _cut, _y1, 0, _sn, _col, _a);
    grove_floor_band(_v, _m0, _m1, _bw, _y0, _cut, _sf, _th, _col, _a);
}

/// @desc One band of floor, tiled across the view.
///
///       `_sf`..`_sn` is the slice of the tile it shows, top to bottom, and
///       `_y0`..`_y1` is where that slice lands. Split out because a band that
///       crosses a tile boundary is drawn twice, and the tiling loop is the
///       part that would otherwise be written twice with it.
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

/// @desc The track worn down the middle of the wood.
///
///       **The floor needs something that is not a horizontal stripe.** The
///       ground bands are periodic in depth, which is exactly what sells the
///       speed and is also, on its own, a picture of ruled lines going across
///       the screen -- read at a glance the first version of this floor was
///       water. A path is the one piece of lateral structure a corridor gets
///       for free: it is the same trapezoid the trees are standing either side
///       of, so it is already in the composition, and it converges on the
///       vanishing point without anything having to be told where that is.
///
///       Three nested wedges rather than one. A single hard-edged trapezoid
///       reads as a shape laid on the floor; three, each a little narrower and
///       a little lighter, read as a track that has been walked on -- and it
///       is cheaper than the soft edge a per-row alpha would have needed,
///       because a triangle strip has two vertices a row and a soft edge
///       wants four.
function grove_draw_path(_b, _v) {
    var _hy = corridor_horizon(_v);
    var _y0 = _hy + 2;
    if (_y0 >= _v.y1) return;

    // **Five wedges rather than three.** Each one has a hard edge -- a
    // triangle strip has two vertices a row, so there is nowhere to put a
    // soft one -- and at three the outermost of them photographed as a
    // visible trapezoid laid on the floor. Five at three fifths of the alpha
    // is the same track with its edge spread over five steps, which the mist
    // drawn over the top then finishes off.
    for (var _n = 0; _n < 5; _n++) {
        var _wide = GROVE_PATH_HALF * (0.98 - _n * 0.17);
        draw_primitive_begin(pr_trianglestrip);
        for (var _i = 0; _i <= 20; _i++) {
            var _sy = _y0 + (_v.y1 - _y0) * (_i / 20);
            var _z = corridor_depth_at(_v, _sy);
            var _k = corridor_k(_z);
            var _hw = _k * _wide;
            // Fades out toward the horizon with everything else, and again as
            // it comes under the camera -- a track directly beneath you is
            // not a shape, it is the ground.
            var _a = 0.09 * corridor_haze(_z) * clamp((_z - 260) / 500, 0, 1);
            // **Darker than the floor it is worn into**, which is both what a
            // trodden path looks like and the one thing that helps the
            // danmaku: the track runs up the middle of the field, which is
            // where the player lives and where a bullet most has to read.
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

/// @desc Moonlight coming through the canopy and lying on the floor.
///
///       **A forest floor is not evenly lit and that is most of why an evenly
///       lit one reads as a lawn.** The texture gives the ground things with
///       positions; this gives it *light* with positions, which is the other
///       half -- the eye reads a scattering of pools and shadows between them
///       as a canopy overhead without anything having to draw one.
///
///       Additive, clock-derived and projected exactly like the fog it is
///       drawn beside, so it costs one loop and nothing to step. It goes out
///       with everything else at totality, because the only thing casting it
///       is the moon.
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

        // Foreshortened hard: a circle of light on a plane seen at a glancing
        // angle is an ellipse a fifth as tall as it is wide, and a round one
        // reads as a lamp hanging in mid-air rather than as light on the
        // ground.
        var _w = _k * (240 + 320 * corridor_hash(_i + _lap * 13, 28)) / _bw;
        var _a = 0.10 * _b.light * min(1, _u * 5) * min(1, (1 - _u) * 3);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _w, _w * 0.22, 0,
                        merge_colour(_b.moon_n, _b.moon_b, _sb), _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Banks of fog lying on the floor and rushing past the camera.
///
///       **This is the layer that stops the floor being a floor.** The ground
///       plane is periodic in depth and uniform across the frame, so however
///       well it is banded it can only ever draw horizontal stripes -- and a
///       set of smooth horizontal stripes filling the bottom half of the
///       screen is a picture of water. What breaks it is something with a
///       *position* moving through it, and the cheapest such thing is a dozen
///       soft ellipses projected exactly like the trees.
///
///       Additive and derived from the clock, so there is nothing to order and
///       nothing to step -- the same bargain the wisps make, and the same one
///       `bg_draw_embers` made before either of them existed.
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
        // Wide and flat: fog on the ground is a sheet, and an ellipse with a
        // circle's proportions reads as a puff of smoke instead.
        var _w = _k * (700 + 600 * corridor_hash(_i + _lap * 17, 14)) / _bw;
        var _h = _w * 0.20;
        var _a = 0.085 * min(1, _u * 5) * min(1, (1 - _u) * 3);
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _w, _h, 0, _col, _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The mist at the vanishing point. Three bands at three rates.
///
///       **Additive without exception**, here and in the foreground pass.
///       Mist in a moonlit wood is light being scattered toward the eye, so
///       adding it is not an approximation of what it does, it is what it
///       does -- and an additive layer can only ever brighten what is behind
///       it, which means no arrangement of it can hide a bullet.
function grove_draw_mist(_b, _v, _sb, _front) {
    var _hy = corridor_horizon(_v);
    var _col = merge_colour(_b.haze_n, _b.haze_b, _sb);
    var _sc = _v.w / sprite_get_width(spr_scn_mist);
    var _h = sprite_get_height(spr_scn_mist) * _sc;
    // The mist stills through the eclipse and picks up again behind the wave,
    // which is the quietest of the four movements and the one that makes the
    // others land.
    var _still = _b.light;

    if (_front) {
        corridor_draw_band(_v, spr_scn_mist, -_b.drift * 3.4 + 210,
                           _v.y1 - _h * 0.72, _sc * 1.7, _col, 0.10 * _still);
        return;
    }
    // **Thickest at the vanishing point and thinning fast as it comes
    // forward.** Mist reads as distance, so mist in the near half of the
    // frame reads as no distance -- and it is the near half the player is
    // dodging in. The first pass ran all three bands at one alpha and laid a
    // pale wash over the whole floor.
    corridor_draw_band(_v, spr_scn_mist, _b.drift * 0.5,
                       _hy - _h * 0.42, _sc, _col, 0.17 * _still);
    corridor_draw_band(_v, spr_scn_mist, -_b.drift * 0.9 + 400,
                       _hy + _v.h * GROVE_MIST_Y - _h * 0.5, _sc * 1.25, _col,
                       0.13 * _still);
    corridor_draw_band(_v, spr_scn_mist, _b.drift * 1.6 + 830,
                       _hy + _v.h * GROVE_MIST_Y * 2.6 - _h * 0.5, _sc * 1.5,
                       _col, 0.07 * _still);
}

/// @desc Every prop in a ring, far to near, with whatever is hanging in it.
function grove_draw_one(_b, _v, _p) {
    // What this kind of prop is made of. **A switch rather than four loops**,
    // which is what merging the rings into one depth-sorted pass costs: the
    // sprite becomes a property of the prop rather than of the loop it is in.
    var _spr, _rim, _wh, _rim_k, _anchor, _yflip;
    switch (_p.kind) {
        case GROVE_KIND_TRUNK:
            _spr = spr_scn_trunk; _rim = spr_scn_trunk_rim;
            // **The trunks get three times the rim every other prop gets**,
            // because they are the only things in the wood big enough for the
            // lit edge to be a small fraction of them. On a bare branch a rim
            // of a fixed width is most of the twig, so it has to be faint or
            // the wood is a cage of glowing wire; on a trunk four hundred
            // pixels across it is a highlight down one side, which is the only
            // thing separating a near trunk from a hole in the picture.
            _wh = GROVE_TRUNK_H; _rim_k = 3.0;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
        case GROVE_KIND_BUSH:
            _spr = spr_scn_bush; _rim = spr_scn_bush_rim;
            _wh = GROVE_BUSH_H; _rim_k = 1;
            _anchor = CORRIDOR_CAM_H; _yflip = 1;
            break;
        case GROVE_KIND_BOUGH:
            _spr = spr_scn_tree; _rim = spr_scn_tree_rim;
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
    // Its own height, not the kind's. Everything below this line -- the body,
    // the rim, the mound and whatever is hanging in it -- is measured from
    // `_h`, so a prop drawn at four fifths of nominal has its charms four
    // fifths of the way up it as well.
    var _h = _wh * _p.scale;

    // **Off the side of the frame is the ordinary way a prop leaves**, so it
    // is worth refusing early: at the near plane a tree is four times the
    // height of the field and entirely outside it, and drawing it is a
    // texture fetch across the whole screen for nothing.
    var _half = _k * _h * 0.6;
    if (_sx + _half < _v.x0 || _sx - _half > _v.x1) return;

    var _haze = corridor_haze(_p.z);
    // What is left of it after the near plane and after its own ring's far
    // one. The second half is what stops a prop arriving at whatever opacity
    // the global haze happens to be at that depth.
    var _fade = corridor_near_fade(_p.z) * corridor_prop_fade(_p);
    var _blood = grove_blood_at(_b, _p.z);
    var _flare = grove_flare_at(_b, _p.z);

    // Depth is value: a far tree lifts toward the fog it is seen through, and
    // only the near ones are allowed to be black.
    var _col = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _blood),
                            merge_colour(_b.fog_n, _b.fog_b, _blood),
                            power(1 - _haze, 1.4));
    var _rc = grove_dim(_b, merge_colour(_b.rim_n, _b.rim_b, _blood), _blood);

    // **The rim is a hint, not a light.** It went in at three times this and
    // what came back was a wood of pale blue skeletons: a rim of a fixed width
    // is most of a *twig*, so on bare branches it stops being an edge and
    // becomes the whole object. The moon is the only bright thing in this
    // stage; everything else is the shape of something dark.
    corridor_draw_prop(_v, _spr, _rim, _p.frame, _p.z, _p.wx, _h,
                       _p.flip, _col, _rc, _p.a * _fade,
                       (0.10 + 0.20 * _haze + 0.7 * _flare) * _rim_k * _fade,
                       _p.aspect, _anchor, _yflip);

    // Only things standing on the ground bank litter against themselves.
    if (_yflip > 0) grove_draw_mound(_b, _v, _p, _spr, _h, _col, _fade);

    if (_p.tag < 0) return;
    if (_p.kind == GROVE_KIND_TREE) {
        grove_draw_charm(_b, _v, _p, _h, _haze, _fade, _blood, _flare);
    } else if (_p.kind == GROVE_KIND_TRUNK) {
        grove_draw_ivy(_b, _v, _p, _h, _haze, _fade, _blood);
    }
}

/// @desc The debris piled where a trunk meets the ground.
///
///       **A billboard has a flat bottom and the ground does not.** A trunk is
///       drawn as a fragment that leaves the top of its own frame, so its
///       sprite necessarily ends in a ruled horizontal line at the base -- and
///       photographed at the size the near ones are drawn, that line is the
///       give-away: it reads as a cardboard cutout standing on a floor rather
///       than as something growing out of it.
///
///       There is no fix for this in the art, because the cut is the sprite's
///       own edge. What fixes it is what fixes it in a real wood: leaf litter
///       and roots bank up around a trunk, so the join is never a line
///       anywhere. One soft dark ellipse at the foot of every prop, in the
///       prop's own colour, and the line is gone.
///
///       Drawn normally rather than additively -- it is the one thing in the
///       scenery that has to *remove* light. It can afford to: this is the
///       background pass, and every bullet in the game is drawn over it.
function grove_draw_mound(_b, _v, _p, _spr, _wh, _col, _a) {
    if (_a <= 0.01) return;
    var _k = corridor_k(_p.z);
    var _y = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    // **Only when the foot is actually in the picture.** A near trunk's base
    // is a long way below the bottom of the field, and so is the cut -- there
    // is nothing to hide and a mound drawn there is a wide dark ellipse over
    // the floor for no reason.
    if (_y < _v.y0 - 40 || _y > _v.y1 + 40) return;

    var _w = _k * 2 * corridor_prop_half_w(_spr, _wh, 1, _p.aspect);
    if (_w < 8) return;
    var _x = _v.cx + _k * _p.wx;
    if (_x + _w < _v.x0 - 40 || _x - _w > _v.x1 + 40) return;

    // **A strip rather than a bloom, and the reason is what a bloom is.**
    // `spr_fx_bloom` is `soft_glow` with a falloff of 2.9: its alpha is above
    // four fifths only within seven per cent of its radius, which is exactly
    // right for a light and useless as a fill. Drawn at the width of a trunk
    // it covered the cut with about eight per cent opacity and the ruled line
    // was still plainly there. This is the shape that was wanted all along --
    // opaque along the ground line and dissolving downward into the litter,
    // tapering to nothing at both ends.
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

/// @desc One hex hanging off one branch of one tree.
///
///       **The branch is the sprite's, not a guess.** `tools/make_grove.py`
///       works out where each tree's branch tips are as it draws them and
///       writes them into `scripts/grove_table`, so a charm hangs off wood
///       rather than off a coordinate somebody eyeballed -- and a tree
///       redrawn tomorrow moves its charms with it.
function grove_draw_charm(_b, _v, _p, _wh, _haze, _fade, _blood, _flare) {
    var _hang = grove_hang_at(_p.frame, _p.hang);
    var _k = corridor_k(_p.z);
    var _ts = _k * _wh / sprite_get_height(spr_scn_tree);

    // The sprite's origin is the foot of its trunk, so a point in its own box
    // is an offset from there.
    var _bx = _v.cx + _k * _p.wx;
    var _by = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    var _x = _bx + (_hang[0] - 0.5) * sprite_get_width(spr_scn_tree)
                   * _ts * _p.aspect * _p.flip;
    var _y = _by + (_hang[1] - 1) * sprite_get_height(spr_scn_tree) * _ts;

    var _cs = _k * GROVE_CHARM_H / sprite_get_height(spr_scn_charm);
    // It swings. The origin is the top of the cord, so a rotation *is* a
    // pendulum and nothing has to be worked out.
    var _ang = dsin(_b.t * 1.1 + _p.sway) * GROVE_CHARM_SWAY;

    var _wood = merge_colour(merge_colour(_b.tree_n, _b.tree_b, _blood),
                             merge_colour(_b.air_n, _b.air_b, _blood),
                             1 - _haze);
    draw_sprite_ext(spr_scn_charm, _p.tag, _x, _y, _cs, _cs, _ang,
                    merge_colour(_wood, c_white, 0.22 * _haze), _fade);

    // What is burning in it. **The one place in this wood allowed a second
    // hue**: everything else is the moon's colour at some distance, and a hex
    // on a cord is the only thing out here somebody made.
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

/// @desc Ivy climbing a trunk.
///
///       **The only saturated hue in the wood that is not a light.** Two
///       clusters up the side of the trunk facing the moon -- on the moonward
///       side because that is the side with any light on it at all, and a
///       green in shadow is a grey.
function grove_draw_ivy(_b, _v, _p, _wh, _haze, _fade, _blood) {
    var _k = corridor_k(_p.z);
    var _bx = _v.cx + _k * _p.wx;
    var _by = corridor_horizon(_v) + _k * CORRIDOR_CAM_H;
    var _ts = _k * _wh / sprite_get_height(spr_scn_trunk);
    var _tw = sprite_get_width(spr_scn_trunk) * _ts * _p.aspect;
    var _ls = _k * GROVE_IVY_H / sprite_get_height(spr_scn_leaf);

    // The moonward side is the inner one, and `flip` already says which that
    // is: a trunk left of the path is flipped so its lit edge faces the
    // middle, and the ivy goes on the same edge for the same reason.
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

/// @desc Spirit lights streaming past the camera.
///
///       **Derived from the clock, with no pool and nothing to step.** These
///       are the one thing in the corridor that can be: they are additive, so
///       nothing has to be drawn in order, and where a wisp is this frame is
///       `frac` of a phase and the distance flown. It is `bg_draw_embers`'
///       bargain with a projection in front of it.
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
        // Fades up out of the far haze and out again as it leaves, so nothing
        // pops at either end of its run.
        var _a = _alpha * min(1, _u * 6) * min(1, (1 - _u) * 3.5)
                 * (0.6 + 0.4 * dsin(_b.t * 2.1 + _i * 61));
        // The wisps are their own light, so they survive the eclipse the way
        // the hexes do -- for the two seconds the moon is gone they and the
        // charms are the only things in the wood that are visible at all,
        // which is what that beat is for.
        draw_sprite_ext(spr_fx_bloom, 0, _x, _y, _s, _s, 0,
                        merge_colour(_b.wisp_n, _b.wisp_b,
                                     grove_blood_at(_b, _z)), _a);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc Darken the view inward from its own edges.
///
///       The same four strips the forge ends on and for the same reason: a
///       composition that converges on a vanishing point sits in a rectangle
///       with four bright corners, and without this the eye goes to the
///       corners. It is the cheapest single thing that separates a background
///       somebody made from one something generated.
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

/// @desc What passes between the player and the wood.
///
///       **Every draw in this function is additive, and that is a fairness
///       rule rather than a look.** The near parallax layer of stage one is
///       opaque art held down to `BG_NEAR_ALPHA` and kept out of the middle of
///       the screen by a window, because an opaque foreground over live
///       danmaku does not hide scenery, it hides *bullets* -- which reached a
///       player as "I am taking damage and there is nothing on screen".
///
///       A corridor cannot keep out of the middle: the whole idea is that
///       things come at the camera. So it takes the stronger rule instead.
///       Light can only ever brighten what is behind it, so an additive
///       foreground cannot conceal a bullet at any alpha, at any size, in any
///       arrangement -- which is a guarantee the keep-out window only ever
///       approximated. What is given up is the ability to put a solid branch
///       in front of the player, and that is not a loss worth arguing about.
///
///       It stands down for a spell background on the same terms the parallax
///       foreground does: a wash that works by subtraction cannot have a
///       foreground that opted out of it.
function grove_draw_front(_b, _spell, _fill) {
    var _a = 1 - 0.86 * clamp(_spell, 0, 1);
    if (_a <= 0.02) return;
    var _v = corridor_view(_fill);
    var _sb = grove_sky_blood(_b);

    gpu_set_blendmode(bm_add);

    // The lit edges of whatever is closest. A branch sweeping past the camera
    // as a line of moonlight, with no mass behind it.
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
    // Spores close to the lens, moving fast because they are close. The whole
    // of what says "this is the front" is their speed.
    grove_draw_wisps(_b, _v, 22, 900, 9.0, 0.30 * _a);
}

// ---------------------------------------------------------------------------
// The caster's spell background
// ---------------------------------------------------------------------------

/// @desc The grove's: the wood is replaced by a rite.
///
///       **A place, not a colour**, which is the rule Ziggy's forge is written
///       to. Nothing here reads `_col`: the caster keeps a bone-and-ivy circle
///       whatever the spell's own hue is, and the spell's colour lives where
///       it belongs -- on the bullets, the banner and the notch in the bar.
///
///       Four things and a vignette: a wash, a ring of standing runes turning
///       against a second one, the blood moon low behind it, and her antlers
///       rising out of the bottom corners. The antlers are the forge's horns
///       argument exactly -- a contour leaving the frame is completed by the
///       eye into a mass too big to be in the picture -- and they are the one
///       part of this that says *who*.
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

    // The moon she is standing in front of, low and enormous.
    var _ms = (FIELD_W * 0.62) / sprite_get_width(spr_scn_moon);
    draw_sprite_ext(spr_scn_moon, 0, _fx, _fy + 40, _ms, _ms, 0, _blood,
                    0.30 * _fade * (0.9 + 0.1 * dsin(_t * 0.8)));

    var _bw = sprite_get_width(spr_fx_bloom);
    var _bs = (FIELD_W * 1.1) / _bw;
    draw_sprite_ext(spr_fx_bloom, 0, _fx, _fy, _bs, _bs, 0, _blood,
                    0.13 * _fade * (0.84 + 0.16 * dsin(_t * 1.2)));

    // Two circles of standing runes, counter-turning. Slow -- a rite is not
    // a machine.
    var _ss = 1420 / sprite_get_width(spr_boss_sigil);
    draw_sprite_ext(spr_boss_sigil, 0, _fx, _fy, _ss, _ss, _t * 0.09, _bone,
                    0.10 * _fade);
    draw_sprite_ext(spr_boss_sigil, 0, _fx, _fy, _ss * 0.58, _ss * 0.58,
                    -_t * 0.17, _ivy, 0.09 * _fade);

    // What travels: a ring pushing out every four seconds, which is the one
    // thing in here doing something rather than turning.
    for (var _i = 0; _i < 3; _i++) {
        var _p = frac(_t / 240 + _i / 3);
        var _rr = (140 + _p * 1400) * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _fx, _fy, _rr, _rr, 0, _bone,
                        (1 - _p) * 0.11 * _fade);
    }

    // Her antlers, out of the bottom corners. Mirrored about their own root,
    // which is exactly the other side of a head.
    // **Bigger than the frame can hold, which is the whole trick.** At the
    // size these started they were two pale twigs in the corners; a contour
    // that *leaves* the picture is completed by the eye into a mass too big
    // to be in it, and that only happens once the thing is plainly running
    // off the edge. Same finding as Ziggy's horns, one background over.
    var _as = 1.9;
    var _aa = 0.46 * _fade * (0.88 + 0.12 * dsin(_t * 0.9));
    draw_sprite_ext(spr_scn_antler, 0, FIELD_X0 - 60, FIELD_Y1 + 150,
                    -_as, _as, 0, _bone, _aa);
    draw_sprite_ext(spr_scn_antler, 0, FIELD_X1 + 60, FIELD_Y1 + 150,
                    _as, _as, 0, _bone, _aa);

    // Leaves and ash going up through it, half of each. Grey is the only
    // thing in this game that is never a bullet, so it can be as busy as it
    // likes; the green is hers.
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
