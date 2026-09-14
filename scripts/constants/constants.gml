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

// **The special has two halves: the sigil takes, and the seals give it back.**
// The sweep is the half that was always there -- a circle of Szuix's sigil
// grows out from where he cast it and every bullet it reaches is erased, its
// magic streaming back into the circle's heart. `BOMB_SEAL_AT` frames later
// the heart lets go: `BOMB_SEALS` wisps of his fire spiral out, hunt whatever
// is nearest, and burst on it -- sweeping the bullets they pass and the ones
// round where they land. It is Touhou's Fantasy Seal turned to an imp who
// steals magic: what comes back at the boss is its own pattern, burnt blue.
//
// **The seals do damage, and that is a rule change rather than a picture.**
// The special used to hurt nothing. A seal that visibly strikes a boss and
// leaves its bar where it was reads as broken, so each lands for
// `BOMB_SEAL_DMG` -- six of them together are two seconds of the shot held
// on target, and like the shot they pass through a boss in ceremony.
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

// The close-up of Szuix that flashes as he casts -- the same card a boss's
// spell gets, for the same length. See `draw_eye_card`.
#macro PLAYER_CARD_TIME BOSS_EYE_TIME

// **The grace dial.** Wordsearch's combo ring, round Szuix instead of round a
// pointer: a faint circle for the whole grace and a bright arc for what is
// left of it, sweeping back to noon, tightening as it goes and flickering in
// its last `GRACE_URGENT`. Sized to clear his wings at full and to sit just
// inside their tips as it closes. See `player_draw_grace`.
#macro GRACE_RING_R_FULL 80
#macro GRACE_RING_R_EMPTY 62
#macro GRACE_URGENT 0.3

// **One hit from death, he beats.** A heartbeat rather than a flash -- two
// pulses and a rest -- because a warning that flickers constantly is one the
// eye learns to ignore within a minute, and a rhythm is noticed without being
// looked at. `LOW_HP_BEAT` is frames per beat.
#macro LOW_HP_BEAT 48

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
#macro RING_MAX 24
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
// Rings
//
// **The first thing on this field that is neither a bullet nor an enemy.** A
// ring is furniture the boss puts down: it cannot be destroyed, it stops the
// player's shots along its metal, and when it is charged the metal kills. See
// `scripts/ring_functions` for the whole argument and `stage_sanctum` for the
// fight built out of them.
// ---------------------------------------------------------------------------

// **Every ring in the game is this size and there is no way to make one that
// is not.** The radius is a macro rather than a field on the struct, which is
// the difference between a rule and a convention: an attack cannot ask for a
// bigger ring, so six of them on the field are six of the same object and the
// player learns one shape once.
//
// The number is set against the *bullets*: `BSHAPE_SPHERE` is the largest
// thing this game fires at 108 pixels across, and a ring is 167 -- moderately
// bigger, and nothing like the 400-pixel gates the first pass drew. Those read
// as architecture rather than as the bands he wears, and at that size two of
// them walled the field.
#macro RING_R 72

// Half the metal's thickness, as a fraction of the ring's radius.
//
// **This is the sprite's own proportion and it is quoted in
// `tools/make_rings.py`.** Because the sprite is scaled uniformly, holding the
// number in one place is what makes the band that is drawn and the band that
// blocks a shot the same shape by construction rather than by agreement --
// the property `capsule_half` buys the meters and `laser_draw_curve` buys a
// curve. `UI_CORNER_DEPTH` mirrors a generator for the same reason.
#macro RING_BAND_FRAC 0.16

// ...and what that comes to in pixels. Every test in the file is against this.
#macro RING_BAND_HALF (RING_R * RING_BAND_FRAC)

// Where the band's centre line sits in the sprite, as a fraction of its half
// width: 200 of 256. Also `make_rings.py`'s, and the only other number the two
// have to agree about.
#macro RING_SPR_LINE 0.78125

// How much of the metal actually kills when it is charged. Under the drawn
// width, on the genre's rule -- see `ring_kill_half`.
#macro RING_KILL_FRAC 0.62

#macro RING_FORM 34                // frames arriving: no block, no kill
#macro RING_FADE 22                // frames leaving
#macro RING_WARN 40                // the default charge, before the metal bites
#macro RING_GRAZE_CD 20            // as a laser's: a wall pays repeatedly

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

// **Loose horizontal tracking**: `BossMove.Track`. The station walks toward
// the player's column at a bounded speed rather than easing proportionally,
// and that is the whole difference between "trends toward" and "follows". A
// proportional ease moves *fastest* when the player is furthest away, which is
// the opposite of loose; a speed cap means a player who crosses the field
// genuinely gets out from under the boss and keeps that advantage for the
// couple of seconds it takes to walk back.
//
// A third of `PLAYER_SPD`, and within a whisker of how fast the drift's own
// wander point already travels -- 430 pixels of amplitude at 0.55 degrees a
// frame peaks at about 4.1 -- so a tracking boss reads as the same creature
// moving at the same pace, just with somewhere to be.
#macro BOSS_TRACK_SPD 4.0

// How far it still wanders either side of the tracked column. **A tracking
// boss that sat exactly above the player would fire every aimed pattern
// straight down**, which is the thing drifting exists to prevent, reintroduced
// by the fix for it. At the station's height against a player near the bottom
// of the field this is about ten degrees either way, which is enough to make
// an aimed fan arrive somewhere different each time.
#macro BOSS_TRACK_SWAY 120

// How close the boss's centre may come to the side of the field: half the
// widest boss sprite, so the sprite stays inside the picture.
//
// **The sway is squashed against this rather than the station being held off
// it.** Holding the station back by a whole sway would leave a cornered player
// with the boss 240 pixels away and unhittable, which defeats the point of
// tracking a player who is pinned. Clamped this way the wander flattens as the
// boss reaches the edge and it still passes over the corner.
#macro BOSS_TRACK_EDGE 130

// Where a boss holds station, measured down the field. A boss's station is a
// fact about the arena rather than about the readouts, which is why it is here
// and not among the HUD constants.
//
// **Clear of its own bar, and of nothing else.** `spr_boss_ziggy` is 250 tall
// on a centred origin, so 250 less a drift of 74 less half a sprite leaves the
// top of the boss twenty-three pixels under the tube at its highest.
//
// **It used to be 320, and what was in the way was type rather than the
// bar.** The name was centred over the middle of the line and the timer sat
// beside it, so the boss had to hold station clear of a block fifty-six pixels
// deep that it was never going to touch anyway -- and at 320 the foot of the
// sprite reached past the middle of the field on the low half of its drift,
// which is a boss leaning over the player for the whole fight. Reported as
// oppressive, and it was: a boss belongs at the top of the arena, and the
// player owns everything under it.
//
// Moving the name and the timer to the two ends of the bar gave the middle of
// the line back, and the station came up with it. What the fight loses is
// nothing -- the boss is still 250 pixels down a 992-pixel field -- and what
// the player gains is 70 pixels of room under the thing shooting at them.
#macro BOSS_HOME_Y (FIELD_Y0 + 250)

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
#macro BOSS_BAR_Y (FIELD_Y0 + 14)  // the tube's top edge
#macro BOSS_BAR_H 14

// **The bar is the top of the field and the words are under it.** They were
// the other way round: the name centred over the bar and the timer beside it,
// which put fifty-six pixels of type between the top of the playfield and the
// only part of the line that is a *number the player reads while dodging*.
// The bar is fourteen pixels and is the thing that wants to be pinned to an
// edge; type can hang off it.
//
// **And the words moved out of the middle at the same time.** The name was
// centred precisely because the boss used to stand clear below it -- so the
// caption could own the centre and the boss would never be under it. Raising
// the boss takes that away: the centre of the top of the field is where its
// face now is. So the name goes back to the left-hand end of the bar and the
// timer to the right-hand end, which is where the genre has always put them
// and which leaves the whole middle of the line to the boss.
#macro BOSS_NAME_Y (BOSS_BAR_Y + BOSS_BAR_H + 6)

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
// text, one line, at the top of the field where the player is not.
//
// **It stacks under the boss's own name rather than being centred**, for the
// same reason that one moved: the middle of this line belongs to the boss
// now. Under the caster's name and set to the caster's left margin, the two
// read as one block -- who is casting, and what they are casting -- which is
// what they are.
#macro BOSS_SPELL_ROW 42                        // one line of `fnt_ui`
#macro BOSS_SPELL_Y (BOSS_NAME_Y + BOSS_SPELL_ROW)

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

/// **How the boss carries itself during one attack**, because the drift is not
/// one size fits all. It is a property of the *attack* rather than of the boss:
/// the same caster wants to wander through a wide non-spell and hold still
/// through a radial spell, and a boss-wide setting could not say that.
///
/// A phase that names none of these drifts, so every attack written before
/// this existed still reads correctly. See `boss_move`.
enum BossMove {
    Drift,      // the default: a wide lissajous wander round its station
    Track,      // trends toward the player's column, loosely, still wandering
    Fixed,      // takes its station and holds it
}

// ---------------------------------------------------------------------------
// Backgrounds that are corridors
//
// **Stage one is a floor and stage two is a corridor**, and the difference is
// the projection rather than the art. See `scripts/bg_corridor` for the whole
// argument; what lives here is the camera it is drawn through and the numbers
// the grove is arranged with.
//
// The camera sits at the origin looking down +z, `CORRIDOR_CAM_H` above a
// ground plane, and everything comes off one quotient: `k = FOCAL / z` is the
// screen pixels one world unit covers at depth z. A prop's position, its
// scale, how fast it crosses the frame and how much air is in front of it are
// all that number.
// ---------------------------------------------------------------------------

// The lens. Bigger is longer -- less spread between near and far, and a
// flatter picture. 900 against a field 1360 wide is about a 75-degree
// horizontal field of view, which is wide enough that a tree passing the
// camera visibly *accelerates* and narrow enough that the far end of the
// corridor is not a dot.
#macro CORRIDOR_FOCAL 900

// How high the camera flies. It is what decides where the ground meets a
// prop's feet, so it is also what decides how much of the picture is floor.
#macro CORRIDOR_CAM_H 250

// The vanishing point, as a share of the view's height. **Low enough to leave
// room for a floor**: the ground is where the sense of speed comes from, and a
// horizon at the middle of the frame gives it half a screen to do that in
// while giving the sky half a screen of nothing.
// **Half way down, not two fifths.** The floor of a corridor is where the
// speed lives, so the first pass gave it three fifths of the frame -- and
// what that produced was a picture that was mostly ground, which is a picture
// of a lake. A forest is read off what is *over* the camera; the room the
// horizon gives back goes to the canopy.
#macro CORRIDOR_HORIZON 0.52

// The near plane a prop is recycled at, the clamp that stops the projection
// dividing by nothing, and the far plane it fades in from.
//
// **Nothing is ever seen at `CORRIDOR_Z_MIN`.** Props are set out well off the
// centre line, so they leave the frame *sideways* -- at the near plane a tree
// three hundred units off the path projects two thousand pixels from the
// middle of a field six hundred and eighty pixels wide. The clamp exists for
// the frame that arithmetic is wrong on, not for one anybody will see.
#macro CORRIDOR_Z_MIN 60
#macro CORRIDOR_Z_NEAR 200
#macro CORRIDOR_Z_CLEAR 900     // no haze at all closer than this
#macro CORRIDOR_Z_FAR 5200

// **How much of the air may still be clear where a ring recycles its props.**
// A prop's alpha is zero at its own ring's far plane, so nothing ever
// *appears* -- but that is only half of arriving unseen. The other half is
// that its colour has to already be the fog's, and `corridor_haze` only
// reaches that at `CORRIDOR_Z_FAR`. The trunks recycled at 2800, where more
// than half the air is still clear, so what faded up was a four-hundred-pixel
// shape in nearly its own colour: reported, twice, as big trees popping in in
// front of smaller ones that were further back. Sorting them correctly did not
// help, because they genuinely were in front -- the fault was that they
// arrived at a distance where a thing that size can be seen at all.
//
// So a ring's far plane is not a free choice: it has to be far enough back
// that the air does the arriving. `test_corridor` measures every ring against
// this rather than trusting the numbers below.
#macro CORRIDOR_ARRIVE_HAZE 0.45

// How many columns of vertices a wave band's strip has, per tile. See
// `corridor_draw_band_wave`: the wave is interpolated between them, so this
// is a smoothness and not a step size, and it costs two vertices a column.
// It used to be a slice count, and slices are what drew a row of one-pixel
// lines across the moon.
#macro CORRIDOR_BAND_COLS 64

#macro BGKIND_PARALLAX 0
#macro BGKIND_CORRIDOR 1

// **How long a stage takes to turn.** A background may have a second half --
// see `bg_set_omen` -- and four and a half seconds is what the grove's blood
// moon needs: a beat of quiet, an eclipse, and a wavefront rolling down the
// corridor toward the player. Short enough to be an event; long enough that
// none of the three is over before the eye has found it.
#macro BG_OMEN_TIME 270

// ---------------------------------------------------------------------------
// The Hollow Grove
//
// **One moon lights this stage and half way through it turns to blood.** Every
// piece of scenery is therefore drawn as luminance and tinted, and every
// colour below comes in a pair -- see `tools/make_grove.py`. Nothing here is
// painted into a sprite.
// ---------------------------------------------------------------------------

// How fast the world comes at you, in world units a frame, before and after.
// **The stage speeds up rather than the danmaku doing**, which is the cheapest
// way a background has of saying the second half is worse: nothing about the
// fight changed and the room is going past half again as fast.
#macro GROVE_SPEED 6
#macro GROVE_SPEED_FAST 9.5

// The moon. It sits on the horizon in the middle of the frame, which is
// exactly where the boss stands and exactly where the danmaku is thickest --
// so its *value* is held well under white and it carries its structure in
// maria and craters instead. A pale disc bright enough to read as a lamp is a
// disc no bullet reads against.
// **How much light there is in this wood on an ordinary night**, before the
// eclipse takes any of it away. One is "everything the palette says", and the
// palette was tuned against a frame with the moon in full -- which came out
// hazier and flatter than the same wood half way through its eclipse, where
// the mist stops glowing and the charms become the brightest things in the
// picture. That frame was the better one, so this is the number that moves the
// default toward it: the mist quietens, the rims come down, the floor goes
// nearer the colour of the air, and the moon -- which is not dimmed by it --
// is left as the one bright thing.
#macro GROVE_NIGHT_LIGHT 0.74

// The shadow that crosses the moon. **Copper rather than black**, because a
// total lunar eclipse turns the moon dark red: the eclipse is not something
// that happens before the blood moon, it is the reason for it.
#macro GROVE_UMBRA_COL make_colour_rgb(44, 9, 7)
#macro GROVE_UMBRA_RAMP 0.75     // the penumbra, as a share of the moon's radius
#macro GROVE_UMBRA_SLICES 72

#macro GROVE_MOON_R 168
#macro GROVE_MOON_RISE 44       // how far its centre sits above the horizon

// The trees, in world units: how tall one is and how far off the path the
// nearest may stand.
//
// **The path half-width is what makes the near plane safe, and it is measured
// from a tree's *edge* rather than from its centre.** At 300 the arithmetic
// looked right and was wrong by exactly one tree half-width: a trunk on the
// path's own edge still had four hundred pixels of itself inside the field
// when the ring recycled it, so the nearest tree in the wood winked out in
// plain sight once a second. A tree is about 215 units wide either side of
// its trunk, and it has to clear the field's half-width *plus* that before
// `CORRIDOR_Z_NEAR` -- which is what `test_corridor` measures rather than
// this comment claiming it.
#macro GROVE_TREE_H 700
#macro GROVE_PATH_HALF 470
#macro GROVE_TREE_OUT 1600
#macro GROVE_TREE_N 40

// The trunks. **Taller than the screen at any distance worth drawing one
// at**, which is what makes them read as something the camera is going past
// rather than something it is looking at.
// **The half-width is measured from the trunk's inner edge, and getting it
// from its centre is what made them walls.** A trunk is about three hundred
// and forty units wide either side of itself; standing the nearest one three
// hundred and sixty units off the path put its inner edge twenty units from
// the centre line, so the two nearest trunks in the wood met in the middle of
// the screen and the picture was a pair of black slabs with a keyhole between
// them. At five hundred and sixty the same trunk frames the field instead of
// filling it.
// **How much a billboard's own size is allowed to vary from its kind's.**
// Six tree frames and eight trunk frames drawn at exactly nominal size read as
// six trees and eight trunks -- which is what "the same sprite pasted over and
// over" means. Height and width vary independently, so a frame is effectively
// never seen twice: the same trunk comes past squat, then tall and narrow.
//
// Bounded rather than free, because the placement rules downstream are built
// on how wide a prop can get. See `GROVE_TRUNK_HALF` and `test_corridor`.
#macro GROVE_VARY_H 0.20
#macro GROVE_VARY_W 0.16
#macro GROVE_VARY_MAX ((1 + GROVE_VARY_H) * (1 + GROVE_VARY_W))

#macro GROVE_TRUNK_H 1500
// **The clearance a trunk's inner *edge* keeps from the centre line**, which
// is not the same thing as where its middle stands once trunks come in eight
// widths. `grove_make_trunk` adds the prop's own half-width to this.
#macro GROVE_TRUNK_HALF 230
#macro GROVE_TRUNK_OUT 1400      // ...and how much further out it may go
// **Far enough back that they arrive out of the fog.** At nineteen hundred a
// trunk was recycled into a place the air was still three quarters clear, so
// even with a fade it had barely a second of distance to arrive across. It is
// also what gives the layer its depth: a trunk should be a dark shape at the
// vanishing point long before it is a wall going past the camera.
// **Out to the corridor's own far plane**, so a trunk emerges from the fog
// rather than fading up in the middle distance. The count goes up with the
// span so the spacing between them is what it was.
#macro GROVE_TRUNK_Z CORRIDOR_Z_FAR
#macro GROVE_TRUNK_N 22

#macro GROVE_IVY_H 190

// **What kind of thing a prop is.** It has to be on the prop rather than
// implied by which loop is drawing it, because every ring is drawn in one
// merged depth-sorted pass -- see `corridor_merge_new`.
#macro GROVE_KIND_TREE 0
#macro GROVE_KIND_TRUNK 1
#macro GROVE_KIND_BUSH 2
#macro GROVE_KIND_BOUGH 3

// The boughs overhead: the tree sprite hung upside down from a point above the
// camera. `GROVE_BOUGH_UP` is how far above, and it is varied per prop or the
// canopy is a ceiling at one height.
// **High and few.** At twelve boughs hanging four hundred units over the
// camera the canopy came down over half the field and the moon was behind a
// thicket -- which is a wood the player is inside rather than one they are
// flying under. The point of the layer is that something passes overhead, and
// eight of them doing it near the top of the frame says that better than
// twelve filling it.
#macro GROVE_BOUGH_H 440
#macro GROVE_BOUGH_UP 950
// **Where a bough may hang, measured from its inner edge -- and it may not
// hang across the moon.** They were spread right across the corridor on the
// reasoning that the place a bough is most wanted is directly ahead, and a
// bough directly ahead and far away hangs straight down the middle of the
// moon: an upside-down tree in front of the one thing everybody looks at,
// which was most of what was reported as a tangle there. Kept to the sides,
// they frame the moon as an arch and sweep up and out of the top corners as
// they come. `GROVE_BOUGH_IN` is what that costs in world units at the far
// end of the ring, which is where a bough is level with the moon, and
// `test_corridor` does the arithmetic rather than this comment.
#macro GROVE_BOUGH_IN 900
#macro GROVE_BOUGH_OUT 1700
#macro GROVE_BOUGH_Z 4200
#macro GROVE_BOUGH_N 14

#macro GROVE_BUSH_H 130
#macro GROVE_BUSH_Z 3400
#macro GROVE_BUSH_N 50

// A charm hangs on about two trees in five. Every one of them is drawn from
// the branch tips `tools/make_grove.py` wrote into `scripts/grove_table`.
// **Bigger than it looks like it should be.** A charm at a seventh of a
// tree's height is arithmetically a reasonable hanging ornament and
// photographs as a two-pixel green spark: the tree it is hanging in is four
// hundred pixels tall at the distance anybody looks at it, and a hex nobody
// can make out is a hex that is not in the picture. It is the one thing in
// this wood that says somebody lives here.
#macro GROVE_CHARM_ODDS 0.55
#macro GROVE_CHARM_H 200
#macro GROVE_CHARM_SWAY 7        // degrees either way

// Where the fog sits, as a share of the view height below the horizon, and how
// far the ground's own banding reaches before the air swallows it.
// The forest floor, laid down the corridor in bands.
//
// **`GROVE_FLOOR_ROW` is a screen height, and everything else about the floor
// follows from it.** A band is textured *affinely* -- one `draw_sprite_part`
// stretched between two screen rows -- where the perspective it is standing in
// wants the texture to compress as one over the depth. Over a band twenty-six
// pixels tall that difference is under a pixel; over one of constant world
// depth, which is a quarter of the screen tall by the time it comes close, the
// near half of the tile is stretched to nearly twice its length and the
// texture visibly swims under the camera.
//
// So the floor is cut into bands of constant *screen* height and each one is
// told which slice of the tile it is showing. It is the same trick every
// pseudo-3D racing game of the period used, for the same reason.
// **The tile is square in the world as well as in the sprite**, which is
// why there is one number here and not two. Six hundred and sixty units of
// forest floor stretched across five hundred and twelve pixels of texture put
// every leaf in it at thirty pixels on screen, and thirty-pixel leaves are not
// litter, they are lily pads -- which is most of why the first version of this
// floor still read as water even with a texture on it.
#macro GROVE_FLOOR_W 270         // world units across one tile
#macro GROVE_FLOOR_Z GROVE_FLOOR_W   // ...and along it. Square, deliberately.
#macro GROVE_FLOOR_ROW 26        // screen pixels per band

// **How the floor survives the distance, and it is a mip map by hand.** A
// band a fixed number of world units across is many pixels wide under the
// camera and a fraction of one near the horizon, so a floor drawn at one
// scale has to be faded out well before the vanishing point -- and what that
// leaves is a hard horizontal line across the field with a textured floor
// below it and nothing above.
//
// The tile is periodic in both axes, so laying it out at twice the world size
// is a legal thing to do and halves how much of it a band has to show. Doing
// that in doubling steps, and cross-fading between two adjacent steps rather
// than switching, is exactly what a mip chain is -- and the cross-fade is the
// part that matters, because a *step* in texture scale across the floor is
// the same visible line the fade was there to remove.
//
// `GROVE_FLOOR_NYQ` is the share of a tile one band may show before the next
// level takes over. Comfortably under a half, because a pattern sampled at
// its own period does not draw finely, it crawls.
#macro GROVE_FLOOR_NYQ 0.34
#macro GROVE_FLOOR_MIPS 4

#macro GROVE_MIST_Y 0.10
#macro GROVE_GROUND_BAND 130     // world units between root ridges

// The blood wavefront. It launches from the moon -- which is at infinity --
// and travels *down the corridor toward the player*, so the red arrives at the
// far trees first and reaches the near ones last. `GROVE_WAVE_FEATHER` is how
// deep the front is and `GROVE_WAVE_FLARE` is how far either side of it a
// hanging charm catches light from it.
#macro GROVE_WAVE_START 0.30     // the share of the omen it launches at
#macro GROVE_WAVE_Z0 6400
#macro GROVE_WAVE_FEATHER 900
#macro GROVE_WAVE_FLARE 700

// How close a tree has to be before its lit edge is drawn *over* the field as
// well as behind it. See `grove_draw_front`: that pass is additive without
// exception, so it cannot hide a bullet at any alpha.
#macro GROVE_NEAR_Z 560

// ---------------------------------------------------------------------------
// The arrival
//
// **A stage used to begin at full speed on its first frame**, which is the
// one moment in it that nobody composed: the rack cuts and the wood is
// already rushing past. So the corridor opens deep in fog and nearly still,
// and the fog lifts as the flight picks up -- which is the turn's own
// movement run once at the beginning and in the other direction, and it costs
// one number on the background and one veil at the end of the back pass.
//
// `GROVE_INTRO_SPD` is not zero, deliberately. A world that is completely
// stopped for half a second reads as a frozen frame -- as the game having
// hung rather than as a flight beginning -- where one that is barely creeping
// reads as coming out of cloud.
// ---------------------------------------------------------------------------
#macro GROVE_INTRO_TIME 170      // frames the fog takes to lift
#macro GROVE_INTRO_SPD 0.12      // the share of full speed the flight opens at

// ---------------------------------------------------------------------------
// The camera
//
// **Nothing was flying the camera, and that is what made the corridor read as
// a slideshow.** A constant speed down a straight line is arithmetically a
// flight and looks like a dolly on rails: there is no cadence in it and
// nothing the eye can attribute to a body. So the flight *swells* -- a slow
// sinusoid on the speed and nothing else -- and the path gets a slow meander
// in both axes, so the wood is not permanently dead ahead and the flight is
// not permanently level.
//
// **It was a wingbeat first, and it was too much of one twice.** The first
// pass surged the speed a fifth either way every second and a quarter and
// pitched the camera on the same beat. The pitch came out first -- see below
// -- and the surge was then reported as "a little bit jarring": a fifth of
// the speed in six-tenths of a second is a *lurch* on anything near the lens,
// which is where a player sees speed at all. What is left is under a tenth
// either way over four seconds, which changes the speed by a quarter of a
// per cent a frame at most where the wingbeat changed it by more than one and
// a half, and `test_corridor` holds that number. A glide, not a stroke.
//
// **The wingbeat used to pitch the camera as well, and that was wrong twice
// over.** It ran at nine pixels a beat, which is what flying looks like and
// was reported as overkill and as a clash with the genre: this horizon is
// also the level a danmaku player reads the field against, so whatever it
// does at a beat's rate, every bullet on screen appears to do with it. And
// the *rate* was the worse half. What a corridor wants overhead is not a
// cadence, it is a slow rise and fall on the same timescale as the meander --
// so the two axes are one movement, and what the camera is doing is drifting
// through a wood rather than flapping through one.
//
// **Both are rotations rather than translations**, because a rotation moves
// everything on screen by the same number of pixels: the moon at infinity,
// the far wood, the near trees and the ground all go together. See
// `corridor_view`, which is where the two numbers land.
//
// Small on purpose. This is the background of a danmaku stage and the player
// is reading bullets across it; a camera with character is worth having and a
// camera that has to be fought is not.
// ---------------------------------------------------------------------------
#macro GROVE_SWELL 240           // frames in one swell of the glide
#macro GROVE_SWELL_SURGE 0.09    // ...and the share of the speed it adds
#macro GROVE_SWAY 12             // how far the path wanders on its own
#macro GROVE_RISE 14             // ...and how far the flight rises and falls
// Two periods, neither a multiple of the other, so the meander never comes
// back to the same place -- the same argument the floor's two band periods
// make one file over.
#macro GROVE_SWAY_P1 1130
#macro GROVE_SWAY_P2 431
// ...and the rise gets two more of its own, longer again and sharing no
// factor with the sway's. Matched periods would have the camera tracing one
// diagonal line for ever, which is a movement with a shape and therefore a
// movement the eye can learn.
#macro GROVE_RISE_P1 1670
#macro GROVE_RISE_P2 709

// ---------------------------------------------------------------------------
// The lean
//
// **The yaw used to be the meander and nothing else, and the meander answers
// to nobody.** Two sinusoids wander the camera left and right on their own
// clock, which gives the flight a body and gives the player no part in it --
// so the one thing on screen that could plausibly be *steering* the camera
// was the one thing it was not reading. It also reads as arbitrary, because
// it is: reported as the stage steering at random and mostly to the right,
// which is exactly what two sinusoids seeded where these are seeded do for
// the first twenty seconds.
//
// So the camera looks where the player is. `GROVE_LEAN` is how far the
// vanishing point swings when they are against a wall, and the sign is the
// rail-shooter one: a player on the left of the field is a camera looking
// left, which puts the vanishing point on the *right* of the screen and the
// player heading toward it. See `corridor_view` for why a yaw moves the moon
// and the nearest trunk by the same number of pixels.
//
// **The meander stays, at a third of what it was.** A danmaku player parks
// in one place for seconds at a time, and a camera that reads only the
// player is a dolly on rails again the moment they hold still -- which is
// the defect the meander was written for. What it no longer has to do is
// carry the whole of the camera's character on its own.
//
// **The follow is filtered, and both halves of the filter earn their keep.**
// The player crosses this field in about four seconds and *dodges* across it
// several times a second, so a camera that read their position directly
// would shake in time with the dodging -- at exactly the moment the player
// is reading bullets, which is the one thing this horizon may never do. The
// lag is what removes the dodge: a flick left and back is a third of a
// second against a time constant of one, and comes out as a pixel or two.
// The cap is what makes it a *guarantee* rather than a tuning -- the same
// argument `BOSS_TRACK_SPD` makes about a boss that tracks, where a
// proportional ease alone is fastest exactly when the player has just moved
// furthest, which is the worst frame to be fast on.
//
// Committing to one side for a second and a half is about half the lean;
// wall to wall is about five seconds. Both are unplayed, like everything
// else here, and both are one number.
// ---------------------------------------------------------------------------
// **It is world units, not screen pixels, and that is what buys parallax.**
// The lean used to be a yaw, which moves the moon, the far wall of wood and
// the nearest trunk by the same number of pixels -- so a camera driven by
// nothing but a yaw is a camera whose scene has no depth in it, and the
// canopy sat at a fixed offset in front of the moon however the player flew.
// It is a lateral *slide* now, so every band and every prop takes
// `corridor_k` of its own depth: the moon does not move, the far wood shifts
// five pixels, the canopy overhead shifts forty and the nearest trunk a
// hundred. See `corridor_view`. The idle meander stays a yaw, because a
// look-around is what it is for.
#macro GROVE_LEAN 30             // world units the camera slides at the wall
#macro GROVE_LEAN_EASE 0.016     // ...the share of the gap it closes a frame
#macro GROVE_LEAN_SPD 0.34       // ...and the most it may slide in one frame

// ---------------------------------------------------------------------------
// The verge
//
// **Undergrowth, and it is answering two complaints with one ring.** The
// first is that the far left and right of the frame went bare in stretches:
// the trees pick a side by coin flip, and a fair coin over forty trees
// produces a run of six on one side about as often as not -- which is one
// edge of the picture empty for two seconds. `grove_side` fixes the runs; the
// verge is what fills the space between the trunks whatever the run does,
// because it is dense, low, and spread from the edge of the path out past
// where the trees stop.
//
// The second is the horizon. A verge prop at the far end of the corridor is
// sixty pixels of ragged silhouette standing exactly on the line where the
// wood meets the ground, and there are enough of them that the line is never
// bare for long.
// ---------------------------------------------------------------------------
#macro GROVE_VERGE_H 320         // world units tall: bracken, not a fern
#macro GROVE_VERGE_IN 300        // ...how close to the path it may grow
#macro GROVE_VERGE_OUT 2400      // ...and how far out it goes
#macro GROVE_VERGE_N 78
#macro GROVE_KIND_VERGE 4

// How far the far wood's foot dips, in screen pixels. See
// `corridor_draw_band_wave`: downward only, because the ground is painted
// over the foot and a slice lifted above the horizon shows sky underneath a
// wood.
#macro GROVE_RIDGE_H 58
#macro GROVE_MIST_WAVE 44

// ---------------------------------------------------------------------------
// The scrub
//
// **Solid, and that is the whole specification.** The first version of this
// layer was the treeline sprite reused at a third of its size -- and that
// sprite is a lace of two-pixel twigs with its alpha ramped away down its own
// height, because it is drawn as a *distance* and its feet are meant to go
// into haze. Laid small over a lit floor the same art is a smear. Reported,
// accurately, as transparent messiness thrown at the problem.
//
// A hedgerow at the foot of a wood is a **mass**: opaque, with a lumpy top and
// no light through it at all.
//
// **A second version drew it as a filled silhouette at run time** -- a row of
// overlapping lobes in one triangle strip, which is solid and needs no art at
// all. It answered the complaint and it was still the wrong answer: a row of
// arcs is a row of arcs, and what a new layer wants is new *art*. `make_scrub`
// is that, and it is a hedge rather than a shape.
//
// Two things about how it is drawn are not decoration:
//
//   * **It dips where the path runs into it, and it does not part.** It did
//     part, wider than the moon is round, on the reasoning that undergrowth
//     across the stage's centrepiece would be losing it -- and what that
//     left was the one stretch of horizon everybody looks at, under the
//     brightest thing in the picture, ruled dead straight. That was the
//     complaint the layer was built to answer. Worse, it was the only place
//     the hedge could be *seen*: everywhere else it is dark on dark, and
//     against the moon it is a silhouette. Reported as "I'm not seeing any
//     hedgerow", which was accurate. A hedge crossing the foot of a moon is
//     the oldest composition there is; `test_corridor` holds the dip short
//     of a parting.
//   * **Its foot dissolves and its crown does not**, which is one alpha ramp
//     in `make_scrub` doing two jobs: a crown against the sky has to be hard
//     or it is fog, and a foot on the litter has to not be, or it is the
//     cardboard-cutout edge `grove_draw_mound` exists to remove.
// ---------------------------------------------------------------------------
//   * **And the one thing it may never do is fall below the line it is
//     covering.** That is a property of the hedge's *thinnest* stretch, not
//     of its average, and it is the sum of four numbers that live in three
//     files: how tall the band is drawn (`GROVE_SCRUB_NEAR`), how much of it
//     stands above the horizon (`GROVE_SCRUB_RISE`), how far the wave and the
//     dip push it back down, and where the art's own crown bottoms out. Every
//     one of those is individually reasonable and nothing was adding them up
//     -- so the mat in `make_scrub` thinned to a sixth of its height between
//     two ellipses, the crown there fell *below* the horizon, and the ruled
//     join the layer exists to hide showed straight through it. Reported as
//     the border peeking out from behind the hedgerow, and with the wave and
//     the dip both zeroed the worst stretch still cleared the line by one
//     pixel -- which is the measurement that says the art was the fault and
//     not the tuning.
//
//     The wave and the dip came down as well, because both were sized as if
//     this band were as tall as the treeline: 26 and 0.22 on a band 116
//     pixels high is forty-four per cent of it spent pushing the crown down,
//     which leaves an art budget no hedge can be drawn inside.
//     `check_scrub_covers_horizon` does the addition against the shipped PNG.
// ---------------------------------------------------------------------------
#macro GROVE_SCRUB_FAR 0.95      // the far row's size against the band's width
#macro GROVE_SCRUB_NEAR 1.45     // ...and the near row's, which is the cover
#macro GROVE_SCRUB_RISE 0.84     // the share of the band standing above the line
#macro GROVE_SCRUB_WAVE 10       // how far its baseline rides up and down
#macro GROVE_SCRUB_DIP 0.08      // how much lower it stands where the path is
#macro GROVE_SCRUB_DIP_W 320     // ...and over how many pixels either side
#macro GROVE_SCRUB_CLEAR 12      // px the thinnest stretch must clear the line

#macro SPELLBG_GROVE 2         // the grove's caster: a ring of bone and ivy

// ---------------------------------------------------------------------------
// Sound
//
// The three global knobs. Everything else about a cue -- its gain, how often
// it may sound, what it outranks -- is a row in `audio_functions`' table,
// because a mix is a set of numbers that only mean anything relative to each
// other and splitting them across two files would mean tuning one against the
// other with a scroll bar in between.
// ---------------------------------------------------------------------------

// **The per-frame voice budget.** Not a performance limit -- GameMaker will
// happily start far more -- but a legibility one: past about five simultaneous
// cues nothing is distinguishable from anything else, and what the player
// hears on the busiest frame in the game should be the five most important
// things rather than an average of twenty. `sfx_step` spends it in priority
// order.
#macro SFX_VOICES 5

// The count at which a coalesced volley is as big as it is allowed to get.
// Thirty-two is about a full ring-stack; past it a pattern is not audibly
// larger, it is just louder, which is the thing the swell exists to avoid.
#macro SFX_SWELL_FULL 32

// One number over everything, so the whole mix can be pulled down without
// re-levelling twenty-four rows. Below 1 deliberately: these cues are drawn to
// their designed peaks in `tools/make_sfx.py` and the headroom is what keeps
// five of them at once from clipping the master bus.
#macro SFX_MASTER 0.72


// ---------------------------------------------------------------------------
// The Archives of Bequeathed Memories: a room, in three dimensions
//
// **Stage one is a floor, stage two is a corridor, and stage three is a
// room.** See `scripts/bg_sanctum` for why that is a third projection rather
// than a third set of art; what lives here is the hall it flies down and the
// camera that flies it.
//
// The camera is a *real* one -- a view matrix and a perspective projection,
// with the GPU's depth buffer doing the sorting. That is what the grove's
// could not be: `corridor_horizon` adds its pitch to the horizon, which is a
// principal-point shift, and a shift keeps the optical axis pointing forward
// however far it travels. This stage opens aimed at the floor, and pointing a
// camera at the floor is a rotation.
// ---------------------------------------------------------------------------

#macro BGKIND_SANCTUM 2

// The hall. A nave 1400 units across under a ceiling at 1250, in bays of 560
// -- which is one three-bay run of `spr_hall_wall`, so a bay of geometry and
// a bay of art are the same thing by construction.
#macro HALL_HALF_W 700
#macro HALL_CEIL_H 1250
#macro HALL_BAY_Z 560
// How many bays are submitted ahead of the camera. At 560 apiece this is
// 6720 units of hall, which is past where the fog has closed completely.
// How many bays are submitted in front of the camera. **It is set by the
// fade, not by taste**: the last bay drawn has to be gone by alpha before it
// can enter the loop, so it must sit at or beyond `HALL_FADE_END` at its
// nearest -- `(HALL_BAYS - 1) * HALL_BAY_Z`, which `test_hall_sky` checks.
//
// It went 13 -> 16 when the fade did, and the reason is worth keeping: the
// fade has to happen somewhere, and wherever it happens is the end of the
// hall. Putting it where the fog already was cost the depth the fog was
// buying -- see `HALL_FADE_START`. Bays are frozen geometry and a dozen
// submits each, so buying the room back is the cheap half of it.
#macro HALL_BAYS 16

// **The pavement, in three courses.** One tile repeated across the nave is a
// grid, and a grid has no middle -- which in a hall with a processional way
// down it is the one thing the floor has to say. So: a sunken runner the
// player flies along, an ornamented border either side of it, and the marble
// field out at the walls where the furniture stands. The two joints between
// them are straight lines converging on the vanishing point, which is a
// perspective cue a field of squares cannot have.
//
// Measured from the centre line outward, and the marble takes whatever is
// left: 264 + 92 leaves 344 of field, which is two tiles of 172 either side.
#macro HALL_RUNNER_HW 264     // the runner's half-width
#macro HALL_FLOOR_STEP 13     // ...and how far it is sunk below the aisles
#macro HALL_BORDER_W 92       // the ornamented course between the two
#macro HALL_THRESH_W 58       // the band laid across the aisles at a bay joint
#macro HALL_AISLE_NX 2        // tiles of marble across one aisle
#macro HALL_AISLE_NZ 3        // ...and along it
#macro HALL_BORDER_NZ 2
#macro HALL_THRESH_NX 3

// The lens. A vertical field of view of 58 degrees against the field's 1.371
// aspect is about 74 horizontal -- the same angle the grove flies, so that
// anything learnt about framing in one stage carries to the other.
#macro HALL_FOV 58
// **Forty, not eight.** Depth precision is spent across the near-to-far
// ratio, so a near plane far closer than anything the camera can actually get
// to throws most of the buffer away on empty space -- and what is left is
// what every coplanar surface in the hall has to be told apart with. Nothing
// in the nave comes within forty units of the lens (the walls are six hundred
// out), so this is free, and it is about five times the precision at the
// distances the shelving is read at.
#macro HALL_ZNEAR 40
#macro HALL_ZFAR 14000

// **The fog is the aerial perspective and it is doing the work the grove's
// haze did**, except that the hardware applies it. Its far end is inside the
// last bay drawn, so the hall ends in air rather than in a visible edge.
#macro HALL_FOG make_colour_rgb(10, 17, 46)
#macro HALL_FOG_START 1100
// **The air goes solid at 7200, not 6400.** The fog and the fade were made to
// end at the same distance, which sounds tidy and is the one arrangement that
// cannot work: fog is what makes the far end *dim* and the fade is what makes
// it *go*, so ending them together means the rows the fog had dimmed were also
// the rows the fade removed. Measured by counting tabards down the nave, the
// hall lost two rows of depth -- reported as six deep before, four after. The
// fog ends further out now and the fade begins where it leaves off.
#macro HALL_FOG_END 7200
// **...and a surface's alpha goes with its colour**, which is the half of
// distance the fog cannot do. Fog recolours a surface toward the air, and that
// hides it only where what is *behind* it is the air too -- at the end of this
// hall it is not, because `hall_draw_far` hangs a lit rotunda at the vanishing
// point and the last few bays project into the middle of it. A bay arriving
// fully fogged arrived as a perfectly air-coloured silhouette cut out of a
// bright building, which is exactly as visible as a black one was. `sh_hall`
// is where this is applied, because a frozen vertex buffer cannot carry how
// far it is from the camera.
//
// **Gone before it can arrive.** One more bay enters the draw loop every time
// the camera crosses a bay line, and the nearest that bay can ever be is
// `(HALL_BAYS - 1)` bays out -- so the fade has to be complete by then or the
// arrival is the thing being hidden. `test_hall_sky` does the arithmetic.
//
// **It begins exactly where the fog ends, and that is the whole of the
// arrangement.** Two earlier versions got this wrong in opposite directions.
// At 4600 the fade began where the air was three quarters thick, so a surface
// was still visibly its own colour while it was going transparent -- which
// reads as the texture dissolving rather than as distance taking it, and was
// reported as the fade being close and noticeable. Moving it to 5200 fixed
// that and cost depth instead: everything past it went, including the rows the
// fog had merely dimmed, and the hall came back two tabbards shallower than it
// had been before any of this.
//
// Beginning at `HALL_FOG_END` is what has both. Up to there the fog does the
// work and every bay is drawn; past there every surface is already flat
// `HALL_FOG`, so what the alpha removes is a shape with no colour left in it
// at all, and the dissolve has nothing to be seen against but the rotunda it
// exists to stop silhouetting on.
#macro HALL_FADE_START 7200
#macro HALL_FADE_END 8400

// The two ends of the reveal.
//
// **Phase A is high and aimed down**, and both halves of that matter. High,
// so the marble and the things standing on it are what fills the frame; aimed
// down far enough that the vanishing point is off the top of the screen, so
// the hall is genuinely hidden rather than merely small. At a 58-degree field
// of view a pitch of -55 puts the top of the frame 26 degrees below level,
// which is a clear margin.
#macro HALL_CAM_HIGH 900
#macro HALL_CAM_FLY 250
#macro HALL_PITCH_A -55
#macro HALL_PITCH_B -2

#macro HALL_SPEED 9.0
// **Phase A flies slower, and that is so it does not look slower.** Speed is
// read off whatever is nearest the lens; from 900 units up there is nothing
// near, so the same number reads as a crawl.
// **The arrival.** The stage used to open at full speed on its first frame,
// in a hall already lit -- which is the one moment in it nobody composed: the
// rack cuts and the room is simply there. So it opens dark and nearly still
// and the lights come up as the flight gathers, which is the grove's own
// `intro` on the same terms and driven by the same one number.
//
// `HALL_INTRO_SPD` is not zero, deliberately, for the reason `GROVE_INTRO_SPD`
// is not: a world that has stopped dead for a second reads as the game having
// hung rather than as a flight beginning.
#macro HALL_INTRO_TIME 165
#macro HALL_INTRO_SPD 0.16
#macro HALL_SPEED_A 5.2
#macro HALL_SWELL 0.055
#macro HALL_SWELL_P 260

// Baked light. A vertex colour multiplies its texture, so these are the whole
// of the lighting model -- everything brighter than the material is the
// emissive pass.
// ---------------------------------------------------------------------------
// The joinery
//
// **The wall is built, not painted.** Reading outward from the nave: a
// pilaster standing proud of everything, the case front set back behind it,
// the recess set back again with the books at the bottom of it, and a cornice
// and plinth projecting past the pilaster at top and bottom. Every one is a
// real plane at a real depth, which is what buys the parallax, the occlusion
// and the light on the shelf edges that a flat quad could not have.
// ---------------------------------------------------------------------------
#macro HALL_PIL_D 46          // how far a pilaster stands out from the case
#macro HALL_PIL_W 80          // ...and how wide it is along the hall
#macro HALL_CASE_D 120
// **How far behind the case front the books actually stand.** They were at
// the *back* of the recess, a hundred and twenty units in, which is not where
// books are: a shelf is deep and the spines sit at the front of it. At that
// depth the boards ran back into darkness and the shelving read as a row of
// empty ledges -- the flat texture it replaced was closer to right.
#macro HALL_BOOK_INSET 22        // how deep a bookcase recess goes
#macro HALL_ALCOVE_D 280      // ...and the alcove, which is deeper on purpose
#macro HALL_PLINTH_H 130
#macro HALL_PLINTH_D 30
#macro HALL_CASE_TOP 1040
#macro HALL_CORN_D 46
#macro HALL_SHELVES 6
// The rhythm of the hall: an alcove every fourth bay, at the third of them.
// See `hall_bay_kind` for why this is a stratum and not a hash.
#macro HALL_ALCOVE_EVERY 4
#macro HALL_ALCOVE_AT 2
#macro HALL_BOARD_T 6
// **A shelf board is stone, not gold.** The flat bay tile it replaced drew
// its boards as an ordinary moulding -- a warm grey lit edge over a dark
// underside -- and gilded only the cornice and the plinth. The 3D version
// made every board a bright gilt bar, six a bay, twelve a side, and that one
// substitution is most of why the joinery went from refined to blocky: gold
// stopped being a line somewhere and became the thing the wall is made of.
#macro HALL_BOARD_COL make_colour_rgb(92, 86, 76)
#macro HALL_GILT make_colour_rgb(104, 80, 32)
// **A tint only means anything over a pale albedo.** See `pale_tile` in
// `tools/make_sanctum.py`: a vertex colour multiplies its texture, so these
// are all drawn on `spr_hall_pale` rather than on the stone.
#macro HALL_CAT make_colour_rgb(46, 46, 60)     // the statues: black basalt
#macro HALL_MASONRY make_colour_rgb(27, 28, 36)
#macro HALL_GLASS make_colour_rgb(72, 78, 104)
#macro HALL_ORB_COL make_colour_rgb(120, 186, 255)
#macro HALL_LAMP_GLOW 0.40

// Where the furniture sits, in world units.
#macro HALL_STATUE_BASE 132     // the height of a statue's plinth
#macro HALL_DESK_TOP 150

// The orb in the alcove: a real object at a real position, and the thing the
// stone around it is actually lit by.
// How far a moulding stands out from the face it is on. Any non-zero value
// breaks the depth tie; this is also simply what a fillet does.
#macro HALL_FILLET_D 4
#macro HALL_ORB_BODY make_colour_rgb(34, 48, 86)

#macro HALL_ORB_R 48
#macro HALL_ORB_Y 470
#macro HALL_ORB_GLOW 0.95
#macro HALL_ORB_POWER 1.55
#macro HALL_ORB_LIGHT_R 420
// **How far into the recess the orb stands, and it is one number because it
// has to be.** The geometry read it one way and `hall_wall_light` read it
// another -- 763 against 949 -- so the pool of light on the stone was a
// hundred and eighty units deeper into the alcove than the thing casting it.
// Nothing about that is visible as an error: both are perfectly good numbers
// and what it draws is a lit patch with nothing in it beside an unlit lamp.
// `hall_orb_x` is the one answer now and `test_hall_orb` holds the two to it.
#macro HALL_ORB_STAND 84
#macro HALL_ORB_STEM_H 262    // the pedestal, from the alcove sill upward
#macro HALL_ORB_CRADLE 28     // ...and the gilt cup it sits in
#macro HALL_ORB_BLOOM 5.2     // the bloom card's radius, in orb radii

// Baked light. `AMB` is what a surface gets with nothing near it, and the two
// powers are how much each source adds at its own centre.
#macro HALL_WALL_AMB 0.46
#macro HALL_LAMP_Y 360
#macro HALL_LAMP_POWER 0.62
#macro HALL_LIGHT_R 680

#macro HALL_WALL_LIGHT 1.00
#macro HALL_FLOOR_LIGHT 0.86
// **The pavement is lit by both walls at once**, which is why it has a light
// model of its own rather than the joinery's: a wall quad faces one way and
// answers to the lamps on its own side, and a floor quad in the middle of the
// nave is between two of them. `HALL_FLOOR_AMB` is what a point equidistant
// from everything falls to, and the bounce is how much of a lamp reaches the
// stone under it -- the two together are what keep the centre of the field,
// where the player lives, the darkest part of the picture.
#macro HALL_FLOOR_AMB 0.26
#macro HALL_FLOOR_BOUNCE 0.74
// **...and then a vignette over the top of it, which is a fairness rule and
// not physics.** `HALL_LIGHT_R` is 680 against a nave 1400 wide, so both
// walls' lamps reach everywhere and the honest falloff alone comes out flat:
// measured, the middle of the nave and the stone at the wall were within one
// and a half per cent of each other, which is a floor with no shape in it and
// -- worse -- a *bright* floor exactly where the player lives and the danmaku
// is thickest. This is the share of the light the centre line keeps.
#macro HALL_FLOOR_DIM 0.42
// Where the lamps sit up the wall, as a share of its height from the cornice
// down. It is where `tools/make_sanctum.py` draws them, and the falloff in
// `hall_build_wall` is measured from it.
#macro HALL_LAMP_V 0.46

// The steering, on the grove's terms: an ease to take the dodging out and a
// cap to make the limit a guarantee rather than a tuning.
#macro HALL_LEAN 92
#macro HALL_LEAN_EASE 0.022
#macro HALL_LEAN_SPD 1.7

// What stands in it, in world units.
#macro HALL_STATUE_X 548
#macro HALL_STATUE_H 430
// **Out on the statue line, not adrift in the nave.** At 430 the pedestals
// stood in open floor with nothing behind them and nothing beside them, which
// is what read as floating: a thing against a wall is furnished, a thing in
// the middle of a room is dropped. They share the statues' setback now and
// fall at the midpoint between two of them.
#macro HALL_DESK_X 548
#macro HALL_DESK_H 165
// **A banner is placed by its centre and is two hundred units wide**, so
// how far out it may hang is bounded by the cornice face it would otherwise
// go through rather than by the wall. Moved out to 628 to hang it off the
// new wall head, it put its outer third inside the cornice and the pilaster
// -- reported, accurately, as the tabards suddenly clipping into the walls.
// `test_hall_sky` does the addition now, because the number that has to hold
// is a sum of three that live in three different places.
#macro HALL_BANNER_X 540
#macro HALL_BANNER_H 620
// It hangs from the wall head rather than from the ceiling that used to be
// there: its top is just under the coping's soffit.
#macro HALL_BANNER_DROP 6
#macro HALL_LAMP_X 606
#macro HALL_LAMP_H 340

// **How hard the emissive pass is driven.** The lamps are drawn additively
// over an almost black hall, so at full white a bay's two orbs were the
// brightest thing on the screen by a wide margin -- brighter than the
// bullets, which is the one thing no piece of scenery may ever be.
#macro HALL_EMISSIVE_K 0.50
// How much light a prop's own surface carries. Props stand out in the nave
// rather than against the shelving, so they take a flat value rather than the
// wall's falloff from the lamp height.
#macro HALL_PROP_LIGHT 0.88
// **Below this, a texel is not there at all.** Cut-out sprites on quads have
// transparent corners, and with depth writing on those corners would punch a
// rectangular hole in whatever is behind them.
#macro HALL_ALPHA_REF 96
#macro HALL_LAMP_EMISSIVE make_colour_rgb(96, 96, 96)

// ---------------------------------------------------------------------------
// The open roof
//
// **The hall has no ceiling, and that is what stopped it reading as a
// corridor.** It was capped at `HALL_CEIL_H` by a coffered plane with a
// starfield painted on its underside -- a picture of a sky on a lid, and a
// lid is precisely what a tunnel has. Floor, two walls and a ceiling is four
// edges and no way out: every ray the camera casts lands on something a
// couple of bays away, so however deep the shelving is modelled the room can
// never be bigger than its own cross-section.
//
// Taking the lid off costs one thing and buys two. It costs the enclosure the
// original note argued for -- and that argument was right about libraries and
// wrong about *this* library, which is a death-god's archive and is open to
// the sky. It buys somewhere for the distance to be, which is where the
// orrery hangs; and it buys a silhouette, because the wall tops now end
// against something.
//
// **What the sky is allowed to be is a wedge, and the wedge is a rule.** The
// visible sky is bounded by the two wall tops, and a long horizontal edge at
// height H and half-width X projects to a straight ray out of the vanishing
// point with slope (H - camera) / X. Anything built above the wall narrows
// that wedge for the whole length of the hall, so the parapet's height is not
// a free choice -- it is the price of the sky, paid once and paid everywhere.
// `test_hall_sky` does the arithmetic against the orrery's own screen radius,
// because the failure it guards against is "the landmark this stage was
// opened up for is behind the masonry", which no assertion about either piece
// on its own could ever see.
// ---------------------------------------------------------------------------

// The coping: the slab that caps the wall, oversailing it on the nave side.
#macro HALL_COPING_H 26
#macro HALL_COPING_OUT 46        // how far past the pilaster it stands

// The parapet standing on the coping. `X` is its *inner* face, which is the
// edge that silhouettes, and it is what the wedge is measured from.
#macro HALL_PARAPET_X 672
#macro HALL_PARAPET_H 72

// An obelisk on every ordinary bay, over the pilaster that carries it.
//
// **Thin, on purpose.** A continuous upper storey would be a second wall and
// would close the wedge along the whole hall; a post closes it only at its
// own bay. What the eye gets instead is a rhythm of dark verticals marching
// away against the stars, which says the building goes up much further than
// the frame does without spending any of the sky to say it.
#macro HALL_OBELISK_H 430
#macro HALL_OBELISK_W 32
#macro HALL_OBELISK_CAP 78       // the gilt pyramidion, which is the lit bit

// ...and a brazier on the alcove bays instead, so the upper level has a light
// of its own and the rhythm is a rhythm rather than a repeat.
#macro HALL_BRAZIER_H 104
#macro HALL_BRAZIER_R 62
#macro HALL_BRAZIER_COL make_colour_rgb(255, 176, 92)
#macro HALL_BRAZIER_GLOW 0.85

// ---------------------------------------------------------------------------
// The sky
//
// **A dome centred on the camera, drawn first, with the depth test off.**
// That is the whole of a skybox, and it is the only construction that gets
// both halves right at once: it turns with the pitch and the lean exactly as
// the world does, and it does not translate at all -- which is what "at
// infinity" means and what no amount of parallax tuning on a flat backdrop
// can imitate.
//
// The radius is arbitrary and has to be *inside the frustum anyway*, because
// the near and far planes clip whether or not the depth test is on.
// ---------------------------------------------------------------------------
#macro HALL_SKY_R 6000
#macro HALL_SKY_COLS 40
#macro HALL_SKY_ROWS 13
// The dome runs well below the horizon, so that no pitch the reveal passes
// through can put an unpainted band under it. Everything down there is
// covered by the floor in play; this is the guarantee rather than the
// expectation.
#macro HALL_SKY_EL0 -40
// **The sky is saturated and the fog is not, and that is the whole of the
// difference between night and haze.** The first version derived every band
// of it from `HALL_FOG` by multiplication -- which keeps the join at the
// horizon exact, and which is also why it came back as a grey void with
// something caught in it. A multiply cannot add chroma, so a desaturated fog
// makes a desaturated sky however it is scaled, and the one thing this stage
// had to gain by losing its ceiling was somewhere that reads as *outside*.
//
// It is the grove's own correction one layer out: value and saturation are
// different budgets. A deep blue at the same value as a neutral grey costs
// the danmaku exactly nothing and is the difference between a night sky and
// a photocopy of one. So the value here stays where it was and the chroma
// goes up by a factor of three.
//
// The join is kept by construction rather than by matching: elevation zero
// *is* the fog colour, and the blue ramps in above it. What that draws is a
// horizon glow, which is what the bottom of a real sky has anyway.
#macro HALL_SKY_LOW make_colour_rgb(20, 44, 104)
#macro HALL_SKY_HIGH make_colour_rgb(7, 12, 46)
// **Where the ramp happens is set by what the camera can see.** The whole
// visible sky is between about ten and twenty-eight degrees of elevation, so
// a gradient spread over the full ninety puts every one of its stops out of
// frame and what is left in frame is one flat colour.
#macro HALL_SKY_LOW_EL 13
#macro HALL_SKY_HIGH_EL 52

// The stars. Three magnitudes, and the count is most of what makes a sky read
// as a sky rather than as a handful of dots.
//
// **Nine thousand of them, for about a hundred on screen.** The dome is a
// whole hemisphere and the wedge between the two parapets is a narrow
// triangle at the top of the frame, so ninety-eight per cent of any star
// count is spent out of shot -- measured, not guessed: at two thousand six
// hundred the frame held thirty-nine stars and read as an empty sky with
// something wrong with it. Generating them only where the camera looks would
// be cheaper and would be a dome that is a lie the moment anything ever
// tilts, so the count is what moves instead. Nine thousand cards is one
// frozen buffer and one draw.
#macro HALL_STARS 9000
// **Extinction, and it is load-bearing rather than decorative.** A star at
// the horizon is seen through the same haze the far end of the hall is, so it
// has to fade out before it reaches the wall tops -- otherwise the fog closes
// on the architecture and the stars behind it do not, and the seam between
// the two is the exact line the fog exists to hide.
#macro HALL_STAR_EL0 1
#macro HALL_STAR_EL1 11
#macro HALL_STAR_SIZE 40         // a middling star's half-size at HALL_SKY_R
// **The band the extinction is measured over is the band that is *seen*.**
// The camera never looks up: at the reveal's own pitch the top of the frame
// is twenty-seven degrees above the horizon and the wall tops cut off
// everything under about ten, so the whole of the visible sky is one narrow
// strip low down. The first ramp faded the stars in between two and thirty
// degrees, which is a perfectly sensible atmosphere over a sky nobody in this
// stage can see: every star actually in frame was at a third of its
// brightness, and what came back was an empty grey wedge.
//
// A band of denser, fainter stars across the sky: the one arrangement that
// separates a designed starfield from a uniform sprinkle.
#macro HALL_STAR_BAND 0.44       // what share of them fall in it
#macro HALL_STAR_BAND_TILT 34
#macro HALL_STAR_BAND_W 13       // its half-width, in degrees

// **How far either side of dead ahead the composed sky is spread.** The
// stars are over the whole dome, because there are enough of them that the
// wedge gets its share wherever they fall. The nebulae and the constellations
// are not: there are a handful of each, the wedge is a narrow V, and a
// uniform azimuth put one segment of one figure on the screen. Wider than the
// lens, so nothing is arranged in a fan the eye could read as one.
#macro HALL_SKY_SPREAD 64

#macro HALL_NEB_N 16
#macro HALL_NEB_A 0.42
#macro HALL_NEB_R0 62            // a patch's half-angle, in degrees
#macro HALL_NEB_R1 26            // ...and how much less it can be

// The constellations: a handful of the bright stars, joined.
#macro HALL_CONST_N 22
#macro HALL_CONST_A 0.22

// ---------------------------------------------------------------------------
// The chamber at the end of the hall
//
// **The sky needed a floor.** With the roof off, the hall's perspective ran
// out at the vanishing point and everything past it was stars -- so the nave
// read as a corridor trailing off into space rather than as a room open to
// the night. What was missing is what every real view of a horizon has:
// something the ground *becomes*.
//
// It is one painted quad at a fixed depth. A second room in three dimensions
// at the end of an endless hall is a room the flight would have to either
// reach or visibly never reach, and both are worse than a backdrop -- which
// is what `bg_grove`'s moon is and what this is.
//
// The half-width in *screen* pixels is shared with `HALL_ROT_HW_SCREEN` in
// `tools/make_sanctum.py`, because the painting's own perspective is computed
// from how far above the eye each gallery sits in the finished frame.
// `test_hall_sky` checks the two agree.
// ---------------------------------------------------------------------------
#macro HALL_ROT_Z 12500
#macro HALL_ROT_HW 5600
// **Wide and short, because that is the shape of the hole it fills.** The
// band available for it is the vanishing point up to the orrery's skirt --
// 260 pixels of a 992-pixel field. Hung over the whole wedge instead, its
// galleries swept up past the orrery and read as pale arcs across the sky
// rather than as a building under one.
#macro HALL_ROT_HH 1830
// Its foot, in world y. Two hundred units under the hall's own floor, so the
// thin band between where the marble runs out and the horizon is covered
// rather than showing a seam -- the card's bottom dissolves there anyway.
#macro HALL_ROT_Y0 -200
#macro HALL_ROT_COL make_colour_rgb(124, 152, 232)
// Under one on purpose: what shows through is the sky behind it, which is
// aerial perspective done the cheapest possible way and the reason it sits
// *in* the air rather than on top of it.
#macro HALL_ROT_A 0.88
#macro HALL_ROT_LIT make_colour_rgb(255, 206, 132)
#macro HALL_ROT_LIT_A 0.82

// ---------------------------------------------------------------------------
// The grand orrery
//
// **It is this stage's moon**, in the sense `bg_grove` means one: a fixed
// direction rather than a place. It is anchored to the camera's own depth, so
// it never arrives however long the flight lasts -- which is a lie the player
// cannot catch, because at nine thousand units nothing about it would change
// over the five minutes a stage runs even if it were real.
//
// **Where it sits is derived from the wedge rather than chosen.** Its centre
// has to clear the parapet's silhouette by its own screen radius or the
// masonry eats its flanks, and at this field's focal length that is what
// fixes the height. See `test_hall_sky`.
// ---------------------------------------------------------------------------
#macro HALL_ORRERY_Z 9000
#macro HALL_ORRERY_Y 2820
#macro HALL_ORRERY_R 1120
// **Drawn with the fog off and dimmed by hand instead.** Hardware fog at nine
// thousand units is total -- the far end of the haze is at 6400 -- so a
// fogged orrery is a rectangle of fog colour. What distance actually does to
// a bright thing is take its contrast away, which is a multiply, and this is
// it.
#macro HALL_ORRERY_DIM 0.80
#macro HALL_ORRERY_GILT make_colour_rgb(226, 184, 100)
#macro HALL_ORRERY_CORE make_colour_rgb(150, 205, 255)
#macro HALL_ORRERY_HALO_R 2900
#macro HALL_ORRERY_HALO_A 0.16
// How long the core takes to breathe once, in frames.
#macro HALL_ORRERY_PULSE 310

#macro HALL_DUST_N 46
#macro HALL_DUST_COL make_colour_rgb(150, 190, 255)
