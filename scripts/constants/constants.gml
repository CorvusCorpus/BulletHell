/// @desc Every number the game is tuned by, and the enums it is shaped by.
///
/// **The whole game runs on a fixed 60Hz step and counts frames, never
/// seconds.** Every duration here is a frame count. That is not nostalgia: a
/// danmaku pattern is a sequence of exact angles fired on exact ticks, and a
/// pattern that advances by `delta_time` is a pattern that is subtly different
/// on every machine and impossible to assert anything about.
/// `check_delta_time_in_rules` in `tools/check_project.py` refuses `delta_time`
/// inside `scripts/`, so the self-test can step a boss through nine hundred
/// frames in a few milliseconds and read the bullets it laid down.
///
/// Where a figure is easier to think about in seconds it is written as
/// `seconds * FPS`, so the arithmetic stays visible rather than pre-multiplied.

#macro FPS 60

// ---------------------------------------------------------------------------
// The screen
//
// The design resolution, and the only thing `GAME_*` is for. Anything that
// genuinely owns the whole display -- the pause scrim, the result panel, the
// flash -- measures from these; everything about the playfield measures from
// `FIELD_*` and everything about the readouts from `HUD_*`.
// ---------------------------------------------------------------------------

#macro GAME_W 1920
#macro GAME_H 1080
#macro GAME_CX 960
#macro GAME_CY 540

// ---------------------------------------------------------------------------
// The field
//
// **The field is a bounded rectangle inside the screen, and the HUD lives
// outside it.** This reverses what this project started from, so the reasoning
// is worth writing down properly.
//
// The original bargain was: let the danmaku have all 1920x1080, put the
// readouts in the corners, and have them fade as the player approaches. Two
// things went wrong with it, and only the second is fixable by tuning.
//
// The first is that a fading readout is a readout you cannot rely on. The one
// moment you most want to check your life is the moment you are deepest in a
// pattern -- which is exactly when the fade has taken it down to its floor.
//
// The second is worse and is a matter of arithmetic. A readout has to be big
// enough to read at a glance from a metre away, and anything big enough to do
// that is big enough to hide bullets. Every attempt at fixing the legibility
// made the occlusion worse; every attempt at fixing the occlusion made the
// legibility worse. There is no size that satisfies both, because they are the
// same pixels.
//
// So the field gets a boundary and the HUD gets its own real estate. What that
// buys, beyond the obvious:
//
//   - **The HUD can be as loud as it likes.** Nothing it draws is over
//     anything, so there is no fade rule, no alpha budget, and no reason for
//     any number on this screen to be small.
//   - **It is assertable.** "No HUD element overlaps the field" is a rectangle
//     test, and `test_hud_layout` now runs it. The fade rule was never
//     testable, which is why it shipped measuring from one corner of a bar.
//   - **A bullet leaving the field is unambiguous.** Culling, the near layer's
//     keep-out, and where a wave enters from are all questions about the field
//     now, and the field has edges.
//
// What it costs is the full-bleed look, and the field is deliberately kept
// wide -- 1360x868 is nothing like a Touhou strip -- so that the fast,
// horizontal game this is meant to be still has room to be one.
//
// **Everything about the playfield is measured from these**, not from
// `GAME_*`. `GAME_*` is now only for things that genuinely own the whole
// screen: the title, the pause scrim, the result panel and the flash.
// ---------------------------------------------------------------------------

// **The margin is the same width on three sides and the fourth is the
// console.** The strip above the field used to be 168 pixels of nothing
// holding a boss's name set at 66pt and a health tube spanning the screen --
// a sixth of the display, spent on two readouts, next to a right-hand column
// with room to spare. Both of those moved: the tube is *inside* the field
// where the genre has always put it, the name is centred and small above it,
// and the 124 pixels that bought back went to the playfield.
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

// The ornamented outer frame: where the corner pieces sit, how big they are,
// and -- derived from both -- where the rule they stand on runs.
//
// **`UI_CORNER_INSET` mirrors `o` in `tools/make_ui.py`**, which is how far
// into its own sprite the corner piece draws its bracket. The two have to be
// edited together, exactly as `BG_NEAR_EDGE` and `NEAR_EDGE` are: get it wrong
// and the rule is a second line running near the corners rather than the line
// they are the corners of, which is the difference between a frame and four
// ornaments beside a box.
#macro UI_CORNER_INSET 11

// How far the corner piece reaches *away* from the edge it runs along -- the
// far end of its chamfer, which is the deepest ink in the sprite. Also
// mirrored from `tools/make_ui.py`, where it is `o + chamfer`.
//
// **This is what decides `FIELD_ORN_OUT`, and getting it wrong put ornament on
// the playfield.** A corner piece is not a thin line along an edge: near the
// elbow it is 37 pixels deep, so pushed only 16 pixels out it had its set
// stone seven pixels *inside* the field. Seven pixels of near-black in the
// extreme corner is not going to cost anybody a life, and that is not the
// standard -- nothing decorative is drawn over the playfield, and the rule is
// worth keeping absolute precisely because every individual exception to it
// sounds this reasonable. `test_hud_layout` asserts it.
#macro UI_CORNER_DEPTH 37

#macro FIELD_ORN_SCALE 0.62
#macro FIELD_ORN_OUT 24
#macro FIELD_RULE_OUT (FIELD_ORN_OUT - UI_CORNER_INSET * FIELD_ORN_SCALE)

// How far in from the field's own edge the player is held. Not zero: a player
// pinned into the literal corner has nowhere to dodge, and every pattern would
// end there.
#macro FIELD_MARGIN 34

// A bullet is culled this far outside the screen. Generous, because a pattern
// that sweeps in from off-screen has to exist before it arrives, and a bullet
// culled at the edge would pop into being in front of the player.
#macro CULL_MARGIN 160

// The share of the *field's* width at each edge the near parallax layer may
// occupy. It draws over the field, so anything it puts in the middle is
// somewhere a bullet can hide. `tools/make_bg.py` builds to this number and
// `check_bg_keepout` measures the shipped PNG against it -- and since the
// layers are now generated at the field's size rather than the screen's, the
// fraction means the same thing in both places without any conversion.
#macro BG_NEAR_EDGE 0.13

// **How opaque the foreground may ever be, and this is a fairness rule rather
// than a look.**
//
// The near layer is the one piece of scenery drawn *over* the danmaku. The
// keep-out window stops it standing in the middle of the field, and that was
// treated as the whole of the problem -- the reasoning being that the player is
// rarely dodging in the outer sixth. That reasoning is wrong, and it was
// reported the way this class of bug is always reported: "I am taking damage
// and there is nothing on screen."
//
// There *was* something on screen. It was behind a spire. An opaque foreground
// over a live playfield does not hide scenery, it hides *bullets*, and a bullet
// the player cannot see is a bullet they cannot dodge -- which is the one thing
// this whole project is arranged to prevent, from the delay marks to the
// contour on every sprite.
//
// So the layer is translucent, and low enough that a lit bullet reads straight
// through it. What is lost is a little of the depth; what is bought is that no
// arrangement of art in this layer can ever cost the player a life.
#macro BG_NEAR_ALPHA 0.42

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

// **Tuned for a 1920-wide field, not for a 384-wide Touhou strip.** The first
// pass of every speed in this file was picked by eye against the genre's own
// numbers, and the genre's numbers are for a playfield a fifth of this one's
// width: a player at 7.2 px/frame takes four and a half seconds to cross this
// screen, where a Touhou player crosses theirs in under one. What that
// produced was a game that felt sluggish everywhere without any single number
// looking wrong, because none of them were wrong -- they were answers to a
// different question about the size of the room.
//
// So the traversal *time* is what is held fixed rather than the pixel rate.
// Everything that moves is up by roughly half again, and the field being five
// times wider is why the factor is not larger still: the vertical axis has
// only grown by 2.4, and a player who crossed the width in a second would
// cover the height in half of one.
#macro PLAYER_SPD 11.0
#macro PLAYER_SPD_FOCUS 4.6

// **The hitbox is tiny and it is the whole game.** Four pixels against a
// sprite eighty wide is the contract danmaku is built on: the picture is a
// character, the hitbox is a point, and holding focus is what tells you so.
#macro PLAYER_R 4.0
#macro GRAZE_R 30.0

// **A laser is grazed on a cooldown, where a bullet is grazed once ever.**
// The flag a bullet carries is the right answer for a thing that passes and is
// gone; a laser is a wall that stands there for two seconds, and a flag would
// pay a player who touched it for a frame exactly as much as one who rode it
// the whole way. So sliding along a beam pays every `LASER_GRAZE_CD` frames,
// which is what the genre does and what ph3 spells `SetGrazeInvalidFrame`.
#macro LASER_GRAZE_CD 20

#macro HP_MAX 100
#macro HP_PER_HIT 25
#macro HP_QUADRANT 25          // where the markers on the bar go
#macro IFRAME_TIME (3 * FPS)   // invulnerable after a hit

#macro MP_MAX 100
#macro MP_PER_BOMB 25
#macro BOMB_INVULN 150         // 2.5s of grace on a special
#macro BOMB_CLEAR_R 560        // bullets inside this are swept
#macro BOMB_GROW 26            // frames the sweep takes to reach full radius

// The shot. Two barrels that converge slightly, and a focused mode that
// narrows them -- the standard trade, and the reason focus is not purely a
// dodging tool.
#macro PSHOT_PERIOD 3          // frames between volleys
#macro PSHOT_SPD 36
#macro PSHOT_DMG 0.75
#macro PSHOT_SPREAD 7.0        // degrees off straight ahead, unfocused
#macro PSHOT_SPREAD_FOCUS 1.5
#macro PSHOT_OFFSET 26         // how far either side of centre a barrel sits

// **How far in front of him a bolt is born.** `spr_szuix` is 122x102 with its
// origin on his chest, so his horns are 56 pixels above the point the player
// occupies; anything spawned closer than that is spawned *inside* him and
// spends its first frames hidden behind his own sprite. See `player_fire`.
#macro PSHOT_MUZZLE 62

#macro PLAYER_HIT_SHARDS 10    // scattered on a hit, so a hit is not only loss

// ---------------------------------------------------------------------------
// Pools
//
// Hard caps, and every one is a *refusal* rather than a resize. A pool that
// grows without limit turns a runaway pattern into a machine that stops
// responding, which is far worse to find than a pattern that visibly stops
// firing. `danmaku_stats` reports how close a run came to each.
// ---------------------------------------------------------------------------

#macro BULLET_MAX 4096
#macro PSHOT_MAX 512
#macro ITEM_MAX 512
#macro ENEMY_MAX 128
#macro LASER_MAX 96
#macro PARTICLE_MAX 1024
#macro FLOATER_MAX 64          // floating text

// A curved laser is a trail of positions. This is how many it keeps, which
// makes its length a number of *frames* rather than of pixels -- so a fast one
// is longer, which is both correct and what it looks like in the games this is
// imitating.
#macro CURVE_NODES 64

// ---------------------------------------------------------------------------
// Bullets
// ---------------------------------------------------------------------------

// A bullet spends its delay fading in and *intangible*. This is the single
// most important fairness rule in the genre: a boss that spawns a hundred
// bullets on top of the player kills them before the frame is drawn, so every
// bullet is born as a soft mark that says "something is about to be here".
#macro BULLET_DELAY_DEFAULT 8
#macro BULLET_DELAY_SCALE 2.6      // how much larger the mark starts

// A bullet born out of another one -- a split or a shed -- gets a shorter
// mark than one fired from a boss. The player is already looking at the parent
// and the burst comes out of a place they are watching, so the warning has
// less work to do; what it must still do is exist, because a burst on top of
// the player is precisely the case the marks were written for.
#macro BULLET_SPLIT_DELAY 4

// When a phase is cleared every bullet on screen converts to score, which is
// the reward for finishing a spell and the reason clearing one feels like an
// exhale.
#macro CLEAR_ITEM_EVERY 7          // one shard per N bullets swept

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

// **Auto-collect above a line.** Touhou's point-of-collection: fly to the top
// of the field and everything comes to you. It is the one place the genre
// rewards being where the bullets are, and removing it would remove the only
// reason to ever go there.
#macro ITEM_AUTO_LINE 240

// ---------------------------------------------------------------------------
// Scoring
//
// Named `tally` throughout and never `score`. **`score` is a built-in global
// GameMaker still carries from GM8**, and a variable of that name silently
// splits in two: `g.score = 5` writes an instance variable and a bare `score`
// in the same object reads the global. It compiles, it runs, nothing warns,
// and the number on screen never moves. `check_legacy_globals` refuses it.
// ---------------------------------------------------------------------------

#macro TALLY_GRAZE 40
#macro TALLY_ENEMY 250
#macro TALLY_ITEM 120
#macro TALLY_SPELL_CLEAR 40000
#macro TALLY_PHASE_CLEAR 12000
#macro TALLY_NO_HIT_BONUS 100000

// ---------------------------------------------------------------------------
// Enemies and bosses
// ---------------------------------------------------------------------------

#macro ENEMY_FLASH 5               // frames an enemy whitens when hit
#macro ENEMY_DEATH_BITS 14

#macro BOSS_ENTRY_TIME (2 * FPS)
#macro BOSS_DECLARE_TIME (3.4 * FPS)   // the name splash
#macro BOSS_PHASE_PAUSE (1.4 * FPS)    // invulnerable, between attacks

// **How long attack practice waits before the attack starts.** Longer than the
// pause between attacks in a fight, because it is doing a different job: there
// the player arrives from the attack before it, already somewhere they chose,
// and here they arrive at the default spawn with a pattern about to open on
// them.
//
// It is two seconds rather than three because `BOSS_SPELL_LEAD` now follows
// it: a practised spell gets this *and* its declaration, which is three and a
// half seconds before a bullet, and this is a mode whose whole value is how
// quickly it can be done again. A non-spell gets the two seconds alone, which
// is what a non-spell is worth -- they are wide and slow by design.
#macro PRACTICE_READY (2 * FPS)
#macro BOSS_SPELL_BANNER (2.6 * FPS)   // how long the spell name holds
#macro BOSS_EYE_TIME (1.5 * FPS)       // the eye card

// **How long a spell declares itself before its pattern opens.** The genre's
// rule, and it was missing: a spell used to fire from the frame it was named,
// so the eye card announcing it was drawn over bullets it had already
// launched. The boss is invulnerable through this and the phase clock has not
// started, so nothing is lost or gained by it.
//
// It is the eye card's own length, because the card is the piece of the
// ceremony that *occludes* -- a face across the middle of the field is the
// thing bullets must not be under, where the banner is one line of outlined
// text sliding out and danmaku beneath it is what the genre looks like. So the
// pattern opens as the face leaves and the banner is still going.
#macro BOSS_SPELL_LEAD BOSS_EYE_TIME

// A boss drifts rather than standing still, so it is never a fixed target and
// the aimed patterns it fires leave from a moving origin.
#macro BOSS_DRIFT_SPD 1.1

// How far a boss wanders from its station, and how fast. Wide, because the
// field is wide: a boss confined to the middle third of a 1920px screen is a
// boss the player never has to turn round for.
#macro BOSS_DRIFT_X 430
#macro BOSS_DRIFT_Y 74
#macro BOSS_DRIFT_RATE 0.075   // how sharply it chases its wander point

// Where a boss holds station, measured down the field. A boss's station is a
// fact about the arena rather than about the readouts, which is why it is here
// and not among the HUD constants.
//
// **Clear of its own name and its own bar.** Those are drawn over the top of
// the field now, and `spr_boss_ziggy` is 250 tall on a centred origin, so a
// boss stationed where the old strip let it stand would fly its head through
// its own health tube. 320 less a drift of 74 less half a sprite leaves the
// top of the boss thirty pixels under the bar at its highest -- and since the
// field grew by 124 at the same time, the fight sits at very nearly the screen
// position it always did while the player gets every pixel of the growth.
#macro BOSS_HOME_Y (FIELD_Y0 + 320)

// ---------------------------------------------------------------------------
// The HUD
//
// **One console down the right-hand side, and a thin line inside the field.**
// That is the whole layout, and it is the third arrangement this project has
// had. The first put the readouts in the corners of a full-bleed field and
// faded them as the player flew near -- unwinnable, because a readout big
// enough to read at a glance is big enough to hide a bullet and fading it
// makes it unreadable exactly when it is most needed. The second gave the
// field a boundary and put the readouts in two margins: a 168px strip above
// and a column beside.
//
// The strip was the part that did not earn its keep. It carried a boss's name
// at 66pt and a health tube 1360 wide -- a sixth of the display spent on two
// facts -- and it was empty for the two or three minutes of every stage before
// the boss arrives. The genre has always drawn a boss's bar *over* the
// playfield, and it is right to: the bar is a fact about the thing you are
// shooting, so it belongs beside it, and a line fourteen pixels tall is a
// rounding error against a field of 992.
//
// So the strip is gone, the field grew into it, and there is one region left:
//
//   the console, right of the field   everything that is not the boss
//   a line inside the field's top     the boss's name, bar, marks and timer
//
// `hud_box` is still the only thing that knows where anything is, and
// `test_hud_layout` still walks it -- see the note there about the one box
// that is now *deliberately* over the field, and what is asserted instead.
// ---------------------------------------------------------------------------

// How far the console's own contents are inset from its plate.
#macro HUD_PAD 24

// **What a caption is drawn in, and it is one macro because it is the most
// repeated element on the screen.** Five tags run down the console and they
// set its colour more than any single ornament does -- grey caption text over
// a violet plate is the exact combination that reads as a settings dialog
// rather than as an illuminated panel. Antique gold: the gilt taken most of
// the way down toward the ground it sits on, so it is legible without
// competing with the values beside it.
#macro HUD_TAG_COL merge_colour(COL_GILT, COL_ARCANE, 0.3)

// **The console is a plate, not a region.** It has edges, a material and
// corners, so it is drawn rather than merely occupied -- see `hud_draw_plate`.
// It stands the same height as the field and is separated from it by a gap
// about half the field's own margin, which is what reads as two panels on one
// fascia rather than as a picture with a list beside it.
//
// **It stands to the field's outer rule, not to the field.** Set flush with
// `FIELD_Y0` the plate's top edge sits seventeen pixels below the ornamented
// rule that frames the picture beside it, and two panels on one fascia that
// disagree about where the top of the fascia is read as one of them having
// slipped -- which is exactly how it was reported: "the right side UI area is
// slightly unaligned, too low next to the game screen". `FIELD_RULE_OUT` is
// where the field's own frame runs, so both outer edges are now the same line.
#macro HUD_PANEL_X0 (FIELD_X1 + 20)
#macro HUD_PANEL_X1 (GAME_W - 32)
#macro HUD_PANEL_Y0 (FIELD_Y0 - FIELD_RULE_OUT)
#macro HUD_PANEL_Y1 (FIELD_Y1 + FIELD_RULE_OUT)

#macro HUD_COL_X (HUD_PANEL_X0 + HUD_PAD)
#macro HUD_COL_W (HUD_PANEL_X1 - HUD_PAD - HUD_COL_X)

// The rows in it. **Written out rather than derived**, because a column of
// readouts is a layout and a layout is a list of positions: deriving each from
// the height of the one above means a font change silently moves everything,
// which is how a HUD drifts. `test_hud_layout` asserts the order and the
// spacing, so a typo here is a failed suite rather than two readouts on top of
// one another.
//
// **The meters sit in the middle, not at the foot.** They were at the foot
// first, on the reasoning that a danmaku player lives in the bottom half of the
// field so a life bar level with the character is one the eye reaches without
// leaving the pattern. That is a real argument and it lost to a simpler one:
// the console is a column and a column is read top to bottom, so the order down
// it should be the order of *importance*, and life is more important than a
// ledger of grades. The meters now sit directly under the score, which also
// groups the four things that are true every frame into one block and leaves
// the whole bottom of the plate to the one thing that grows -- see
// `HUD_ROW_MARKS`. What is given up is about 350 pixels of eye travel, which is
// worth less than not having to hunt for the life bar under a list.
//
// **Four sections of comparable height, not four crammed at the top.** The
// first pass of this layout put the header, the score, the graze count and the
// attack row in the console's top four hundred pixels, the meters in its last
// two hundred, and left three hundred and thirty pixels of plate in the middle
// with nothing on it -- which is the same complaint that removed the strip
// above the field, reappearing on the other axis. A console with a hole in it
// is a console that has not been laid out.
//
// So the rows are spread across the whole plate, and the two sections that
// only exist during a boss fight -- the attack marks and the spell nameplate
// -- were merged into one. That is the fix the first respacing missed: moving
// a hole is not closing it, and *two* conditional sections leave two holes
// whatever their heights. One conditional section can be given a tenant that
// is never absent, and `hud_draw_engagement` is that tenant.
//
// **Every readout is one line, so the rows closed up.** Collapsing the score's
// tag and its numerals onto a shared centre freed a row's worth of height and
// the layout kept the old spacing anyway, which turned a tidy-up into a
// console with visible gaps between every line. Rows that share a shape should
// share a rhythm: `BEST`, `SCORE` and `GRAZE` are one pitch apart, the two
// meters are one pitch apart, and the space that was reclaimed went to the
// ledger at the foot rather than being left between things.
#macro HUD_ROW_CREST 8             // the headpiece, down from the plate's top
#macro HUD_ROW_STAGE 92            // the stage's name; subtitle 44 below it
#macro HUD_RULE_1 172
#macro HUD_ROW_BEST 202            // the stage's best, above this attempt's
#macro HUD_ROW_SCORE 274           // tag and numerals on one line
#macro HUD_ROW_GRAZE 346
#macro HUD_RULE_2 388
#macro HUD_ROW_LIFE 446            // the tube's top edge; its row 24 above it
#macro HUD_ROW_SIGIL 542
#macro HUD_RULE_3 622
#macro HUD_ROW_MARKS 656           // the ledger, and the rest of the plate

// ---------------------------------------------------------------------------
// The meters
//
// **Life and sigil are vessels of liquid, and they lie down.** The Wordsearch
// project worked the shape of a vessel out: a surface that sloshes, bubbles
// that rise and light that falls off with depth is read *peripherally*,
// because the part that moves is the part that carries the number. A flat bar
// has to be looked at, and in this genre looking away is how you die.
//
// They stood upright first, as a pair of 132x464 tubes at the foot of the
// column, and that was the wrong axis twice over. A vertical vessel is read
// against its own height, so two of them side by side are two lengths to
// compare rather than two numbers to glance at; and a column 416 wide filled
// with a pair of narrow uprights is a column mostly made of the gap between
// them. Lying down, each spans the console's full width, its name and its
// value share one line above it, and the two stack into a block that reads top
// to bottom like everything else in the console.
//
// **Every meter in the game is now this shape** -- life, sigil and the boss's
// health -- so `draw_gauge_h` is the only vessel, and `draw_gauge_v` went with
// the uprights.
// ---------------------------------------------------------------------------

#macro HUD_METER_W HUD_COL_W
#macro HUD_METER_H 52

// The surface: how far it displaces, and how many segments it is drawn in.
// Lifted wholesale from the Wordsearch gauges.
#macro LIQ_WAVE_A1 3.0             // pixels of displacement
#macro LIQ_WAVE_A2 1.7
#macro LIQ_WAVE_K1 4.6             // degrees per pixel along the surface
#macro LIQ_WAVE_K2 10.2
#macro LIQ_WAVE_S1 0.055           // degrees per millisecond
#macro LIQ_WAVE_S2 -0.083          // the second one runs the other way
#macro LIQ_WAVE_AMP (LIQ_WAVE_A1 + LIQ_WAVE_A2)
#macro LIQ_WAVE_STEPS 22           // segments the surface is drawn in

// How the *body* of a vessel is sampled. **The liquid follows the glass**,
// which a roundrect-shaped fill could never do -- see `capsule_half` and the
// note on it in `draw_gauge_h`.
//
// Two numbers rather than one, because a capsule is an arc at each end and a
// straight line between them: `LIQ_BODY_STEPS` is how many segments the
// straight part gets, and `LIQ_CAP_STEP` is the pixel spacing inside a
// radius of either end, where an evenly spaced walk crosses the entire curve
// in one segment and draws it as a triangle.
#macro LIQ_BODY_STEPS 40
#macro LIQ_CAP_STEP 1.5

// ---------------------------------------------------------------------------
// The boss's line, inside the field
//
// **Over the playfield, and that is a deliberate exception to the one rule the
// bordered field was built to keep.** Everything else the HUD draws is outside
// the boundary; this is not, because a boss's health belongs beside the boss
// and because every game in the genre puts it there.
//
// What makes the exception affordable is that the whole thing is a *line*. Its
// occlusion budget is its height, not its alpha: fourteen pixels of a
// 992-pixel field is one and a half per cent, and a bullet crossing it is
// hidden for a single frame at the slowest speed this game fires at. The name,
// the timer and the marks are outlined text on either side of it, which is
// what the genre does and what `draw_text_outline` exists for.
//
// `test_hud_layout` asserts the height rather than asserting the box is clear
// of the field, because the box is not clear of the field and is not meant to
// be. See the note there.
// ---------------------------------------------------------------------------

#macro BOSS_BAR_INSET 34           // in from the field's left and right edges
#macro BOSS_BAR_Y (FIELD_Y0 + 72)  // the tube's top edge
#macro BOSS_BAR_H 14
#macro BOSS_NAME_Y (FIELD_Y0 + 16) // the name and the timer, above the bar

// **The spell's name goes under the bar, and this reverses a decision.** It
// lived in the console for one pass, on the reasoning that forty seconds of
// nameplate over the play area is not affordable where two and a half seconds
// of banner is. Two things changed. The names are single now rather than a
// type and a title, so the plate is one short line instead of three; and a
// name that is a fact about the boss belongs where the boss's other facts are,
// which is the line the bar is on -- in the console it was the width of the
// column away from the health it refers to, and it clipped off the bottom of
// the plate the moment a title ran long.
//
// It is the same exception the bar itself is, on the same terms: outlined
// text, one line, at the top of the field where the boss is and the player is
// not.
#macro BOSS_SPELL_Y (BOSS_BAR_Y + BOSS_BAR_H + 10)

// The tallest a line drawn over the playfield may be. One number, so the
// exception above cannot quietly grow back into a strip.
#macro FIELD_OVERLAY_MAX_H 22

// **The spell name goes in the console, not over the play area.** It was at
// the bottom of the screen first, which on a full-bleed field is inside the
// player's working area -- the one permanent piece of text in the game
// competing for the pixels being read hardest.
#macro HUD_SPELL_W HUD_COL_W

#macro FONT_INK_RATIO 0.58         // see check_font_ink_ratio

// ---------------------------------------------------------------------------
// Spell backgrounds
//
// **Which one a spell uses is a property of the boss, not of the spell.** A
// spell background exists to say who is casting, and every boss in the first
// version got the same pair of counter-rotating magic circles -- which says
// nothing about anybody. A style is one of these plus a function in
// `bg_functions`, so a new boss costs a field and a function.
//
// `SPELLBG_SIGIL` is the fallback and is genuinely right for some casters; it
// is what the Warden uses, being a carved stone told to watch.
// ---------------------------------------------------------------------------

#macro SPELLBG_SIGIL 0
#macro SPELLBG_BRIMSTONE 1     // Ziggy: a forge, in red, grey and black

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// What a run is doing right now. The distinction that matters is that
/// `Paused` and `BossDeclare` both stop the clock while only one of them stops
/// the field being live.
enum Phase {
    Intro,        // the stage opening; the player is flying in, no input yet
    Playing,
    BossDeclare,  // the name splash; the field is live but the boss is not
    PhaseClear,   // bullets converting to shards, boss invulnerable
    Paused,
    Won,
    Lost,
}

/// How a bullet behaves *for as long as it lives*, beyond `spd`, `acc` and
/// `turn`. **Most bullets are `Plain`**, and the test is one integer compare,
/// so the interesting kinds cost nothing to the ninety per cent that are not.
///
/// **The one-shot changes used to live here as well**, as a single slot with a
/// frame number beside it -- which allowed a bullet exactly one event in its
/// life, and meant "accelerate at 30 and then turn at 60" was not a thing that
/// could be written. Those are `BQ` now and they queue. What is left here is
/// the two behaviours that are not events at all: they have no frame, because
/// they are what the bullet is doing on every frame.
enum BMod {
    Plain,
    Home,       // steers toward the player, weakly, for as long as it lives
    Wander,     // drifts on a sine -- wisp trails and dandelion patterns
}

/// What a bullet can be told to do *at a frame*. This is ph3's `AddPattern`
/// family and its `AddShot` pair, and the entries queue: a bullet carries up
/// to `BULLET_QUEUE_MAX` of them, sorted, and `bullet_step` walks them off the
/// front as its life reaches each one.
///
/// The arguments are `a`, `b`, `c`, `d` on the queue entry, and what each of
/// them means is per kind -- which is the bargain the single modifier slot's
/// own `mod_a`/`mod_b`/`mod_n` made before it, kept because a struct per kind
/// would allocate per scheduled event and this pool is built not to allocate.
/// Every one of them has a named
/// helper (`bullet_accel_at`, `bullet_split_at`, ...) so no pattern has to
/// remember which letter is which.
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

/// "Leave this one as it is", for the fields of `BQ.Move` that take a value a
/// bullet could legitimately be given. Zero speed and zero degrees are both
/// ordinary, so the sentinel has to be a number no pattern would ever mean.
#macro BQ_KEEP -999999

/// How many scheduled events one bullet may carry. **A refusal rather than a
/// resize**, on the same terms as `BULLET_MAX`: a pattern that queues without
/// limit is a pattern that quietly eats memory a frame at a time, which is far
/// harder to find than one whose fifth scheduled event visibly does nothing.
#macro BULLET_QUEUE_MAX 8

/// How long a bullet takes to fade out when it is deleted by time rather than
/// by leaving the field. **It fades rather than vanishing**, because a bullet
/// that blinks out of existence in the middle of the field reads as a bug in
/// the game rather than as a rule of the pattern -- and a fading bullet is
/// harmless from the first frame of the fade, so what the player sees leave is
/// gone before it looks gone rather than after.
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

/// The fodder. **Nothing here is a creature**: a stage is full of animated
/// objects -- a wisp, a grimoire, a cut gem -- because a world in which imps
/// are the trash mob should not be asking the player to shoot down imps.
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
    Spell,      // named, with a banner, an eye card and a background of its own
}
