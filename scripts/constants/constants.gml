/// @desc The game's tuning numbers and enums.
///
/// The game runs on a fixed 60 Hz step and every duration is a frame count;
/// `delta_time` is not allowed in `scripts/` (checked by
/// `check_delta_time_in_rules`). Durations easier to think of in seconds are
/// written as `seconds * FPS`.

#macro FPS 60

// ---------------------------------------------------------------------------
// The screen
//
// The design resolution. Only things that own the whole display (title, pause
// scrim, result panel, flash) measure from `GAME_*`; the playfield measures
// from `FIELD_*` and the readouts from `HUD_*`.
// ---------------------------------------------------------------------------

#macro GAME_W 1920
#macro GAME_H 1080
#macro GAME_CX 960
#macro GAME_CY 540

// ---------------------------------------------------------------------------
// The field
//
// The playfield is a rectangle inside the screen with a 44px margin on three
// sides and the console plate on the fourth. No HUD element may overlap it
// (`test_hud_layout`); the boss's health rail is the one thing drawn inside
// it.
// ---------------------------------------------------------------------------

#macro FIELD_X0 44
#macro FIELD_Y0 44
#macro FIELD_W 1360
#macro FIELD_H 992

#macro FIELD_X1 (FIELD_X0 + FIELD_W)
#macro FIELD_Y1 (FIELD_Y0 + FIELD_H)
#macro FIELD_CX (FIELD_X0 + FIELD_W / 2)
#macro FIELD_CY (FIELD_Y0 + FIELD_H / 2)

// The frame drawn round it: how thick, and how far the glow reaches in.
#macro FIELD_EDGE 3
#macro FIELD_GLOW 26

// The ornamented outer frame. `UI_CORNER_INSET` is how far into its own
// sprite the corner piece draws its bracket, and `UI_CORNER_DEPTH` is the
// deepest ink in it; both mirror `tools/make_ui.py` (`o` and `o + chamfer`)
// and must be changed together with it. The rule the corners stand on is
// derived from them, and the corner pieces must stay out of the field.
#macro UI_CORNER_INSET 11
#macro UI_CORNER_DEPTH 37

#macro FIELD_ORN_SCALE 0.62
#macro FIELD_ORN_OUT 24
#macro FIELD_RULE_OUT (FIELD_ORN_OUT - UI_CORNER_INSET * FIELD_ORN_SCALE)

// How far in from the field's edge the player is held.
#macro FIELD_MARGIN 34

// A bullet is culled this far outside the field, so patterns can enter from
// off-screen. One value for the whole game.
#macro CULL_MARGIN 160

// Stage one's near parallax layer draws over the field, so it keeps to this
// share of the field's width at each edge (built to by `tools/make_bg.py`,
// measured by `check_bg_keepout`) and is never more opaque than
// `BG_NEAR_ALPHA`, so a bullet reads through it.
#macro BG_NEAR_EDGE 0.13
#macro BG_NEAR_ALPHA 0.42

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

// Speeds are scaled for this field's size rather than copied from Touhou's
// 384px strip.
#macro PLAYER_SPD 11.0
#macro PLAYER_SPD_FOCUS 4.6

// The hitbox, drawn at exactly this size when focused.
#macro PLAYER_R 4.0
#macro GRAZE_R 30.0

// A bullet pays a graze once; a laser pays every this many frames while the
// player rides it.
#macro LASER_GRAZE_CD 20

#macro HP_MAX 100
#macro HP_PER_HIT 25
#macro HP_QUADRANT 25          // where the markers on the bar go
#macro IFRAME_TIME (3 * FPS)   // invulnerable after a hit

#macro MP_MAX 100
#macro MP_PER_BOMB 25
#macro BOMB_INVULN 150         // grace on a special
#macro BOMB_CLEAR_R 560        // bullets inside this are swept
#macro BOMB_GROW 26            // frames the sweep takes to reach full radius

// The special (sigil): the sweep grows from the cast point and erases
// bullets, then `BOMB_SEAL_AT` frames later `BOMB_SEALS` wisps spiral out,
// hunt the nearest target and burst, each dealing `BOMB_SEAL_DMG`.
#macro BOMB_SEALS 6
#macro BOMB_SEAL_AT 40         // frames after the cast the seals leave
#macro BOMB_SEAL_CURL 24       // frames they spiral out before they hunt
#macro BOMB_SEAL_LIFE 96       // frames a seal lives if it finds nothing
#macro BOMB_SEAL_SPD0 7.5      // leaving the heart
#macro BOMB_SEAL_SPD 24        // top speed, hunting
#macro BOMB_SEAL_TURN 8.5      // degrees a frame, hunting
#macro BOMB_SEAL_R 26          // how close to a target counts as striking it
#macro BOMB_SEAL_WAKE 90       // bullets this close to a flying seal are swept
#macro BOMB_SEAL_BLAST 230     // ...and this close to where it bursts
#macro BOMB_SEAL_DMG 10
#macro BOMB_SIGIL_OUT 116      // the frame the circle has finished fading

// The close-up of Szuix shown as he casts (see `draw_eye_card`).
#macro PLAYER_CARD_TIME BOSS_EYE_TIME

// The grace dial round the player (see `player_draw_grace`): its radius at
// full and at empty, and the share of the grace left when it starts to
// flicker.
#macro GRACE_RING_R_FULL 80
#macro GRACE_RING_R_EMPTY 62
#macro GRACE_URGENT 0.3

// Frames per heartbeat of the one-hit-from-death warning.
#macro LOW_HP_BEAT 48

// The shot: two converging barrels, narrowed while focused.
#macro PSHOT_PERIOD 3          // frames between volleys
#macro PSHOT_SPD 36
#macro PSHOT_DMG 0.75
#macro PSHOT_SPREAD 7.0        // degrees off straight ahead, unfocused
#macro PSHOT_SPREAD_FOCUS 1.5
#macro PSHOT_OFFSET 26         // how far either side of centre a barrel sits

// How far in front of the player a bolt is born, so it clears his sprite
// (his horns are 56px above his origin).
#macro PSHOT_MUZZLE 62

#macro PLAYER_HIT_SHARDS 10    // recoverable shards scattered on a hit

// ---------------------------------------------------------------------------
// Pools
//
// Hard caps. A full pool refuses (the allocator returns `undefined`) rather
// than growing.
// ---------------------------------------------------------------------------

#macro BULLET_MAX 4096
#macro PSHOT_MAX 512
#macro ITEM_MAX 512
#macro ENEMY_MAX 128
#macro LASER_MAX 96
#macro RING_MAX 24
#macro PARTICLE_MAX 1024
#macro FLOATER_MAX 64          // floating text

// How many past positions a curved laser keeps, so its length is a number of
// frames.
#macro CURVE_NODES 64

// ---------------------------------------------------------------------------
// Bullets
// ---------------------------------------------------------------------------

// A bullet spends its delay as a harmless, stationary warning mark that
// starts this much larger than the bullet.
#macro BULLET_DELAY_DEFAULT 8
#macro BULLET_DELAY_SCALE 2.6

// The delay given to children of a split or shed.
#macro BULLET_SPLIT_DELAY 4

// When a phase is cleared, one shard is dropped per this many bullets swept.
#macro CLEAR_ITEM_EVERY 7

// ---------------------------------------------------------------------------
// Rings
//
// Furniture a boss puts down: indestructible, blocks player shots on its
// band, hurts to touch. See `ring_functions`.
// ---------------------------------------------------------------------------

// Every ring is this size; a ring has no radius of its own (owner's rule).
#macro RING_R 72

// Half the metal's thickness as a fraction of the radius. This is the
// sprite's own proportion, quoted in `tools/make_rings.py`, so the drawn band
// and the blocking band match.
#macro RING_BAND_FRAC 0.16
#macro RING_BAND_HALF (RING_R * RING_BAND_FRAC)

// Where the band's centre line sits in the sprite, as a fraction of its half
// width (200 of 256). Also mirrored in `make_rings.py`.
#macro RING_SPR_LINE 0.78125

// How much of the band kills: its core when cold, the whole drawn cuff when
// charged. Never wider than the drawn metal.
#macro RING_KILL_FRAC 0.62
#macro RING_HOT_KILL_FRAC 1.0

#macro RING_FORM 34                // frames arriving: no block, no kill
#macro RING_FADE 22                // frames leaving
#macro RING_WARN 40                // the default charge warning
#macro RING_GRAZE_CD 20            // graze cooldown, as a laser's

#macro RING_ARC_WID 26             // the current between two rings, drawn
#macro RING_ARC_NODES 14           // segments the bolt is jittered in

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------

#macro ITEM_R 30                   // collection radius
#macro ITEM_MAGNET_R 200           // drifts toward the player inside this
#macro ITEM_MAGNET_SPD 14
#macro ITEM_GRAVITY 0.22
#macro ITEM_TERMINAL 5.5
#macro ITEM_LIFE (14 * FPS)

#macro ITEM_HP_VALUE 1
#macro ITEM_MP_VALUE 1

// How the stones are drawn (see `item_draw`). Visual only.
#macro ITEM_TURN 0.45              // turns a second, give or take a fifth
#macro ITEM_POP 10                 // frames a new stone takes to arrive
#macro ITEM_FADE 50                // frames a stone takes to go out at ITEM_LIFE
#macro ITEM_GLOW_PX 54             // the light under each stone
#macro ITEM_GLINT_EVERY 150        // frames between twinkles, give or take
#macro ITEM_GLINT_LEN 18           // frames one twinkle lasts

// Above this line every item on the field is drawn to the player
// (Touhou's point-of-collection).
#macro ITEM_AUTO_LINE 240

// ---------------------------------------------------------------------------
// Scoring
//
// Points are called `tally`, never `score`: `score` is a legacy built-in
// global (see `check_legacy_globals`).
// ---------------------------------------------------------------------------

#macro TALLY_GRAZE 40
#macro TALLY_ENEMY 250
#macro TALLY_ITEM 120

// The flat award for ending an attack. A speed bonus is paid on top (see
// `rank_speed_award`); it is not voided by a hit.
#macro TALLY_SPELL_CLEAR 40000
#macro TALLY_PHASE_CLEAR 12000

// Breaking a spell with no hit and no sigil.
#macro TALLY_SPELL_CAPTURE 40000

#macro TALLY_NO_HIT_BONUS 100000

// ---------------------------------------------------------------------------
// Marks (see `rank_functions`)
// ---------------------------------------------------------------------------

// A clean encounter's mark; beating the score threshold adds one rung.
#macro RANK_BASE Mark.Gold

// What a mistake costs, in rungs.
#macro RANK_HIT_COST 2
#macro RANK_BOMB_COST 1

// Grazes per second the score threshold expects on top of what finishing the
// encounter pays. Unplayed.
#macro RANK_GRAZE_RATE 14

// A floor under a wave group's duration for its threshold.
#macro RANK_WAVE_MIN_TIME (4 * FPS)

// The rank card (see `rank_card`). Its length fits inside `BOSS_PHASE_PAUSE`.
#macro RANK_CARD_TIME 80
#macro RANK_CARD_STRIKE 6          // the medal arrives oversized and settles
#macro RANK_CARD_SETTLE 24         // ...with a small elastic under it
#macro RANK_CARD_GLINT_END 40      // the glint crossing its face
#macro RANK_CARD_FLY 24            // and it leaves for its socket

// Where the card is shown: above the player's half, below the boss's station.
#macro RANK_CARD_Y (FIELD_Y0 + FIELD_H * 0.38)

#macro RANK_CARD_SCALE 1.25        // the medal is authored at 176
#macro RANK_CARD_HOME_S 0.17       // ...and a socket is 30
#macro RANK_CARD_FRAMES 6          // five rungs and the perfect standing

// ---------------------------------------------------------------------------
// Enemies and bosses
// ---------------------------------------------------------------------------

#macro ENEMY_FLASH 5               // frames an enemy whitens when hit
#macro ENEMY_DEATH_BITS 14

#macro BOSS_ENTRY_TIME (2 * FPS)
#macro BOSS_DECLARE_TIME (3.4 * FPS)   // the name splash
#macro BOSS_PHASE_PAUSE (1.4 * FPS)    // invulnerable, between attacks

// The READY beat before a practised attack starts.
#macro PRACTICE_READY (2 * FPS)
#macro BOSS_SPELL_BANNER (2.6 * FPS)   // how long the spell name holds
#macro BOSS_EYE_TIME (1.5 * FPS)       // the eye card

// How long a spell declares itself before its pattern opens: the eye card's
// length. The boss is invulnerable and the phase clock stopped through it.
#macro BOSS_SPELL_LEAD BOSS_EYE_TIME

#macro BOSS_DRIFT_SPD 1.1

// `BossMove.Drift`: how far a boss wanders from its station, and how sharply
// it chases its wander point.
#macro BOSS_DRIFT_X 430
#macro BOSS_DRIFT_Y 74
#macro BOSS_DRIFT_RATE 0.075

// `BossMove.Track`: the station walks toward the player's column at this
// capped speed (not a proportional ease, which would be fastest when the
// player is furthest away), wanders `BOSS_TRACK_SWAY` either side of it so it
// is not directly overhead, and keeps its centre `BOSS_TRACK_EDGE` in from the
// field's sides.
#macro BOSS_TRACK_SPD 4.0
#macro BOSS_TRACK_SWAY 120
#macro BOSS_TRACK_EDGE 130

// Where a boss holds station, measured down the field.
#macro BOSS_HOME_Y (FIELD_Y0 + 250)

// The tallest ink any boss sprite carries above its origin, measured off the
// PNGs (Ziggy's horns: 100). The health rail's clearance is measured against
// it, so re-measure it when boss art changes.
#macro BOSS_INK_ABOVE 100

// ---------------------------------------------------------------------------
// The HUD
//
// One console plate right of the field, and the boss's health rail inside
// the top of the field. `hud_box` is the one place that knows where each
// readout is; `test_hud_layout` walks it.
// ---------------------------------------------------------------------------

// How far the console's contents are inset from its plate.
#macro HUD_PAD 24

// The colour of the console's small caption tags: gilt pulled toward the
// plate.
#macro HUD_TAG_COL merge_colour(COL_GILT, COL_ARCANE, 0.3)

// The console plate. It is the field's height and its top and bottom line up
// with the field's outer rule (`FIELD_RULE_OUT`), not with the field itself.
#macro HUD_PANEL_X0 (FIELD_X1 + 20)
#macro HUD_PANEL_X1 (GAME_W - 32)
#macro HUD_PANEL_Y0 (FIELD_Y0 - FIELD_RULE_OUT)
#macro HUD_PANEL_Y1 (FIELD_Y1 + FIELD_RULE_OUT)

#macro HUD_COL_X (HUD_PANEL_X0 + HUD_PAD)
#macro HUD_COL_W (HUD_PANEL_X1 - HUD_PAD - HUD_COL_X)

// The console's rows, top to bottom, measured from the plate's top. Written
// out as a list of positions; every readout row goes through `hud_row`.
#macro HUD_ROW_CREST 8             // the headpiece, down from the plate's top
#macro HUD_ROW_STAGE 92            // the stage's name; subtitle 44 below it
#macro HUD_RULE_1 172
#macro HUD_ROW_BEST 202            // the stage's best, above this attempt's
#macro HUD_ROW_SCORE 274           // tag and numerals on one line
#macro HUD_ROW_GRAZE 346
#macro HUD_RULE_2 388
#macro HUD_ROW_LIFE 446            // the meter's top edge; its row 24 above it
#macro HUD_ROW_SIGIL 542
#macro HUD_RULE_3 622
#macro HUD_ROW_MARKS 656           // the ledger, and the rest of the plate

// ---------------------------------------------------------------------------
// The meters
//
// Life, sigil and the boss's health are all horizontal vessels of liquid,
// drawn by `draw_gauge_h`.
// ---------------------------------------------------------------------------

#macro HUD_METER_W HUD_COL_W
#macro HUD_METER_H 52

// The liquid's surface: two travelling waves, and how many segments it is
// drawn in.
#macro LIQ_WAVE_A1 3.0             // pixels of displacement
#macro LIQ_WAVE_A2 1.7
#macro LIQ_WAVE_K1 4.6             // degrees per pixel along the surface
#macro LIQ_WAVE_K2 10.2
#macro LIQ_WAVE_S1 0.055           // degrees per millisecond
#macro LIQ_WAVE_S2 -0.083          // the second one runs the other way
#macro LIQ_WAVE_AMP (LIQ_WAVE_A1 + LIQ_WAVE_A2)
#macro LIQ_WAVE_STEPS 22           // segments the surface is drawn in

// How the liquid's body is sampled along the capsule contour
// (`capsule_half`): `LIQ_BODY_STEPS` segments along the straight part, and a
// finer pixel spacing within a radius of either end, where an even walk would
// cut across the curve.
#macro LIQ_BODY_STEPS 40
#macro LIQ_CAP_STEP 1.5

// ---------------------------------------------------------------------------
// The boss's line, inside the field
//
// A gilded rail hung on chains from the frame: the health channel, a
// percentage cartouche at the left end, a clock dial at the right, the
// caster's name on a plate above it and the spell's name below the
// cartouche. It is drawn before the field's frame mask, so it can be stowed
// above the field between bosses.
// ---------------------------------------------------------------------------

#macro BOSS_BAR_INSET 34           // in from the field's left and right edges
#macro BOSS_BAR_Y (FIELD_Y0 + 38)  // the rail's top edge, at rest
#macro BOSS_BAR_H 30               // the casing's full height

// The height of the health channel cut into the rail.
#macro BOSS_BAR_CHANNEL 14

// How far in from the rail's ends the terminals (and the chains) are centred.
#macro BOSS_RIG_END 26

// Where the rail is stowed: high enough that the frame's mask hides all of
// it.
#macro BOSS_RIG_STOW (FIELD_Y0 - BOSS_BAR_H - 40)

// The spring that lowers the rail: pull `K` and damping `D`. Tuned to land
// in about fifty frames with one small overshoot, inside `BOSS_ENTRY_TIME`.
#macro BOSS_RIG_K 0.0030
#macro BOSS_RIG_D 0.066

// The percentage cartouche, sized to hold `100.0%`, and the scale its digits
// are set at.
#macro BOSS_PCT_W 178
#macro BOSS_PCT_H 50
#macro BOSS_PCT_SCALE 0.72

// The clock dial. `BOSS_DIAL_D` mirrors `DIAL_D` in `tools/make_ui.py`.
#macro BOSS_DIAL_D 84
#macro BOSS_DIAL_URGENT 8      // seconds, below which it goes to the hit hue
#macro BOSS_DIAL_SCALE 0.72    // the count's size inside it

// The plate carrying the caster's name, standing on the rail with its foot
// sunk into the rail's top flange.
#macro BOSS_PLATE_H 38
#macro BOSS_PLATE_SINK 6       // how far the plate's foot sinks into the rail
#macro BOSS_PLATE_Y (BOSS_BAR_Y + BOSS_PLATE_SINK - BOSS_PLATE_H)
#macro BOSS_PLATE_PAD 30       // metal either side of the name
#macro BOSS_NAME_TRACK 7

// The name's centre line. It is centred by its ink (`text_cap_middle_y`).
#macro BOSS_NAME_Y (BOSS_PLATE_Y + BOSS_PLATE_H * 0.5)

// A long name widens the plate up to this, then shrinks.
#macro BOSS_PLATE_MAX_W 560

// The spell's name: its centre line under the cartouche, and the width it is
// fitted (shrunk) to.
#macro BOSS_SPELL_Y (BOSS_BAR_Y + BOSS_BAR_H * 0.5 + BOSS_PCT_H * 0.5 + 18)
#macro BOSS_SPELL_W 330

// Divisions the rail is graduated in (see `hud_rail_scale`).
#macro RAIL_GRADS 20

// Where the chain attaches on `spr_ui_hanger`; mirrors `HANGER_EYE_CY` in
// `tools/make_ui.py`.
#macro UI_HANGER_EYE 8

// The cartouche's chamfer; mirrors `PLAQUE_CHAMF` in `tools/make_ui.py`. The
// percentage is laid out from the plate's inner corner.
#macro UI_PLAQUE_CHAMF 16

// The tallest bar allowed over the playfield.
#macro FIELD_OVERLAY_MAX_H 30

#macro FONT_INK_RATIO 0.58         // see check_font_ink_ratio

// How far a sprite font's cell falls below its baseline, as a fraction of the
// cell (measured off the atlases). `text_baseline_y` and
// `text_cap_middle_y` use it to set different sizes on one line.
#macro FONT_BASELINE_DROP 0.26

// Where a digit's ink is centred above the bottom of its cell, per typeface.
// Measured off the atlases and re-derived by `check_font_digit_mid`.
#macro FONT_DIGIT_MID_NUM 0.527     // Cinzel, `fnt_num`
#macro FONT_DIGIT_MID_UI 0.561      // Spectral, `fnt_ui` and `fnt_small`

// How fast a counter's wheels catch up with their value: the share of the
// gap closed per frame, and the least they move per frame (in units of the
// lowest wheel).
#macro COUNTER_EASE 0.18
#macro COUNTER_MIN_STEP 0.09

// The share of each second in which the dial's seconds wheel turns over.
#macro DIAL_TICK_SHARE 0.2

// ---------------------------------------------------------------------------
// Spell backgrounds
//
// A spell background belongs to the boss (`def.spell_bg`), not the spell. A
// style is a macro here plus a function in `bg_functions`.
// ---------------------------------------------------------------------------

#macro SPELLBG_SIGIL 0         // two counter-rotating magic circles
#macro SPELLBG_BRIMSTONE 1     // Ziggy: a forge, in red, grey and black

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// What a run is doing. `Paused` and `BossDeclare` both stop the stage clock;
/// only `Paused` stops the field.
enum Phase {
    Intro,        // the stage opening; the player is flying in, no input yet
    Playing,
    BossDeclare,  // the name splash; the field is live but the boss is not
    PhaseClear,   // bullets converting to shards, boss invulnerable
    Paused,
    Won,
    Lost,
}

/// What a bullet does on every frame of its life, beyond `spd`, `acc` and
/// `turn`. Most bullets are `Plain`. One-off changes at a frame are `BQ`.
enum BMod {
    Plain,
    Home,       // steers toward the player, weakly, for as long as it lives
    Wander,     // drifts on a sine
}

/// What a bullet can be told to do at a frame (ph3's `AddPattern` family).
/// A bullet queues up to `BULLET_QUEUE_MAX` of these, sorted by frame. The
/// arguments are `a`..`d` on the entry and mean something different per kind;
/// use the `bullet_*_at` helpers rather than filling them by hand.
enum BQ {
    Aim,        // face the target, plus `a` degrees of lead or lag
    Move,       // speed `a`, direction `b`; `BQ_KEEP` leaves one of them alone
    Accel,      // acceleration `a`, capped at speed `b`
    Turn,       // turn rate `a`, in degrees a frame
    Force,      // per-axis force (`a`, `b`) capped at (`c`, `d`) -- see below
    Split,      // `c` children at speed `a`, offset `b` degrees; parent dies
    Shed,       // the same, `d` pixels out from the parent, which *lives*
    Graphic,    // shape `a`, colour `b`
    Fade,       // start fading out, over `a` frames
}

/// "Leave this field as it is", for `BQ.Move` arguments where zero is an
/// ordinary value.
#macro BQ_KEEP -999999

/// How many scheduled events one bullet may carry. Past it, scheduling is
/// refused.
#macro BULLET_QUEUE_MAX 8

/// How long a bullet deleted by time takes to fade out. It is harmless from
/// the first frame of the fade.
#macro BULLET_FADE_DEFAULT 12

enum LaserKind {
    Ray,        // a moving bar of light; travels like a bullet
    Beam,       // anchored, telegraphed, fires, fades
    Curve,      // a trail laid down by a moving head
}

enum LaserPhase {
    Warn,
    Fire,
    Fade,
    Done,
}

enum ItemKind {
    Health,     // red
    Mana,       // blue
    Tally,      // gold; points only
}

/// The fodder. None of it is a creature (owner's rule): wisps, grimoires,
/// gems and sentries are animated objects.
enum EnemyKind {
    Wisp,
    Grimoire,
    Gem,
    Sentry,
    Boss,
}

/// One entry in a boss's attack table.
enum AttackKind {
    NonSpell,   // a basic attack: no banner, no background change
    Spell,      // named, with a banner, an eye card and the boss's background
}

/// How a boss moves during one attack; set per attack with the phase's
/// `move` field. A phase that names none drifts. See `boss_move`.
enum BossMove {
    Drift,      // the default: a wide lissajous wander round its station
    Close,      // the same wander, kept near the station
    Track,      // trends toward the player's column, loosely, still wandering
    Fixed,      // takes its station and holds it
    Step,       // holds still, hops to a new spot, holds again
}

// ---------------------------------------------------------------------------
// BossMove.Step
//
// The boss holds still for `BOSS_STEP_HOLD` frames, then hops to a new spot
// over `BOSS_STEP_MOVE` frames. An attack that should only fire while the
// boss is still checks `boss_holding`.
// ---------------------------------------------------------------------------
#macro BOSS_STEP_HOLD 195      // frames held still
#macro BOSS_STEP_MOVE 45       // frames spent hopping

// How far a hop may land from the station.
#macro BOSS_STEP_X 140
#macro BOSS_STEP_Y 24

// How hard the boss chases the spot it is hopping to; it must arrive within
// `BOSS_STEP_MOVE`.
#macro BOSS_STEP_RATE 0.10

// `BossMove.Close`: how far the wander strays from the station, sideways and
// vertically.
#macro BOSS_CLOSE_X 150
#macro BOSS_CLOSE_Y 22

// ---------------------------------------------------------------------------
// Corridor backgrounds (stage two; see `bg_corridor`)
//
// The camera sits at the origin looking down +z, `CORRIDOR_CAM_H` above the
// ground, and `k = FOCAL / z` is the screen pixels one world unit covers at
// depth z.
// ---------------------------------------------------------------------------

// The lens: about a 75-degree horizontal field of view on this field.
#macro CORRIDOR_FOCAL 900

// How high the camera flies.
#macro CORRIDOR_CAM_H 250

// The vanishing point, as a share of the view's height.
#macro CORRIDOR_HORIZON 0.52

// The clamp that stops the projection dividing by nothing, the near plane a
// prop is recycled at, the depth inside which there is no haze, and the far
// plane (the corridor's back wall).
#macro CORRIDOR_Z_MIN 60
#macro CORRIDOR_Z_NEAR 200
#macro CORRIDOR_Z_CLEAR 900     // no haze at all closer than this
#macro CORRIDOR_Z_FAR 5200

// The most haze-free air allowed where a ring recycles its props. A prop must
// arrive already nearly the fog's colour, or it visibly pops in;
// `test_corridor` checks every ring against this.
#macro CORRIDOR_ARRIVE_HAZE 0.45

// Vertex columns per tile of a wave band's strip (see
// `corridor_draw_band_wave`).
#macro CORRIDOR_BAND_COLS 64

#macro BGKIND_PARALLAX 0
#macro BGKIND_CORRIDOR 1

// How long a background's mid-stage turn takes (see `bg_set_omen`).
#macro BG_OMEN_TIME 270

// ---------------------------------------------------------------------------
// The Hollow Grove (stage two)
//
// Scenery is drawn as luminance and tinted at draw time, so the whole wood
// can change colour when the moon turns to blood (see `tools/make_grove.py`).
// ---------------------------------------------------------------------------

// Flight speed in world units a frame, before and after the turn.
#macro GROVE_SPEED 6
#macro GROVE_SPEED_FAST 9.5

// The wood's light on an ordinary night, as a multiplier on the palette. The
// moon is not dimmed by it.
#macro GROVE_NIGHT_LIGHT 0.74

// The eclipse's shadow on the moon: copper rather than black.
#macro GROVE_UMBRA_COL make_colour_rgb(44, 9, 7)
#macro GROVE_UMBRA_RAMP 0.75     // the penumbra, as a share of the moon's radius
#macro GROVE_UMBRA_SLICES 72

#macro GROVE_MOON_R 168
#macro GROVE_MOON_RISE 44       // how far its centre sits above the horizon

// The trees, in world units. `GROVE_PATH_HALF` is measured from a tree's
// edge, and has to put every tree off the side of the field before it reaches
// `CORRIDOR_Z_NEAR` (`test_corridor` checks).
#macro GROVE_TREE_H 700
#macro GROVE_PATH_HALF 470
#macro GROVE_TREE_OUT 1600
#macro GROVE_TREE_N 40

// How much a prop's own height and width may vary from its kind's, so the
// same frame rarely looks the same twice. Placement allows for the widest.
#macro GROVE_VARY_H 0.20
#macro GROVE_VARY_W 0.16
#macro GROVE_VARY_MAX ((1 + GROVE_VARY_H) * (1 + GROVE_VARY_W))

// The trunks: taller than the screen. `GROVE_TRUNK_HALF` is the clearance a
// trunk's inner edge keeps from the centre line (`grove_make_trunk` adds the
// prop's own half-width), and they run out to the corridor's far plane so
// they arrive out of the fog.
#macro GROVE_TRUNK_H 1500
#macro GROVE_TRUNK_HALF 230
#macro GROVE_TRUNK_OUT 1400      // ...and how much further out it may go
#macro GROVE_TRUNK_Z CORRIDOR_Z_FAR
#macro GROVE_TRUNK_N 22

#macro GROVE_IVY_H 190

// What kind of thing a prop is. Carried on the prop because every ring is
// drawn in one merged depth-sorted pass (see `corridor_merge_new`).
#macro GROVE_KIND_TREE 0
#macro GROVE_KIND_TRUNK 1
#macro GROVE_KIND_BUSH 2
#macro GROVE_KIND_BOUGH 3

// The boughs overhead: the tree sprite hung upside down from a point
// `GROVE_BOUGH_UP` above the camera. They keep `GROVE_BOUGH_IN` (from their
// inner edge) off the centre line so none hangs across the moon.
#macro GROVE_BOUGH_H 440
#macro GROVE_BOUGH_UP 950
#macro GROVE_BOUGH_IN 900
#macro GROVE_BOUGH_OUT 1700
#macro GROVE_BOUGH_Z 4200
#macro GROVE_BOUGH_N 14

#macro GROVE_BUSH_H 130
#macro GROVE_BUSH_Z 3400
#macro GROVE_BUSH_N 50

// Hanging charms: the odds a tree carries one, and their size. They hang from
// the branch tips `tools/make_grove.py` writes into `scripts/grove_table`.
#macro GROVE_CHARM_ODDS 0.55
#macro GROVE_CHARM_H 200
#macro GROVE_CHARM_SWAY 7        // degrees either way

// The forest floor, laid down the corridor in bands of constant screen
// height (so the affine texturing error stays under a pixel). The tile is
// square in world units.
#macro GROVE_FLOOR_W 270         // world units across one tile
#macro GROVE_FLOOR_Z GROVE_FLOOR_W   // ...and along it
#macro GROVE_FLOOR_ROW 26        // screen pixels per band

// The floor's hand-made mip chain: the tile is laid at doubling world sizes,
// cross-faded, and a level hands over when one band would show more than
// `GROVE_FLOOR_NYQ` of a tile.
#macro GROVE_FLOOR_NYQ 0.34
#macro GROVE_FLOOR_MIPS 4

#macro GROVE_MIST_Y 0.10
#macro GROVE_GROUND_BAND 130     // world units between root ridges

// The blood wavefront: it launches from the moon and travels down the
// corridor toward the player, so far props turn first. `GROVE_WAVE_FEATHER`
// is how deep the front is and `GROVE_WAVE_FLARE` how far either side of it a
// charm catches its light.
#macro GROVE_WAVE_START 0.30     // the share of the omen it launches at
#macro GROVE_WAVE_Z0 6400
#macro GROVE_WAVE_FEATHER 900
#macro GROVE_WAVE_FLARE 700

// How close a tree must be before its lit edge is also drawn over the field
// (additively; see `grove_draw_front`).
#macro GROVE_NEAR_Z 560

// ---------------------------------------------------------------------------
// The arrival: the stage opens in fog, nearly still, and the fog lifts as the
// flight picks up speed.
// ---------------------------------------------------------------------------
#macro GROVE_INTRO_TIME 170      // frames the fog takes to lift
#macro GROVE_INTRO_SPD 0.12      // the share of full speed the flight opens at

// ---------------------------------------------------------------------------
// The camera
//
// The flight swells gently in speed, and the view meanders slowly in yaw and
// pitch (rotations, so everything shifts together; see `corridor_view`).
// ---------------------------------------------------------------------------
#macro GROVE_SWELL 240           // frames in one swell of the glide
#macro GROVE_SWELL_SURGE 0.09    // ...and the share of the speed it adds
#macro GROVE_SWAY 12             // how far the path wanders on its own
#macro GROVE_RISE 14             // ...and how far the flight rises and falls
// Two periods per axis, neither a multiple of the other, so the meander does
// not repeat.
#macro GROVE_SWAY_P1 1130
#macro GROVE_SWAY_P2 431
#macro GROVE_RISE_P1 1670
#macro GROVE_RISE_P2 709

// ---------------------------------------------------------------------------
// The lean
//
// The camera slides sideways toward the player's side of the field (a
// rail-shooter lean: a player on the left moves the view left, putting the
// vanishing point on the right). It is a lateral slide in world units, so
// each depth shifts by its own `corridor_k` and near things part from far
// ones. It is eased, so dodging doesn't shake the horizon, and capped per
// frame. A player-less screen does not steer.
// ---------------------------------------------------------------------------
#macro GROVE_LEAN 30             // world units the camera slides at the wall
#macro GROVE_LEAN_EASE 0.016     // ...the share of the gap it closes a frame
#macro GROVE_LEAN_SPD 0.34       // ...and the most it may slide in one frame

// ---------------------------------------------------------------------------
// The verge: dense low undergrowth on both sides, from the path's edge out
// past the trees and back to the far plane.
// ---------------------------------------------------------------------------
#macro GROVE_VERGE_H 320         // world units tall
#macro GROVE_VERGE_IN 300        // ...how close to the path it may grow
#macro GROVE_VERGE_OUT 2400      // ...and how far out it goes
#macro GROVE_VERGE_N 78
#macro GROVE_KIND_VERGE 4

// How far the far wood's foot dips, in screen pixels. Downward only
// (`corridor_draw_band_wave`): lifting it would show sky under the wood.
#macro GROVE_RIDGE_H 58
#macro GROVE_MIST_WAVE 44

// ---------------------------------------------------------------------------
// The scrub: an opaque hedgerow band drawn over the floor along the horizon,
// hiding the join between the ground and the far wood. It dips (does not
// part) where the path meets it. Its thinnest stretch must still cover the
// horizon; `check_scrub_covers_horizon` adds up these numbers against the
// shipped PNG.
// ---------------------------------------------------------------------------
#macro GROVE_SCRUB_FAR 0.95      // the far row's size against the band's width
#macro GROVE_SCRUB_NEAR 1.45     // ...and the near row's, which is the cover
#macro GROVE_SCRUB_RISE 0.84     // the share of the band standing above the line
#macro GROVE_SCRUB_WAVE 10       // how far its baseline rides up and down
#macro GROVE_SCRUB_DIP 0.08      // how much lower it stands where the path is
#macro GROVE_SCRUB_DIP_W 320     // ...and over how many pixels either side
#macro GROVE_SCRUB_CLEAR 12      // px the thinnest stretch must clear the line

#macro SPELLBG_GROVE 2         // Velka's spell background: a ring of bone and ivy

// ---------------------------------------------------------------------------
// Sound
//
// The global knobs. Per-cue gain, gap and priority are rows in
// `audio_functions`.
// ---------------------------------------------------------------------------

// Most cues that may start in one frame; `sfx_step` spends them in priority
// order.
#macro SFX_VOICES 5

// The request count at which a coalesced volley stops getting bigger.
#macro SFX_SWELL_FULL 32

// Master gain over the whole mix, below 1 for headroom.
#macro SFX_MASTER 0.72


// ---------------------------------------------------------------------------
// Stage three's hall: a room in 3D (see `bg_sanctum`)
//
// A real camera with a view matrix, a perspective projection and the depth
// buffer. The stage opens with the camera high and aimed at the floor, then
// rises and levels out (the "reveal").
// ---------------------------------------------------------------------------

#macro BGKIND_SANCTUM 2

// The nave's half-width, the height of the case tops' ceiling line, and the
// bay length (one three-bay run of `spr_hall_wall`).
#macro HALL_HALF_W 700
#macro HALL_CEIL_H 1250
#macro HALL_BAY_Z 560
// How many bays are drawn ahead of the camera. The nearest a newly entering
// bay can be is `(HALL_BAYS - 1)` bays out, which must be beyond
// `HALL_FADE_END` so it arrives invisible (`test_hall_sky` checks).
#macro HALL_BAYS 16

// The pavement's three courses, from the centre line out: a sunken runner,
// an ornamented border, and the marble field at the walls.
#macro HALL_RUNNER_HW 264     // the runner's half-width
#macro HALL_FLOOR_STEP 13     // ...and how far it is sunk below the aisles
#macro HALL_BORDER_W 92       // the ornamented course between the two
#macro HALL_THRESH_W 58       // the band laid across the aisles at a bay joint
#macro HALL_AISLE_NX 2        // tiles of marble across one aisle
#macro HALL_AISLE_NZ 3        // ...and along it
#macro HALL_BORDER_NZ 2
#macro HALL_THRESH_NX 3

// Vertical field of view in degrees (about 74 horizontal on this field).
#macro HALL_FOV 58
// The near and far planes. Nothing comes within 40 units of the lens, and a
// nearer near plane would waste depth precision.
#macro HALL_ZNEAR 40
#macro HALL_ZFAR 14000

// Distance fog (applied in `sh_hall`) and then an alpha fade. The fade starts
// where the fog is solid, so a bay dissolves only once it has no colour of
// its own left; it matters because the lit rotunda at the end of the hall is
// behind the last bays, and fog alone would leave them as silhouettes.
#macro HALL_FOG make_colour_rgb(10, 17, 46)
#macro HALL_FOG_START 1100
#macro HALL_FOG_END 7200
#macro HALL_FADE_START 7200
#macro HALL_FADE_END 8400

// The two ends of the reveal: phase A is high and pitched down far enough to
// hide the vanishing point; phase B is at flying height, nearly level.
#macro HALL_CAM_HIGH 900
#macro HALL_CAM_FLY 250
#macro HALL_PITCH_A -55
#macro HALL_PITCH_B -2

#macro HALL_SPEED 9.0
// The arrival: the stage opens dark and nearly still and the lights come up
// as the flight gathers. Phase A flies slower because nothing is near the
// lens up there.
#macro HALL_INTRO_TIME 165
#macro HALL_INTRO_SPD 0.16
#macro HALL_SPEED_A 5.2
#macro HALL_SWELL 0.055
#macro HALL_SWELL_P 260

// ---------------------------------------------------------------------------
// The joinery: a wall built of real planes at real depths (pilasters, case
// fronts, shelf recesses, cornice and plinth).
// ---------------------------------------------------------------------------
#macro HALL_PIL_D 46          // how far a pilaster stands out from the case
#macro HALL_PIL_W 80          // ...and how wide it is along the hall
#macro HALL_CASE_D 120
#macro HALL_BOOK_INSET 22     // how far behind the case front the books stand
#macro HALL_ALCOVE_D 280      // how deep an alcove goes
#macro HALL_PLINTH_H 130
#macro HALL_PLINTH_D 30
#macro HALL_CASE_TOP 1040
#macro HALL_CORN_D 46
#macro HALL_SHELVES 6
// An alcove every fourth bay, at the third of them (see `hall_bay_kind`).
#macro HALL_ALCOVE_EVERY 4
#macro HALL_ALCOVE_AT 2
#macro HALL_BOARD_T 6
#macro HALL_BOARD_COL make_colour_rgb(92, 86, 76)
#macro HALL_GILT make_colour_rgb(104, 80, 32)
// Tints for surfaces drawn on the pale albedo `spr_hall_pale` (a vertex
// colour multiplies its texture).
#macro HALL_CAT make_colour_rgb(46, 46, 60)     // the statues: black basalt
#macro HALL_MASONRY make_colour_rgb(27, 28, 36)
#macro HALL_GLASS make_colour_rgb(72, 78, 104)
#macro HALL_ORB_COL make_colour_rgb(120, 186, 255)
#macro HALL_LAMP_GLOW 0.40

// The height of a statue's plinth (the statue sprite is the figure alone).
#macro HALL_STATUE_BASE 262
#macro HALL_DESK_TOP 150

// How far a moulding stands out from the face it is on (also breaks depth
// ties).
#macro HALL_FILLET_D 4
#macro HALL_ORB_BODY make_colour_rgb(34, 48, 86)

// The orb in an alcove, and the light it casts on the stone round it.
#macro HALL_ORB_R 48
#macro HALL_ORB_Y 470
#macro HALL_ORB_GLOW 0.95
#macro HALL_ORB_POWER 1.55
#macro HALL_ORB_LIGHT_R 420
// How far into the recess the orb stands. `hall_orb_x` is the one place that
// turns this into a position, for both the geometry and the light
// (`test_hall_orb`).
#macro HALL_ORB_STAND 84
#macro HALL_ORB_STEM_H 262    // the pedestal, from the alcove sill upward
#macro HALL_ORB_CRADLE 28     // ...and the gilt cup it sits in
#macro HALL_ORB_BLOOM 5.2     // the bloom card's radius, in orb radii

// Baked light. `AMB` is what a surface gets with nothing near it; the powers
// are how much each source adds at its own centre.
#macro HALL_WALL_AMB 0.46
#macro HALL_LAMP_Y 360
#macro HALL_LAMP_POWER 0.62
#macro HALL_LIGHT_R 680

#macro HALL_WALL_LIGHT 1.00
#macro HALL_FLOOR_LIGHT 0.86
// The pavement is lit by both walls at once (`hall_floor_light`):
// `HALL_FLOOR_AMB` is what a point far from everything gets, and the bounce is
// how much of a lamp reaches the stone under it.
#macro HALL_FLOOR_AMB 0.26
#macro HALL_FLOOR_BOUNCE 0.74
// A vignette on top: the share of the light the centre line keeps, so the
// floor under the player is the darkest part of it.
#macro HALL_FLOOR_DIM 0.42
// Where the lamps sit up the wall, as a share of its height from the cornice
// down (where `tools/make_sanctum.py` draws them).
#macro HALL_LAMP_V 0.46

// Steering, as the grove's lean: an ease and a per-frame cap.
#macro HALL_LEAN 92
#macro HALL_LEAN_EASE 0.022
#macro HALL_LEAN_SPD 1.7

// What stands in the nave, in world units.
#macro HALL_STATUE_X 548
// The statue figure's height, standing on `HALL_STATUE_BASE`.
#macro HALL_STATUE_H 300
// How strongly the statue's lit edge is drawn in the additive pass.
#macro HALL_STATUE_RIM 0.42
// Facets round the statue's swept cross-section.
#macro HALL_STATUE_STEPS 16
// What the statue's swept form adds to the sprite's baked light: a lift where
// the surface faces up and a fall where it faces away down the hall. Both are
// zero on the face toward the camera.
#macro HALL_STATUE_TOP 0.34
#macro HALL_STATUE_AWAY 0.32
// The pedestals stand on the statue line, midway between two statues.
#macro HALL_DESK_X 548
#macro HALL_DESK_H 165

// The instruments on the pedestals (an hourglass and a small armillary). They
// are built at the origin and drawn under a matrix, so they can move; the rest
// of the hall is frozen into each bay's vertex buffers.
#macro HALL_INST_Y 88          // how far over the cap the instrument floats
#macro HALL_INST_BOB 9         // ...and how far it rises and falls
#macro HALL_INST_BOB_P 274     // frames a rise and a fall takes
#macro HALL_INST_SPIN 0.17     // degrees a frame the hourglass turns
// The hourglass: two bulbs turned on a lathe (`hall_lathe`).
#macro HALL_GLASS_H 104        // the glass, foot to head
#macro HALL_GLASS_R 31         // ...at its belly
#macro HALL_GLASS_NECK 3.2     // ...and at its waist
#macro HALL_GLASS_SEG 18       // segments round
// The sand is kept dark: it is scenery under the danmaku.
#macro HALL_SAND make_colour_rgb(118, 90, 40)
#macro HALL_SAND_FILL 0.40     // how much of the lower bulb is full
#macro HALL_SAND_HEAD 0.18     // ...and how far up the upper bulb reaches
// The armillary, built like `hall_draw_orrery` at small scale.
#macro HALL_ARM_R 46
#macro HALL_ARM_CORE 11
// The tabards, placed by their centre; `HALL_BANNER_X` plus half a banner's
// width must stay clear of the cornice (`test_hall_sky` checks).
#macro HALL_BANNER_X 540
#macro HALL_BANNER_H 620
// Its top hangs this far under the wall head's coping.
#macro HALL_BANNER_DROP 6
#macro HALL_LAMP_X 606
#macro HALL_LAMP_H 340

// How hard the additive emissive pass is driven, so the lamps stay dimmer
// than the bullets.
#macro HALL_EMISSIVE_K 0.50
// A prop's own light: a flat value rather than the wall's falloff.
#macro HALL_PROP_LIGHT 0.88
// Alpha test threshold. Cut-out sprites on quads have transparent corners
// that would otherwise write depth.
#macro HALL_ALPHA_REF 96
#macro HALL_LAMP_EMISSIVE make_colour_rgb(96, 96, 96)

// ---------------------------------------------------------------------------
// The open roof
//
// The hall has no ceiling. The visible sky is the wedge between the two wall
// tops: a long horizontal edge at height H and half-width X projects to a ray
// from the vanishing point with slope (H - camera) / X, so anything built
// above the wall narrows the sky for the whole hall. `test_hall_sky` checks
// that the orrery still clears the masonry.
// ---------------------------------------------------------------------------

// The coping: the slab capping the wall, oversailing it on the nave side.
#macro HALL_COPING_H 26
#macro HALL_COPING_OUT 46        // how far past the pilaster it stands

// The parapet on the coping. `X` is its inner face, the edge that silhouettes
// and that the sky's wedge is measured from.
#macro HALL_PARAPET_X 672
#macro HALL_PARAPET_H 72

// An obelisk over the pilaster on each ordinary bay. Thin, so it narrows the
// sky only at its own bay.
#macro HALL_OBELISK_H 430
#macro HALL_OBELISK_W 32
#macro HALL_OBELISK_CAP 78       // the gilt pyramidion, the lit part

// A brazier on the alcove bays instead.
#macro HALL_BRAZIER_H 104
#macro HALL_BRAZIER_R 62
#macro HALL_BRAZIER_COL make_colour_rgb(255, 176, 92)
#macro HALL_BRAZIER_GLOW 0.85

// ---------------------------------------------------------------------------
// The sky
//
// A dome centred on the camera, drawn first with the depth test off, so it
// rotates with the view but never translates. Its radius must still be inside
// the frustum, since the near and far planes clip regardless.
// ---------------------------------------------------------------------------
#macro HALL_SKY_R 6000
#macro HALL_SKY_COLS 40
#macro HALL_SKY_ROWS 13
// The dome reaches well below the horizon so no pitch in the reveal shows an
// unpainted band.
#macro HALL_SKY_EL0 -40
// The sky's colour ramp. Elevation zero is exactly `HALL_FOG`, so the far end
// of the hall dissolves into it; above that it ramps to these saturated
// blues. The ramp sits inside the band the camera actually sees (roughly
// 10-28 degrees of elevation).
#macro HALL_SKY_LOW make_colour_rgb(20, 44, 104)
#macro HALL_SKY_HIGH make_colour_rgb(7, 12, 46)
#macro HALL_SKY_LOW_EL 13
#macro HALL_SKY_HIGH_EL 52

// The stars, in three magnitudes. Only about a hundred of these fall in the
// visible wedge; they are one frozen buffer and one draw.
#macro HALL_STARS 9000
// Star extinction toward the horizon: out by `HALL_STAR_EL0`, full by
// `HALL_STAR_EL1` degrees, so stars fade before the wall tops as the fog does.
#macro HALL_STAR_EL0 1
#macro HALL_STAR_EL1 11
#macro HALL_STAR_SIZE 40         // a middling star's half-size at HALL_SKY_R
// A band of denser, fainter stars across the sky.
#macro HALL_STAR_BAND 0.44       // what share of them fall in it
#macro HALL_STAR_BAND_TILT 34
#macro HALL_STAR_BAND_W 13       // its half-width, in degrees

// How far either side of dead ahead the nebulae and constellations are
// placed, so the few of them there are land in view.
#macro HALL_SKY_SPREAD 64

#macro HALL_NEB_N 16
#macro HALL_NEB_A 0.42
#macro HALL_NEB_R0 62            // a patch's half-angle, in degrees
#macro HALL_NEB_R1 26            // ...and how much less it can be

// The constellations: a handful of bright stars, joined.
#macro HALL_CONST_N 22
#macro HALL_CONST_A 0.22

// ---------------------------------------------------------------------------
// The chamber at the end of the hall
//
// One painted quad at a fixed depth, so the ground ends in a building rather
// than in stars. The painting computes its own perspective from its screen
// size, so `HALL_ROT_HW` and `HALL_ROT_Z` must agree with
// `HALL_ROT_HW_SCREEN` in `tools/make_sanctum.py`
// (`check_rotunda_scale_agrees`).
// ---------------------------------------------------------------------------
#macro HALL_ROT_Z 12500
#macro HALL_ROT_HW 5600
// Its half-height: wide and short, to fit between the vanishing point and the
// orrery.
#macro HALL_ROT_HH 1830
// Its foot, in world y: below the hall's floor, so there is no gap above the
// horizon.
#macro HALL_ROT_Y0 -200
#macro HALL_ROT_COL make_colour_rgb(124, 152, 232)
// Slightly transparent, so the sky shows through as distance.
#macro HALL_ROT_A 0.88
#macro HALL_ROT_LIT make_colour_rgb(255, 206, 132)
#macro HALL_ROT_LIT_A 0.82

// ---------------------------------------------------------------------------
// The grand orrery
//
// A fixed direction rather than a place: anchored to the camera's depth, so
// the flight never reaches it. Its height and size are set so it clears the
// parapet and its top stays in the field (`test_hall_sky`).
// ---------------------------------------------------------------------------
#macro HALL_ORRERY_Z 9000
#macro HALL_ORRERY_Y 2820
#macro HALL_ORRERY_R 1120
// Drawn with fog off (fog at this distance is total) and dimmed by this
// multiply instead.
#macro HALL_ORRERY_DIM 0.80
#macro HALL_ORRERY_GILT make_colour_rgb(226, 184, 100)
#macro HALL_ORRERY_CORE make_colour_rgb(150, 205, 255)
#macro HALL_ORRERY_HALO_R 2900
#macro HALL_ORRERY_HALO_A 0.16
// Frames the core takes to breathe once.
#macro HALL_ORRERY_PULSE 310

// ---------------------------------------------------------------------------
// Blown sand in the air (see `hall_draw_front`)
//
// Grains are projected through the camera, all driven by one sideways wind
// and kept low over the pavement. One hash sets a grain's size, fall and
// wander together, so heavy grains fall faster. The colour is a desaturated
// tan that no bullet in Mika's table uses.
// ---------------------------------------------------------------------------
#macro HALL_SAND_N 130
#macro HALL_SAND_COL make_colour_rgb(206, 180, 142)
#macro HALL_SAND_A 0.30
// The volume it blows through, in world units: how near a grain may come
// before it is gone, how deep the cloud runs, how far out either side of the
// nave it starts, and how high the drift reaches.
#macro HALL_SAND_NEAR 300
#macro HALL_SAND_RANGE 3400
#macro HALL_SAND_SPREAD 360
#macro HALL_SAND_TOP 900
// How far sideways the wind carries a grain over one fall, and the fall
// rate.
#macro HALL_SAND_WIND 680
#macro HALL_SAND_FALL 0.00042
// A grain's radius in world units.
#macro HALL_SAND_R 7.0
// How many frames back the streak is drawn from, and its maximum length in
// pixels.
#macro HALL_SAND_TRAIL 5
#macro HALL_SAND_TRAIL_MAX 26
// Nearer than this in view space a grain is dropped rather than projected.
#macro HALL_SAND_ZNEAR 60
