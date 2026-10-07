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

// The hitbox disc's radius in `spr_hitbox`'s own pixels (`HITBOX_R` in
// tools/make_fx.py), so it can be drawn at exactly `PLAYER_R`.
#macro HITBOX_ART_R 4.0

// Frames the focus circle takes to open as focus is held, and to close.
#macro FOCUS_OPEN 9
#macro FOCUS_CLOSE 6

// A bullet pays a graze once; a laser pays every this many frames while the
// player rides it.
#macro LASER_GRAZE_CD 20

#macro HP_MAX 100
#macro HP_PER_HIT 25
#macro HP_QUADRANT 25          // where the markers on the bar go
#macro IFRAME_TIME (3 * FPS)   // invulnerable after a hit

#macro MP_MAX 100
#macro MP_PER_BOMB 25
#macro BOMB_INVULN IFRAME_TIME // grace on a special: as long as a hit's
#macro BOMB_CLEAR_R 560        // bullets inside this are swept
#macro BOMB_GROW 70            // frames the sweep takes to reach full radius

// The special (sigil), paced round his cut-in (`sigil_cutin`): while it plays
// the sweep grows from the cast point and erases bullets; as it ends
// `BOMB_SEALS` wisps spiral out, hunt the nearest target and burst, each
// dealing `BOMB_SEAL_DMG`; then the circle fades out as his grace runs out.
#macro BOMB_SEALS 6
#macro BOMB_SEAL_AT SIGIL_CUTIN_TIME   // frames after the cast the seals leave
#macro BOMB_SEAL_CURL 24       // frames they spiral out before they hunt
#macro BOMB_SEAL_LIFE 96       // frames a seal lives if it finds nothing
#macro BOMB_SEAL_SPD0 7.5      // leaving the heart
#macro BOMB_SEAL_SPD 24        // top speed, hunting
#macro BOMB_SEAL_TURN 8.5      // degrees a frame, hunting
#macro BOMB_SEAL_R 26          // how close to a target counts as striking it
#macro BOMB_SEAL_WAKE 90       // bullets this close to a flying seal are swept
#macro BOMB_SEAL_BLAST 230     // ...and this close to where it bursts
#macro BOMB_SEAL_DMG 10
#macro BOMB_SIGIL_FADE 120     // the frame the circle starts to fade...
#macro BOMB_SIGIL_OUT (BOMB_INVULN - 8)   // ...and is gone

// The grace dial round the player (see `player_draw_grace`): its radius at
// full and at empty, and the share of the grace left when it starts to
// flicker.
#macro GRACE_RING_R_FULL 80
#macro GRACE_RING_R_EMPTY 62
#macro GRACE_URGENT 0.3
// How far out it moves while he is focused, to run outside the focus circle
// (`spr_focus_sigil`, whose stars reach 85px) rather than across it.
#macro GRACE_RING_FOCUS_OUT 26

// Frames per heartbeat of the one-hit-from-death warning.
#macro LOW_HP_BEAT 48

// The shot: a volley of mirrored pairs, one pair per barrel in
// `pshot_barrels`, which sets each pair's muzzle, angle and damage.
#macro PSHOT_PERIOD 3          // frames between volleys
#macro PSHOT_SPD 36

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

// The mark a bullet leaves where it hit the player (`fx_hit_mark`): frames it
// lasts, frames its lock takes to close on it, frames of its release at the
// end, and the radius of the lock's ring in `spr_fx_strike` (`STRIKE_LOCK` in
// tools/make_fx.py).
#macro HIT_MARK_TIME 46
#macro HIT_MARK_CLOSE 12
#macro HIT_MARK_OUT 12
#macro HIT_MARK_LOCK_R 44

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

// A ring's orbit track (`track`): a line fading out this many pixels either
// side of the circle, in segments short enough that the circle bows from its
// chords by no more than `SAG` pixels.
#macro RING_TRACK_HALF 2
#macro RING_TRACK_SAG 0.25

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

// The thresholds lean lenient (owner's call): decent play should pass them
// without aggressive tactics or grazing skill.

// A boss attack's par is how long its share of the boss's health takes with
// every shot landing, times this: room for dodging and for shots the boss's
// rings stop. Breaking an attack by its par meets its score threshold on
// speed alone (`rank_attack_target`). Unplayed.
#macro RANK_PAR_SLACK 2.5

// What a second of an attack's clock is worth, as a number of grazes: the
// speed award pays this for every second saved, and each second past par has
// to be made up with this many grazes. Unplayed.
#macro RANK_GRAZE_RATE 14

// A group of waves' threshold, as a share of what its enemies are worth
// (`rank_wave_target`). Unplayed.
#macro RANK_WAVE_SHARE 0.75

// The rank card (see `rank_card`). Its length fits inside `BOSS_PHASE_PAUSE`.
#macro RANK_CARD_TIME 80
#macro RANK_CARD_FLASH 18          // the flash and shockwave as it arrives
#macro RANK_CARD_SPIN 32           // the medal spins in and comes to rest
#macro RANK_CARD_TURNS 2           // ...turning this many times
#macro RANK_CARD_ROCK 20           // then rocks once as it stops
#macro RANK_CARD_GLINT_END 52      // the glint crossing its face
#macro RANK_CARD_FLY 24            // and it leaves for its socket, turning once

// Where the card is shown: above the player's half, below the boss's station.
#macro RANK_CARD_Y (FIELD_Y0 + FIELD_H * 0.38)

// The medals' sizes, as `tools/medal_art.py` renders them
// (`check_medal_sizes_agree`).
#macro MEDAL_D 216                 // the card's medal, drawn at scale 1
#macro MEDAL_THICK 15              // its edge, which shows as it turns
#macro MEDAL_STAR_AXIS 1.16        // a spell's star, above and below, in radii
#macro MARK_D 32                   // a console socket's medal

// The card's scale when it lands: the socket medal's size.
#macro RANK_CARD_HOME_S (MARK_D / MEDAL_D)

// Where a turning medal's face throws the light's reflection at the viewer:
// its heading, in degrees from facing the viewer (negative is turned to the
// left, toward the light).
#macro MEDAL_SHEEN_AT -35

// ---------------------------------------------------------------------------
// Enemies and bosses
// ---------------------------------------------------------------------------

#macro ENEMY_FLASH 5               // frames an enemy whitens when hit
#macro ENEMY_DEATH_BITS 14

#macro BOSS_ENTRY_TIME (2 * FPS)
#macro BOSS_DECLARE_TIME (3.4 * FPS)   // the name card (`name_card`)
#macro BOSS_PHASE_PAUSE (1.4 * FPS)    // invulnerable, between attacks

// The READY beat before a practised attack starts.
#macro PRACTICE_READY (2 * FPS)

// How long a spell declares itself before its pattern opens: its cut-in
// (`spell_cutin`), whose band is gone a little before the end. The boss is
// invulnerable and the phase clock stopped through it.
#macro BOSS_SPELL_LEAD CUTIN_TIME

// How long before an attack's first shots its boss's charge cue starts
// (`boss_charge`). The cue is the Hex's 1.8s pull, loudest early and fading
// as it climbs, so it has mostly died away as the shots come.
#macro BOSS_CHARGE_LEAD (1.2 * FPS)

#macro BOSS_DRIFT_SPD 1.1

// `BossMove.Drift`: how far a boss wanders from its station, and how sharply
// it chases its wander point.
#macro BOSS_DRIFT_X 430
#macro BOSS_DRIFT_Y 74
#macro BOSS_DRIFT_RATE 0.075

// `BossMove.Track`: holds `HOLD` frames, then hops over `MOVE` frames to a
// spot `LEAN` of the way across to the player's x, give or take up to `X`,
// keeping its centre `BOSS_TRACK_EDGE` in from the field's sides.
#macro BOSS_HOP_HOLD 120
#macro BOSS_HOP_MOVE 45
#macro BOSS_HOP_LEAN 0.45
#macro BOSS_HOP_X 160
#macro BOSS_TRACK_EDGE 130

// Where a boss holds station, measured down the field.
#macro BOSS_HOME_Y (FIELD_Y0 + 250)

// Frames a boss's seal (`boss_draw_seal`) takes to open as the boss appears,
// and the radius of its gilt rule in `spr_boss_seal`'s pixels (`SEAL_RIM` in
// tools/make_fx.py), where its stars are.
#macro BOSS_SEAL_OPEN 40
#macro BOSS_SEAL_RIM 126

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


// The rail fades to `BOSS_RAIL_FADE` of its opacity while the player is under
// it or within `BOSS_RAIL_NEAR` pixels of its box (`hud_rail_near`), easing
// `BOSS_RAIL_FADE_EASE` of the way there each frame.
#macro BOSS_RAIL_FADE 0.5
#macro BOSS_RAIL_NEAR 60
#macro BOSS_RAIL_FADE_EASE 0.15

// How far down from the top of the screen the rail's layers reach: past the
// spell's name at the bottom of the rig's swing, with room for its glows.
#macro HUD_RAIL_LAYER_H (BOSS_SPELL_Y + 120)

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
    BossDeclare,  // the boss arriving, talking and being named; it is not live
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
/// gems and sentries are animated objects. The `Hall` kinds are stage
/// three's own (a soul-flame, a flying spellbook, an armillary sphere), drawn
/// in their own colours (`hall_foe_draw`).
enum EnemyKind {
    Wisp,
    Grimoire,
    Gem,
    Sentry,
    HallWisp,
    HallBook,
    HallSphere,
    Boss,
}

/// One entry in a boss's attack table.
enum AttackKind {
    NonSpell,   // a basic attack: no cut-in, no background change
    Spell,      // named, with a cut-in and the boss's background
}

/// How a boss moves during one attack; set per attack with the phase's
/// `move` field. A phase that names none drifts. See `boss_move`.
enum BossMove {
    Drift,      // the default: a wide lissajous wander round its station
    Close,      // the same wander, kept near the station
    Track,      // hops like Step, leaning toward the player's side
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

// The music's gain (`tools/make_music.py` writes every track at one
// loudness), and the frames a change of track crossfades over.
#macro MUSIC_MASTER 0.4
#macro MUSIC_FADE 60


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
// ...and behind it, which the opening's steep look down takes in.
#macro HALL_BAYS_BEHIND 2

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
// Phase A flies slower because nothing is near the lens up there.
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
#macro HALL_GILT make_colour_rgb(104, 80, 32)
// Tints for surfaces drawn on the pale albedo `spr_hall_pale` (a vertex
// colour multiplies its texture).
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
// How far into the recess the orb stands. `hall_orb_x` is the one place that
// turns this into a position, for both the geometry and the light
// (`test_hall_orb`).
#macro HALL_ORB_STAND 84
#macro HALL_ORB_CRADLE 28     // ...and the gilt cup it sits in
#macro HALL_ORB_BLOOM 5.2     // the bloom card's radius, in orb radii

// Steering, as the grove's lean: an ease and a per-frame cap.
#macro HALL_LEAN 92
#macro HALL_LEAN_EASE 0.022
#macro HALL_LEAN_SPD 1.7

// What stands in the nave, in world units.
#macro HALL_STATUE_X 548
// The statue figure's height, standing on `HALL_STATUE_BASE`.
#macro HALL_STATUE_H 300
// How strongly the statue's additive layer (her lit edge and her eyes' glow)
// is drawn.
#macro HALL_STATUE_RIM 0.85
// Facets round each part of the statue's swept cross-section.
#macro HALL_STATUE_STEPS 16
// The pedestals stand on the statue line, midway between two statues.
#macro HALL_DESK_X 548

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

// A prop's colour: the share of its texture it shows.
#macro HALL_PROP_LIGHT 0.88
// Alpha test threshold. Cut-out sprites on quads have transparent corners
// that would otherwise write depth.
#macro HALL_ALPHA_REF 96

// ---------------------------------------------------------------------------
// The hall's light (`sh_hall`, set by `hall_shader`)
//
// Lit per pixel by the night through the open roof and by the fires and orbs,
// which repeat with the bays. Colours are `[r, g, b]` multipliers on a
// texture (1 shows it as painted), so near its source a light can drive a
// surface past its own colour. All first guesses, tuned by eye.
// ---------------------------------------------------------------------------

// What every surface gets with nothing lighting it.
#macro HALL_AMB [0.040, 0.048, 0.090]
// The night through the roof: its light on a surface that sees all of it, and
// what a polished surface reflects of it.
#macro HALL_SKYLIGHT [0.46, 0.60, 1.15]
#macro HALL_SKYSHINE [0.16, 0.22, 0.44]
// The moon, off to one side and behind the camera (it isn't in the painted
// sky): the direction toward it, and its light.
#macro HALL_MOON_DIR [-0.42, 0.86, -0.28]
#macro HALL_MOONLIGHT [0.40, 0.54, 1.00]
// The sky's share at the very start of the opening, and after the reveal.
#macro HALL_SKY_DAWN 0.55
#macro HALL_SKY_REVEAL 1.25
// How much of the fog a light (the light pass) takes: less than a surface,
// so a far fire still shows through the haze.
#macro HALL_LIGHT_FOG 0.55
// How much of the fires' light the air holds (fog near a fire glows).
#macro HALL_SCATTER 0.12

// Baked occlusion (`hall_wall_light`, `hall_floor_light`): what the foot of a
// wall keeps, over what height, and the width of floor it darkens.
#macro HALL_AO_FOOT 0.55
#macro HALL_AO_FOOT_H 240
#macro HALL_AO_FLOOR_W 110

// Surfaces, as `[gloss, shininess, metal, gloss map]` (`hall_mat`). A gloss
// map is the texture's alpha, on opaque tiles.
#macro HALL_MAT_STONE [0.10, 14, 0, 0]
#macro HALL_MAT_CARVED [0.45, 30, 0, 1]
#macro HALL_MAT_BOOKS [0.06, 10, 0, 0]
#macro HALL_MAT_GILT [0.70, 34, 1, 0]
#macro HALL_MAT_GLASS [0.90, 60, 0, 0]
#macro HALL_MAT_MARBLE [0.80, 70, 0, 1]
#macro HALL_MAT_RUNNER [1.00, 110, 0, 1]
#macro HALL_MAT_BORDER [0.80, 70, 0, 1]
// The statue's alpha is a gloss map too, so her solid has no holes where it
// samples just outside her outline (`bastet` carries her colour out there).
#macro HALL_MAT_STATUE [0.40, 90, 0, 1]
#macro HALL_MAT_CLOTH [0.04, 8, 0, 0]

// The torches: a gilt stand at every bay joint, both sides, just in from the
// wall (`hall_torch`). Its fire is a light in `sh_hall` and a card
// (`hall_draw_flames`).
#macro HALL_TORCH_X 612
#macro HALL_TORCH_H 290          // the stand, floor to the bowl's lip
#macro HALL_TORCH_Y 318          // the fire's heart: its light and its card
#macro HALL_TORCH_R 1000         // how far its light reaches
#macro HALL_TORCH_COL [1.00, 0.62, 0.30]
#macro HALL_TORCH_POW 3.2
#macro HALL_TORCH_TINT make_colour_rgb(255, 150, 70)
#macro HALL_TORCH_EMBER make_colour_rgb(230, 84, 24)
#macro HALL_TORCH_FLAME 70       // a fire card's size

// The pilasters' glyphs as light (`hall_glyph_glow`): their colour, their
// steady level, how much the torches' catching flares them, and the pulse
// that runs down the hall: how often, how fast (world units a frame), how
// long a stretch it lights, and how bright.
#macro HALL_GLYPH_COL make_colour_rgb(110, 196, 255)
#macro HALL_GLYPH_BASE 0.16
#macro HALL_GLYPH_FLARE 2.0
#macro HALL_GLYPH_PULSE_P 720
#macro HALL_GLYPH_PULSE_V 70
#macro HALL_GLYPH_PULSE_W 700
#macro HALL_GLYPH_PULSE_A 0.75

// The orbs' light and the braziers'.
#macro HALL_ORB_REACH 1000
#macro HALL_ORB_LIGHT [0.32, 0.60, 1.00]
#macro HALL_ORB_POW 2.2
#macro HALL_BRAZIER_REACH 820
#macro HALL_BRAZIER_LIGHT [1.00, 0.64, 0.32]
#macro HALL_BRAZIER_POW 2.2
#macro HALL_BRAZIER_FLAME 110

// The fire cards: the halo's two layers, and the flame strip's frames and
// rate (frames a hall frame).
#macro HALL_HALO_WIDE 4.2
#macro HALL_HALO_WIDE_A 0.20
#macro HALL_HALO_CORE_A 0.55
#macro HALL_FLAME_FRAMES 16
#macro HALL_FLAME_RATE 0.22

// The pavement's reflection of a fire (`hall_draw_reflections`): the smear's
// size in fire sizes, and how bright it is.
#macro HALL_REFL_W 1.6
#macro HALL_REFL_H 5.5
#macro HALL_REFL_A 0.30
#macro HALL_REFL_CORE_A 0.45
// The Fresnel reflectance at which a reflection is at full strength (a level
// look down the hall reaches it; from above it is a tenth of it).
#macro HALL_REFL_FRESNEL 0.30

// The post-process (`hall_post`): what brightness blooms, how much, the
// vignette, and the floor the shadows are lifted to.
#macro HALL_BLOOM_THRESH 0.42
#macro HALL_BLOOM_A 0.85
#macro HALL_VIGNETTE 0.55
#macro HALL_LIFT [0.010, 0.012, 0.024]

// ---------------------------------------------------------------------------
// The opening (`hall_step`)
//
// The hall wakes over `HALL_INTRO_TIME` frames. The parts are placed within
// it in frames; a `[from, to]` pair is a stretch it eases across.
// ---------------------------------------------------------------------------
#macro HALL_INTRO_TIME 1800
#macro HALL_WAKE_VEIL [0, 90]      // the black lifts
#macro HALL_WAKE_HOLD 110          // where it waits while `wait` is set
#macro HALL_WAKE_TORCH 170         // the first torches catch
#macro HALL_WAKE_ORB 560           // ...and the orbs
#macro HALL_WAKE_BEAM [360, 1100]  // the moonbeam fades as they take over
#macro HALL_WAKE_TILT [200, 1500]  // the camera tilts forward and sinks
#macro HALL_WAKE_GO [120, 1740]    // ...and gathers speed
// The share of phase A's speed it starts at.
#macro HALL_INTRO_SPD 0.06
// The opening's first camera: high and looking nearly straight down.
#macro HALL_CAM_OPEN 1230
#macro HALL_PITCH_OPEN -84
// A front of lights catching (`hall_front`): how far behind the start it
// begins, and its speed and acceleration (world units a frame, and a frame
// squared).
#macro HALL_FRONT_BACK 160
#macro HALL_FRONT_V 11
#macro HALL_FRONT_A 0.045
#macro HALL_FRONT_ALL 100000000
// The moonbeam the opening starts in: a shaft falling straight down onto the
// first bays, where the first camera looks. Where along the hall it falls,
// the radius of its pool, its colour and its strength at full.
#macro HALL_BEAM_Y 0
#macro HALL_BEAM_Z 200
#macro HALL_BEAM_R 760
#macro HALL_BEAM_COL [0.50, 0.66, 1.00]
#macro HALL_BEAM_POW 1.5
// Frames into the reveal before the braziers begin to catch.
#macro HALL_BRAZIER_WAKE 40

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
// ...and how it catches the light (`hall_draw_front`): what it shows with
// nothing lighting it, how far from a torch it glints, how much, and the
// colours it takes from a torch and from the moonbeam.
#macro HALL_SAND_DARK 0.30
#macro HALL_SAND_GLOW_R 520
#macro HALL_SAND_GLINT 2.2
#macro HALL_SAND_WARM make_colour_rgb(255, 196, 128)
#macro HALL_SAND_COLD make_colour_rgb(176, 206, 255)
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
