# Bullet Hell

A Touhou-inspired danmaku shooter in GameMaker Studio 2 (IDE 2024.14). You play
Szuix, a blue imp who is tired of being everybody's trash mob, flying through
other people's territory and taking their magic off them. Arrow keys move, Z
shoots, X spends a sigil, shift focuses and shows the hitbox, escape pauses.

**The progression is Cuphead's, not Touhou's.** There is no run that starts at
stage one; every stage is played in isolation, a clear is permanent, and more
stages open as clears accumulate. So a stage is five to ten minutes of the same
shape as a Touhou Extra: waves, a midboss, more waves, and a boss with a table
of named attacks. Nothing is lost by failing one.

Grown out of the tooling and the working discipline of the `Wordsearch` project
in the same folder, which is referenced throughout because most of what is
written down here was learned there first.

## Working in this repo

**There is a compiler, and it is fast.** The installed runtime ships
`Igor.exe`, it matches the IDE version in the `.yyp`, and a cached build takes a
couple of seconds. Four tools sit on top of it:

```bash
python tools/build.py && python tools/test.py && python tools/check_project.py
```

| Tool | What it proves |
|---|---|
| `tools/build.py` | The GML compiles. Reports real diagnostics with line numbers. |
| `tools/test.py` | The GML is *correct*: builds, runs with `-selftest`, grades the suites in `scripts/selftest` off stdout. |
| `tools/check_project.py` | The project files are sound: `.yy` JSON, event lists matching `.gml` on disk, resources registered, every SHOUTING_IDENTIFIER a `#macro` that exists, no call with the wrong argument count, no legacy built-in globals, no sprite too big for its texture page, **every background layer tiling seamlessly**, the near layer keeping out of the field, and no bare `draw_sprite` inheriting the draw state. |
| `tools/shot.py` | What it **looks like**: builds, runs with `-shot <scene>`, poses a real game state, saves a screenshot. Nineteen scenes; `--all` does the lot. |

**`shot.py` is not a nicety, and in this genre it is the most important of the
four.** A bullet pattern that is arithmetically perfect and illegible is a bug,
and no assertion can see it. It renders nineteen scenes and **fails on a game
error even when a screenshot appeared** — `obj_shot` calls `screen_save` from
its Step event and `game_end()` lets the current frame finish, so a throw in the
Draw event that follows happens *after* the file is on disk. The first crash
this project shipped did exactly that, and an early version of the harness
reported fifteen successes over it.

Everything below was found by looking at a screenshot and by nothing else:

- The two HUD meters' labels were drawn *above* their bars, so `SIGIL` was
  printed across the middle of the life meter. `test_hud_layout` checked that
  the two bars did not overlap and passed happily — a label thirty pixels above
  a bar is not part of that bar as far as any assertion can tell.
- Two of the three parallax layers had a hard horizontal seam sweeping up the
  screen, because they were *shaded* at one tile's height and the distance
  field treated the canvas edge as the edge of the rock.
- The molten cracks in the third layer arrived at the bottom of the tile
  several hundred pixels from where they left the top.
- Szuix is a dark blue sprite and the first stage is a dark cave. He very
  nearly disappeared into it.
- The spell background flooded the screen with the spell's own colour, so
  `Cinder Waltz` was gold bullets on a gold field. It works by **subtraction**
  now — the wash is dark and the field is the only lit thing left — which is
  the rule the spirit in Wordsearch is built on and the one this had ignored.
- The eye card was drawn full size and centred, covering eight hundred pixels
  of playfield with a face while the spell it was announcing had already
  started firing.

## The screen

**The field is a bounded rectangle, the readouts live in one console beside
it, and the boss's health is a thin line inside it.** This has been reversed
twice, so it is worth having every half of the argument written down.

It started full-bleed. The classic 384x448 playfield inside a 640x480 window
exists because the rest of the window is where the score, the lives and the
spell counter go — so this game gave the danmaku all 1920x1080, put the
readouts in the four corners, and faded each one as the player approached it.

It did not work, and it could not have. The bug was real and was fixable: the
fade measured distance from an element's *top-left corner*, so a meter 430
pixels wide faded when the player stood at its left end and did nothing at all
when they stood on its right. The design was not fixable. A readout has to be
big enough to read at a glance from a metre away; anything that big can hide
bullets; and fading it makes it unreadable at exactly the moment it is most
needed — you check your life when you are deepest in a pattern, which is when
the fade has it at its floor. Every attempt at the legibility made the
occlusion worse and every attempt at the occlusion made the legibility worse,
because they are the same pixels.

So the field got a boundary and the readouts got margins. **The second pass
gave them two margins, and one of them did not earn its keep**: a 168-pixel
strip above the field carrying the boss's name at 66pt and a health tube
spanning the whole width. That is a sixth of the display spent on two facts,
and it was empty for the two or three minutes of every stage before the boss
arrives — sitting next to a right-hand column with a pair of narrow upright
vials at its foot and three hundred pixels of nothing above them. Reported, in
those words, as "a ton of unnecessary vertical space at the top, paired with a
lot of unused space to the right".

The strip is gone. Both of its tenants moved and neither is worse off:

- **The health tube is inside the field**, which is where the genre has always
  drawn one, because a boss's health is a fact about the thing you are shooting
  and belongs beside it.
- **The name is centred over the tube and small**, tracked rather than large —
  see the note on tracking below. It used to be left-aligned specifically
  because a boss holds station in the middle of the top of the field and a
  centred caption would be printed across its face. That is a real problem, and
  the fix is to move the *boss*: `BOSS_HOME_Y` now stations it clear of its own
  line, and the fight sits at very nearly the screen position it always did
  because the field grew downward past it.

So: `FIELD_X0`, `FIELD_Y0`, `FIELD_W`, `FIELD_H` — **1360x992 at (44, 44)**,
with the same 44-pixel margin on three sides — and one console down the fourth.

### The console

`HUD_PANEL_*` is a plate the height of the field, and it holds, top to bottom:

| | |
|---|---|
| the stage | its name and subtitle |
| the numbers | the stage's best, this attempt's score, the graze count |
| the meters | life and sigil, as horizontal vessels |
| the ledger | a mark per encounter, the standing so far, and the last few named |

**Every section has a tenant that is never absent, and getting that right took
three goes.** The attack marks and the spell nameplate are both facts about a
boss, so the first layout gave each its own band of plate — and produced *two*
bands standing empty for most of a stage. Spacing them more evenly moved the
holes without closing them. Merging them into one conditional section that
escalates — a spell's name, else the boss's title, else something — closed the
hole and left the question of what that "else" should be.

The first answer was a control legend, and it was wrong for a third of the
console: a legend is read once on the way in, this game has five keys, and by a
player's second run it is furniture they have stopped seeing. What is there now
is the ledger, below.

`test_hud_layout` asserts that no section of the console is more than three
times another, which is the shape a hole has when it is measured rather than
looked at.

**The meters are in the middle, and they used to be at the foot.** The original
argument was that a danmaku player lives in the bottom half of the field, so a
life bar level with the character is one the eye reaches without leaving the
pattern. That is real, and it lost to a simpler one: a column is read top to
bottom, so the order down it should be the order of *importance*, and life
outranks a list of grades. What is given up is about 350 pixels of eye travel,
which is worth less than having to hunt for the life bar under a ledger.

**The plate stands to the field's outer rule, not to the field.** Flush with
`FIELD_Y0` its top edge sat seventeen pixels below the ornamented rule that
frames the picture beside it, and two panels on one fascia that disagree about
where the top of the fascia is read as one of them having slipped — reported as
"the right side UI area is slightly unaligned, too low next to the game
screen". `HUD_PANEL_Y0` is `FIELD_Y0 - FIELD_RULE_OUT` now, so both outer edges
are the same line and the two panels bracket the display together.

**Every readout is one row and they all go through `hud_row`.** A tag on the
left, a value on the right, both on a shared centre line. The score used to
draw its own tag at `y` and its numerals at `y + 34`, which put the one number
the eye goes to on a second line below and to the right of its own label — out
of line with `BEST` and `GRAZE` either side of it, and spending a whole row of
plate to say what the other rows say in one. **The shared centre is the part
that matters**: a tag at 26pt and a value at 56pt drawn from the same *top*
edge are not on the same line at all, because the small one floats at the top
of the big one's cell. `fa_middle` is also the only alignment that survives a
font change.

**And collapsing a row means closing the gap it left.** The first pass of that
change kept the old spacing, so the console gained a visible gap between every
line — a tidy-up that made the thing it tidied look worse. Rows that share a
shape share a pitch: `BEST`, `SCORE` and `GRAZE` are one pitch apart, the two
meters are one pitch apart, and the height that was reclaimed went to the
ledger rather than being left between things. `test_hud_layout` asserts the
three number rows are evenly pitched, because "there is a gap here" is not
something a check for *order* can ever see.

**Tracking is what makes a four-letter tag read as a label.** `SCORE` set solid
at 26px beside a number at 56px is a small word next to a big one; opened out to
twice its width it is a *caption* — it stops competing with the value and starts
introducing it. `draw_text_tracked` draws a glyph at a time, because a sprite
font has no tracking, and that is fine for the five- and six-character tags it
is used on.

### Marks: a grade per encounter

**A stage is a series of encounters and each one is graded.** That is
Bayonetta's shape rather than Touhou's — Touhou scores a run as one number and
hands out a spell-capture bonus, where the character-action games break a level
into set pieces and put a medal on each.

It fits this game better than the genre's own convention does, and the reason
is the progression: **this is Cuphead's structure, not Touhou's.** A stage is
played in isolation and replayed until it is clean, so what the player wants
back from an attempt is *where it went wrong*, and one number at the end cannot
say that. A row of marks can, and it can say it while there is still time to
do something about it.

**The block is the row of marks and nothing else.** An itemised list of the
last few, named and graded, lived under the row for one pass and was never
asked for: it went in to fill the space the spell nameplate left when that
moved to the boss's line, which is a reason to re-space a layout and not a
reason to invent a readout. A ledger of what each encounter scored belongs on
the result screen, where there is a whole page for it and the player has
stopped dodging; `rank_note` records the label for exactly that.

The ladder is `SLAG · IRON · SILVER · GOLD · ADAMANT` — metals rather than
Bayonetta's stones, with slag under the familiar three because that is what is
left when you smelt badly, and adamant over them because it is the one metal
that is not. The standing is the **floored** mean of the marks earned, and the
floor is the whole difficulty rule: rounding to nearest lets one good encounter
pay for one bad one, which makes the grade a measure of the average attempt
where it should be a measure of the consistent one.

**What is built is the ledger and the readout, not the scoring.** The boss's
attacks are graded for real, because everything a grade needs about them already
exists — whether the attack was beaten or timed out, how many times the player
was hit during it, how many sigils they spent, and how much of its clock was
left — so grading is a *read* rather than new bookkeeping. The stage's own waves
are not: a wave is currently a line in a `{at, fn}` timeline and not a thing
with a beginning, an end or an outcome, and giving it those is a change to
`stage_functions`. `rank_note` is the seam that change will call, and
`stage_def.encounters` is the provisional count standing in for it.

**The sockets are drawn before they are earned**, which is most of why the block
never reads as empty. A stage opens showing fourteen hollows: how long this is
going to be, how much of it is left, and that there is something here to fill
in. Between encounters the foot of the block carries the last mark and what
earned it — a grade filed and never mentioned again until the result screen is
a grade nobody can learn from.

### The boss's line

`BOSS_BAR_Y` is inside the field, and it is the one deliberate exception to the
rule the boundary was built to keep. What makes it affordable is that the whole
thing is a *line*: its occlusion budget is its height, not its alpha, and
fourteen pixels of a 992-pixel field is one and a half per cent — a bullet
crossing it is hidden for a single frame at the slowest speed this game fires
at. The name, the timer and the notches are outlined text and hairlines either
side of it, which is what the genre does and what `draw_text_outline` is for.

`FIELD_OVERLAY_MAX_H` is the number that stops the exception growing quietly
back into a strip, and `test_hud_layout` asserts the height rather than
asserting the box is clear of the field — because the box is not clear of the
field and is not meant to be. Everything else the HUD draws still goes through
`rect_clear_of_field`, and `hud_console_boxes` is the list.

**The spell's name goes under the bar, and that reverses a decision twice
made.** It started at the bottom of the field, which on a full-bleed playfield
is inside the player's working area — the one permanent piece of text in the
game competing for the pixels being read hardest. It moved to the console on
the reasoning that forty seconds of nameplate over the play area is not
affordable where two and a half seconds of banner is. In the console it was the
width of the column away from the health bar it refers to, three lines tall,
and it clipped off the bottom of the plate the moment a title ran long.

Two things changed to make the bar the right home. **The names are single now**
— "Cinder Waltz" rather than "Ember Sign — Cinder Waltz". The two-part form is
Touhou's signature and borrowing it that exactly is closer to copying than to
being inspired by, and it cost three lines of plate to say what one says. And
the top of the field is where the boss is and the player is not, which is the
same exception the bar itself is, on the same terms: outlined text, one line,
nothing opaque. Whether the capture is still live goes at the *end* of the bar
rather than beside the name, so that losing it does not shift the name — which
would read as the spell having changed.

**The marks for the remaining attacks are in the console, not beside the bar.**
Touhou draws its stars in the playfield; the first pass of this line copied
that, and what it produced was a row of small coloured shapes over live scenery
a few pixels above a bar that already carries the same information as notches.
Two readouts of one fact, one of them occluding, when the console has a whole
row for them and the room to draw them at a size that reads.

### The frame, and the fascia behind it

**The boundary is drawn as a mask, in the GUI event.** `field_draw_frame`
paints the four margins opaque and draws the rules and the spill of light round
the field. Four rectangles rather than a scissor or a surface: no state to
restore, nothing to lose on a resize, and no chance of a later draw call
escaping the clip. It is in the GUI event rather than in Draw because Draw
carries the screen shake as a world matrix, and a mask that shook would let
scenery leak into the margin along one edge on every hit.

**The margin is a surface, not an absence.** It was painted flat `COL_VOID` for
as long as the field had a boundary, and photographed at 1:1 that is what came
back — a lit picture pasted onto a sheet of nothing, which is the same finding
`make_bg.py` records about the first version of the stage arriving one layer
further out. What is drawn instead is a plate lit from above: one vertical ramp
sampled from the *screen's* height so the four pieces of margin agree with each
other, plus a tile of glint over it and a few motes drifting up through it.

The frame itself is an outer rule with an ornamented corner standing on it.
Where that rule runs is *derived* rather than chosen — `FIELD_RULE_OUT` is
`FIELD_ORN_OUT` less the corner sprite's own inset — because a rule that misses
the corner pieces by two pixels reads as a mistake in a way that a rule ten
pixels further out would not.

**And the corner piece is 37 pixels deep at its elbow, not a thin line along an
edge.** Pushed only sixteen pixels out it had its set stone seven pixels
*inside* the playfield. Seven pixels of near-black in the extreme corner is not
going to cost anybody a life, and that is not the standard: nothing decorative
is drawn over the field, and the rule is worth keeping absolute precisely
because every individual exception to it sounds this reasonable.
`UI_CORNER_DEPTH` mirrors the generator and `test_hud_layout` does the
arithmetic.

**Anything drawn in the GUI event after the mask has to be clamped.** That is
one line in `fx_draw_text` and it is the only leak the boundary has: floating
text carries world positions but is drawn on the GUI layer, so a "+250" off a
kill near the edge would drift up past the console.

**A wave is authored in field coordinates.** `wave_line` and `wave_cross` add
`FIELD_X0` / `FIELD_Y0` themselves, so a stage says "140 pixels down from the
top of the play area" and `stage_ziggy` has now survived the field becoming a
rectangle *and* the rectangle changing size without a single number in it
changing.

**Every modal is centred on the field, not on the screen.** The pause menu and
the result panel still scrim the whole display, because a pause is modal and a
console left bright under it would read as still live — but centred on
`GAME_CX` their text lands 230 pixels right of where the player is looking and
runs straight across the console's readouts, which through a 68% scrim is two
layers of type in the same place.

The design resolution is 1920x1080 and `display_set_gui_size` pins the GUI
layer to it, so a HUD coordinate is a design pixel whatever window the player
has.

**And the game starts full screen.** A 1920x1080 window does not fit on a
1920x1080 desktop -- the title bar and the taskbar are in the way -- so
GameMaker silently shrank it to 1864x1048 and every pixel in the game was
being drawn at 0.97 of the size it was designed at. Nothing looked broken,
which is why it survived: the whole screen scales together. It was reported as
"an awkward windowed mode", and the give-away was in `tools/_preview` the whole
time, where every screenshot was 1864x1048.

`option_windows_start_fullscreen` is on and so is
`option_windows_allow_fullscreen_switching`, which is what gives the player F4
back -- a game that seizes the display with no way out is worse than a small
window. Aspect is kept rather than stretched, so a display that is not 16:9
letterboxes.

**Neither harness takes the display, and that reverses a decision.**
`-selftest` always dropped back to a window — the suites draw nothing anybody
looks at and `tools/test.py` runs every few minutes. `-shot` did not, on the
reasoning that there the display *is* the output: full screen makes a
screenshot 1920x1080 exactly, so a design pixel and a photographed pixel are
the same pixel and a HUD box can be measured off the PNG.

What that reasoning left out is who is at the machine. Both tools are run while
somebody is working on something else, and a harness that seizes the display —
changing the display mode, rearranging every other window, stealing focus for a
few seconds, nineteen times over for `--all` — costs far more than it buys.
Reported, in those words, as a nightmare to work alongside.

The price is that a screenshot comes back at 1864x1048, because a 1920x1080
window does not fit on a 1920x1080 desktop. That is 97% of design size,
everything in the picture scales together, and **nothing in the tooling
measures a screenshot** — `check_bg_keepout` and its neighbours measure the
PNGs the generators write, not these. `tools/shot.py --fullscreen` passes
`-fullscreen` through for the times a photographed pixel really does have to be
a design pixel.

### Gilt on indigo, and why the console is allowed to be rich

**The frame belongs to the player, not to the stage.** Szuix is a blue imp who
flies through other people's territory and takes their magic off them, so the
world inside the boundary is somebody else's — brimstone here, a lantern-lit
wood next, a vampire's hall after that — and the thing framing it is *his*. It
stays indigo and gilt whatever the stage is doing, which is why nothing in
`COL_ARCANE`, `COL_GILT` or `COL_RUNE` is derived from a stage palette and why
the console never takes a hue from one.

**It read as a grey nothing for two passes, and the reason is a rule applied
one layer too far out.** The scenery is kept nearly black because every point
of value spent on it is a point the bullets no longer have. That rule is about
*contrast against bullets* and it holds everywhere inside the boundary — and
the fascia is outside it. A bullet has never had to read against the console.
What the borrowing bought was a settings dialog wrapped round a game about
stealing magic.

What actually has to stay low out here is **brightness**, because a bright
margin pulls the eye off the field — and brightness is not saturation. A deep
indigo at the same value as the old grey is exactly as quiet and reads as a
material instead of as an absence. That is how gilt-on-indigo bookbinding
works, and it is why the reference reads as opulent rather than as loud: a dark
saturated ground, and a *small area* of very bright gold on it.

So: the fascia and the plate are `COL_ARCANE` ramped down to `COL_VOID`;
everything that catches light — the frame's rules, the corner pieces, the
divider crescents, the crest, the tags — is `COL_GILT`; body text is
`COL_PARCHMENT`; and `COL_RUNE` is the cyan accent, used for the field's own
spill, the graze count and about a third of the drifting motes. The one thing
that is still neutral is the inside of a vessel, because a meter's colour is
its *data*.

**The motifs are one family and that is deliberate.** A crescent in the
divider rules, the same crescent in the crest at the head of the console, and
four-pointed sparks on both — plus volutes on the corner pieces and the crest.
One motif at three sizes is a house style; three different motifs would be a
collection. `tools/make_ui.py` draws all of it white and tints at draw time,
so a later stage that wants cold silver instead of warm iron is a colour, not
a regeneration.

**The crest is wide and short because it has to be.** The first one was 300 by
86 at the top of the plate and printed itself straight through the stage name
— a headpiece tall enough to be a headpiece leaves nothing above the first
line of text. Spread along the column it reads as an illuminated band, which
is what an illuminated page puts at the head of a section anyway.

**And the stage rack got the same treatment**, because it is the first thing
anybody sees and it was the last thing left in the neutral grey. Its scrim is
tinted `COL_ARCANE` so the world behind reads as seen *through* the interface
rather than as a brown photograph with panels on it, and a card is a small
console plate with the same ground, the same gilded bevel and — on the
selected one — the same corner pieces.

### The meters

**A meter here is a glass of something, not a rectangle of colour.** The
machinery is `draw_gauge_h` in `ui_functions`, lifted from the gauges in the
`Wordsearch` project where the shape of it was worked out — a trough, a fill
whose light falls off with depth, a wavy surface with a meniscus riding it,
bubbles derived from the clock rather than simulated, and the rim drawn *last*
so it covers where the fill's arc and the glass's arc disagree.

The argument for bringing it over is not decoration. A flat bar is read by
looking at it: the eye leaves the field, finds the bar, measures a length and
comes back. A vessel is read peripherally, because the only part of it that
moves is the surface and the surface is the number. In a genre where looking
away for a third of a second is how you die, that is a mechanical difference.

The surface **sloshes**, and what drives it is the gap between the number and
the vessel's own lagging copy of it — so losing a quarter of the bar throws the
liquid about for a second afterwards and a shard picked up barely ripples it.
Nothing has to tell the HUD that a hit happened.

**There is one vessel now and it lies down.** Life, sigil and the boss's health
are all `draw_gauge_h`; the upright `draw_gauge_v` is gone. The uprights were
the wrong axis twice over: a vertical vessel is read against its own height, so
two of them side by side are two lengths to compare rather than two numbers to
glance at, and a console 416 wide filled with a pair of narrow uprights is a
console mostly made of the gap between them. Lying down, each spans the full
width, its name and value share one line above it, and the two stack into a
block that reads top to bottom like everything else.

**The liquid is sampled off the glass's own contour**, and its absence is the
bug `capsule_half` was written for. A fill drawn as a rounded rectangle has
corners of one radius and the glass has corners of another — and worse, a
partly full vessel's open end is square: at 100% the old upright meter drew a
flat-topped body inside a tube with a 66-pixel radius, so the liquid stood proud
of its own glass by most of a corner. The rim is two pixels and is drawn last
precisely to cover that class of disagreement; it cannot cover sixty-six. So the
fill is not a rectangle of any kind. It is a triangle strip whose top and bottom
edges are read off the capsule, which cannot disagree with it at any fill, at
any radius, at either end — and the wavy end is sampled down y instead, bounded
by the same contour where the two strips meet.

**And the glass is not a rounded rectangle either, which was the other half of
it.** `draw_roundrect_ext` silently clamps its radius: asked for 26 on a tube 52
tall it draws about 12. So the trough and its rim were a rounded *rectangle*
with squarish ends while the liquid inside them was a true stadium — a dark
crescent at each corner of the cap where the two disagreed by twelve pixels,
which is exactly the misalignment the contour work was supposed to remove. It
reads as the *liquid* being the wrong shape, because the liquid is the part that
moves. There is one contour now and everything comes off it: `capsule_half` for
anything filled along its length, `capsule_ring` for anything outlined, and no
call in the section hands a radius to GameMaker at all.

`capsule_ring` walks -90° to 90° around the right cap and 90° to 270° around the
left, so it starts at the bottom right and ends at the bottom left. **Closing it
to the top right instead lays one more quad from the bottom-left corner to the
top-right one**, which is a rim-coloured diagonal band straight across the
vessel. It shipped for exactly one screenshot and was reported as "a weird
diagonal line through it", which is precisely what it was.

**And the contour has to be *sampled* where it curves.** A capsule is an arc
at each end and a straight line between them, so an evenly spaced walk spends
its samples where nothing is happening and crosses a whole cap in one segment.
On the boss's bar that segment was 30 pixels wide over a 5-pixel radius, and
what it drew was a triangle — the liquid arriving at the closed end as a wedge
with a visible dark gap between it and its own glass. That is the very defect
`capsule_half` exists to remove, reintroduced one level down by the sampling
rather than by the geometry, which is the same shape of mistake as the swept
collision test's bounding box needing to cover the whole segment. `LIQ_CAP_STEP`
is the fine spacing inside a radius of either end; `LIQ_BODY_STEPS` is what the
straight middle gets.

**The liquid is dark and the light on it is a highlight.** That is the
difference between glass with something in it and a moulded plastic capsule.
The first pass ran the body from a 30%-white top edge to a 62%-void bottom and
then added a gloss, a meniscus and a bloom over all of it: what came back was a
pale pink lozenge four hundred pixels wide. The divisions are engraved rather
than painted for the same reason — a dark hairline with a pale one beside it is
a groove cut into the glass, where a single bright bar across the liquid is a
bar drawn on top of it.

The boss's bar is the same vessel at fourteen pixels, with the phase table's
thresholds notched into it. A notch is **dark where it crosses the liquid and
pale where it crosses the empty glass**: one colour cannot do both, and a dark
notch on the unfilled half of a near-black trough is not there at all — which
is the half of the bar that says how much of the fight is left.

### Feedback, and where it is allowed to be loud

**Every reaction in the console is derived by watching, not by being told.**
Nothing in the game calls `hud_note_hit` or `hud_note_score`; `hud_step`
compares what the console is showing with what is true and lights a flare on the
difference. That is what keeps feedback from rotting — a new way to lose health,
or a new source of points, animates correctly the day it is written because
nobody had to remember to tell the HUD. It is the same argument the slosh is
built on, applied to five more numbers.

The flares are one-sided where the fact is: health *lost* flushes the meter,
because picking a shard up is a good thing and should not set off the same alarm
a bullet does — which a plain `abs` difference could not express.

**The one loud piece is the frame, and it is loud because it is free.** A hit
already shakes the screen and flashes it white, and both make the field
momentarily harder to read. The boundary is 1360x992 of outline that no bullet
is ever behind, so lighting it red is a message delivered entirely in pixels the
player was not using.

**Ready is said by the rim and by a sheen, not by the fill.** The sigil meter
answers one question — is there enough to spend — and lightening the liquid to
say so turns a 416-pixel tube into a bar of pale cyan every time the meter does
its job. Something *moving* along the glass is caught by the periphery, which is
the whole argument for a vessel over a bar applied to the one state a vessel
cannot express by its level. The ready rim is the meter's own hue lit rather
than white, because white is what every selected control in every menu is drawn
in.

## The engine

### Bullets are structs in a flat pool, not objects

A screen of danmaku is two to four thousand bullets. Four thousand GameMaker
instances is four thousand Step events, four thousand Draw events, a create and
a destroy for each, and a collision system that wants to know about all of it.
The pool is one array, one loop, one draw pass, and one distance check per
bullet against a single point.

It is the same argument `obj_game` in the Wordsearch project makes for not
giving a board tile an object: a bullet has no behaviour that needs resolving
locally.

**A dead bullet is swapped with the last live one and the count drops.** Order
does not matter to a bullet, so removal is O(1) and the array stays dense — and
the struct beyond the count is *kept*, not freed, so a pattern that fires a
thousand bullets a second allocates nothing after its first second. The step
loop runs backwards for the same reason: a swap-remove at `i` moves an unvisited
bullet into `i`, and a forward loop would skip it.

**The pool refuses rather than resizing.** Past `BULLET_MAX`, `fire` answers
`undefined` and every caller has to cope. A pool that grew without limit would
turn a runaway pattern into a machine that stops responding, which is far harder
to find than a pattern that visibly stops firing.

Measured: **about 2.0 microseconds per bullet-frame under the VM runtime**,
which is what `tools/build.py` produces — 4ms a frame at the two thousand
bullets the suite uses, and about 1.5ms at the six to twelve hundred a busy
screen actually carries. YYC is several times faster again. The figure is
dominated by the interpreter rather than by anything the code does: hoisting the
pool and the shape table out of the loop, and replacing the graze test's
`point_distance` with inline squared distance, together moved it by under three
per cent. **The lever that would actually matter is folding the three passes
into one** — step, graze and hit each walk the whole pool — and it is not done
because it would turn three pure functions into one that does everything.

### The firing API is Danmakufu ph3's

`fire` is `CreateShotA1`: a position, a speed, an angle, a graphic and a delay.
Everything else is built out of it — `fire_ring`, `fire_fan`, `fire_stack`,
`fire_ring_stack`, `fire_spray`. `fire` returns the bullet so a caller can set a
turn rate or a modifier on it; the pattern helpers return nothing, because the
single-shot case is the one that wants tweaking afterwards and the pattern case
never does.

**One bullet goes down the centre line of an odd fan, and that is a fairness
rule rather than a geometry one.** With an even count the fan has a *gap* on the
aim line, so an aimed even fan is a pattern the player survives by standing
still and an aimed odd fan is one they must move for. Both are legitimate; what
is not legitimate is not knowing which one you wrote. `test_fire_patterns`
asserts the middle bullet is on the aim.

**A bullet is moved by one of two models.** `fire` gives the polar one —
direction, speed, acceleration, turn rate — which is ph3's A-series and what
every pattern in this game is written in. `fire_xy` and `bullet_force` give the
Cartesian one, which is its B-series, and the reason it is here rather than
folded into the first is that **a force in a single axis has no polar
expression at all**: `dir` and `spd` bend a path only along its own direction,
so a bullet that falls, arcs, lobs or is blown sideways cannot be written as a
heading and a number. Everything else the B-series does is a convenience that
could have been left out.

`cart` is the one integer compare that says which model a bullet is on, and
`dir` and `spd` are kept true on both — which costs a `point_direction` and a
`point_distance` per Cartesian bullet per frame, and buys that collision,
aiming, the oriented sprites and every later instruction go on reading one
motion model. **A polar instruction takes a bullet back off the Cartesian
model**, because otherwise a force set forty frames ago silently overrides the
aim that has just arrived.

**Beyond that, a bullet does two kinds of thing: one continuously, and any
number of them at particular frames.** `BMod` is the first — `Home` (steer
weakly, with a hard cap on degrees per frame, because a bullet that turns as
fast as it likes is unavoidable rather than hard) and `Wander`. Neither carries
a frame number, because they are what the bullet is doing on every frame it
has.

`BQ` is the second, and it is ph3's `AddPattern` family: `Aim`, `Move`,
`Accel`, `Turn`, `Force`, `Split`, `Shed`, `Graphic` and `Fade`, scheduled
through `bullet_aim_at`, `bullet_split_at` and the rest. **What it replaced was
a single modifier slot with one frame number beside it**, which allowed a
bullet exactly one event in its whole life — so "aim at 20, accelerate at 40,
break into six at 80" was not a pattern this engine could hold, and neither was
most of what the genre's second-half spells are built out of.

The queue is sorted on insert and walked off the front, so a bullet carrying no
events costs one integer compare — **the same bargain `BMod` makes, and the
reason the ninety per cent of bullets that are plain still cost what they
always did.** Its slots are kept the way the pool's structs are, so a pattern
that schedules three events on every bullet it fires allocates nothing after
its first second, and it **refuses past `BULLET_QUEUE_MAX`** rather than
growing, for the same reason the pool does.

**A split and a shed differ by whether the parent lives, and that is worth two
kinds rather than a flag.** A bullet that bursts is one pattern; a bullet that
drops a wake behind it and flies on is a different one, and the old modifier
could only express the first. Both give their children the parent's shape and
colour, so a burst reads as *that bullet* going off rather than as one bullet
vanishing and some unrelated ones appearing.

**A bullet with a lifetime fades rather than vanishing, and is harmless from
the first frame of the fade.** Culling is otherwise by geometry alone, which
means anything homing — and anything turning fast enough to orbit — used to
live until the phase ended: the pool is a refusal rather than a resize, so what
that reaches a player as is a boss whose later patterns quietly stop firing.
The fade is a courtesy to the eye and never a window in which a ghost can still
land a hit, and a bullet that blinked out mid-field would read as a bug in the
game rather than as a rule of the pattern.

**`resist` is bomb-proof, and it is the difference between the two sweeps.**
`bullet_clear_circle` spares it, because a circle is something the *player*
did — a bomb, or the mercy clear after a hit — and marking a bullet is how the
genre writes a survival spell. `bullet_clear_all` takes everything, because
that is the *game* changing what is on the field and a bullet left over from
the previous attack is a bug rather than a challenge. Lasers carry the same
flag on the same terms.

`life` is incremented at the *end* of a step, so a bullet spawned this frame is
on frame 0 during its first step and an event scheduled for frame `_at` fires
on step `_at + 1`. That is asserted rather than adjusted, because incrementing
first would make frame 0 unreachable.

### Every bullet is born intangible

**This is the single most important fairness rule in the genre.** A boss that
spawns a hundred bullets on top of the player kills them before the frame is
drawn. So every bullet spends `delay` frames as an oversized, additive,
*harmless* mark that shrinks onto the spot it will occupy — and it does not
move while it does, because a mark that drifted would be a promise the bullet
then breaks. The delay marks are drawn in a second pass over the live bullets so
a warning is never hidden under the bullets already on the field.

The same rule is why `laser_beam` takes its warning time as an ordinary
argument rather than as an option: writing a beam with no warning should look
wrong on the page.

### Collision is swept, not point

A dart at speed twenty-four moves twenty-four pixels between frames and the
player's hitbox is four. A point test therefore misses roughly four times in
five, and what that produces is a bullet passing *through* the player and doing
nothing, at random — which reads as the game being broken rather than as the
player being lucky. `bullet_hit_index` measures the distance from the player to
the **segment** the bullet travelled.

It rejects on a bounding box first, because `point_seg_dist` is a GML call with
a dozen operations in it and nearly every bullet is nowhere near the player. The
box has to cover the whole segment, not just where the bullet ended up —
otherwise the tunnelling bug is reintroduced one level down, inside the
optimisation that was added to make the fix affordable.

**A bullet is grazed once, ever.** Without the flag a player parked beside a
slow bullet grazes it sixty times a second, which turns the one mechanic that
rewards nerve into one that rewards loitering. Grazing stays live during
invulnerability, deliberately: the three seconds after a hit are the only time
the player is free to sit inside a pattern, and letting those seconds pay turns
being hit into a chance to claw points back.

### Lasers: three kinds, one pool

- **Beam** — anchored, telegraphed, fires, fades. It may follow its caster, so
  a drifting boss drags its beams with it, which is what makes a swept wall read
  as something the boss is *doing* rather than as scenery.
- **Ray** — a bar of light that travels. Its body runs *backwards* from its
  head, which is the one thing about it easy to get the wrong way round, so
  `test_laser` asserts on both ends. It is culled when its **tail** has left,
  not its head: a ray whose head is off the left of the screen is still lying
  across the middle of it.
- **Curve** — the one that looked hard and is not. **A curved laser is a trail
  of where its head has been.** The head is an ordinary bullet with an angular
  velocity, and the laser is the last `CURVE_NODES` positions it occupied.
  Nothing curves; a straight thing moves and its history is the curve. Collision
  is the same segment test run down the trail. When the head's life is up it
  stops and the tail drains a node a frame, which reads as light running out of
  a wire — and because collision reads the same node list, the part that has
  drained is also the part that has stopped being dangerous.

A laser is dangerous **only while firing**. A warning that could kill would make
the telegraph a lie; a fading one that could kill would punish the player for
believing it was over. And the width it kills at is a third of the width it is
drawn at, because the glow either side is light rather than beam — a player who
believes the bright core is the hitbox should be right.

**A laser pays for nerve, and until recently it did not.** Sliding along a beam
is the most deliberate risk this game asks anybody to take — a bullet passes
whether the player is brave or not, where a wall of light is something they
have to choose to stay beside — and it was the one piece of nerve the score
said nothing about. It pays **on a cooldown** where a bullet pays once ever:
the flag a bullet carries is the whole truth about a thing that passes and is
gone, and on a wall that stands there for two seconds it would pay somebody who
brushed it for a frame exactly what it pays somebody who rode the length of it.
Only a *firing* laser can be grazed, on the same reasoning as the kill: paying
for standing in a warning line would be paying the player for reading the
telegraph correctly and then ignoring what it said.

The band is `laser_hits`' band plus `GRAZE_R`, off the same `laser_spine_dist`,
so the distance between being paid and being killed is the deal the player has
already learnt from the bullets — and a laser that killed along one line and
paid along a slightly different one is a disagreement no screenshot and no
assertion about either half could ever show.

The curve is drawn as a run of soft blobs down its trail rather than as a
textured triangle strip. A strip is the tidier answer and needs the sprite's
UVs off the texture page, a `pr_trianglestrip` built by hand, and a mitre at
every node; blobs at this size are indistinguishable once they overlap,
additive blending hides the seams for free, and sixty-four draws per laser
against a handful of lasers is nothing.

### The player is a struct and its input is an argument

`player_step` takes an input struct rather than reading the keyboard, so a
suite can put a player at a coordinate, hand it eight frames of "hold left and
shoot", and assert on where it ended up. `input_gather` is the one function in
`scripts/` that touches a device, and `obj_game` has one seam —
`input_override` — which is `undefined` in play and a struct when something else
is driving. Today that is only `obj_shot` posing a scene with the shot button
held; tomorrow it is a replay or an attract mode.

**Diagonals are normalised.** Without it, moving diagonally is forty per cent
faster than moving straight and every player who notices travels everywhere at
45 degrees.

**A special beats a bullet arriving on the same frame.** The bomb is checked
before the shot and before anything can hit, which is the most argued-about
frame in the genre and the only defensible way round it: a player who reacted in
time should live. `test_player` asserts it directly.

The bomb's sweep **grows** over `BOMB_GROW` frames rather than clearing the
screen at once — a bomb that emptied the field on its first frame would be a
screenshot of an empty screen, and growing it means the player watches the wave
reach the bullets and turn them into score on the way.

**A hit scatters shards.** Touhou drops your power on death; this is the same
idea turned round. Losing a quarter of the bar puts a handful of recoverable
points on the field, so the moment after a hit is a scramble rather than only a
loss. They are gold, not red — being hit must not hand back the health it just
took. And the bullets on top of the player are cleared, or the invulnerability
runs out inside the same wall and the player dies twice to one mistake.

### The hitbox is drawn after the bullets

Bullets and lasers draw over the player, which is the genre's order and is right
for a reason: what the player must never lose track of is the *bullets*, and a
character sprite eighty pixels wide sitting on top of them would hide a dozen.
The hitbox is four pixels and has to be findable through anything, so
`player_draw_hitbox` is a function of its own, called last.

It appears only while focused and **it is the truth**: its radius is `PLAYER_R`
and the sprite is drawn at exactly that size, so what the player is shown is
what the game tests. Anything else would be a lie the game told sixty times a
second.

### Screen shake is a world matrix, not a camera

The GUI layer must not shake — a health bar that jitters on every hit is
unreadable at exactly the moment it is being read — and a matrix in the Draw
event leaves the GUI event untouched for free, with no view to configure and no
surface to own.

## The boss

**One health bar, with the thresholds notched on it.** Touhou gives a boss a
stack of bars, one per attack, and refills between them; that is legible and
says nothing about how far through the fight you are. Here the bar only ever
goes down and every attack's boundary is cut into it, so a glance answers both
"how is this attack going" and "how much of this is left". A spell's notch is
drawn taller than a non-spell's, so the *shape* of the fight is legible before
any of it has been reached. What it costs is that a long fight's last attack is
a short span of bar, which is why the notches are drawn rather than the phases
being made equal.

**The attack table is data and an attack is a function of time.** A phase is
`{kind, name, col, bg, hp_end, time, attack}` and `attack(_e, _g, _t)` is called
once a frame with the frames elapsed. That is the whole interface, and it is
enough for everything in the genre: a pattern is a `switch` on `_t mod period`,
which is exactly how it reads on paper.

**A phase ends on health or on time, and never on anything else.** Health is
checked first: a boss brought to the threshold on the same frame its timer
expires has been *beaten*, not survived, and checking the other way round would
quietly deny the capture bonus on the attempt that most deserved it. A timeout
is not a failure — it ends the attack the same way, awards no capture, and moves
on, which is what stops a player who cannot beat one spell being stuck on it
forever. Either way the bar is pulled down to the threshold, so it can never
disagree with which attack the boss is on.

**A spell declares itself before it fires, and a boss in ceremony cannot be
shot.** Both are the genre's rules and neither was implemented. A spell used to
open its pattern on the frame it was named, so the eye card announcing it was
drawn over bullets the card had already launched — which is the same finding
that first shrank the eye card, treated as a drawing problem when it was a
timing one. And `boss_vulnerable` described the invulnerability in a docstring
that nothing outside the suites read, so a player holding the shot button
chipped the boss through its arrival, its declaration and every pause between
attacks.

`BOSS_SPELL_LEAD` is the wait and `enemy_take_shots` is the enforcement. The
lead is above the attack rather than inside it, so no pattern has to remember
to do it — the same argument the delay marks are built on, one level up. The
phase clock does not start during it, so an attack gets its full time either
way.

The lead is the *eye card's* length rather than the banner's, because the card
is the piece of the ceremony that occludes: a face across the middle of the
field is the thing bullets must not be under, where the banner is one line of
outlined text sliding out and danmaku beneath it is what the genre looks like.
So the pattern opens as the face leaves, with the banner still going. A
non-spell has no ceremony and opens at once; the pause between attacks is all
the breathing room one gets, which is the difference the ceremony is there to
draw.

**A capture needs the spell beaten *and* untouched** — no hits and no bombs.
That is the Touhou rule and it is the right one: a bonus for merely surviving
rewards hiding in a corner.

**A boss drifts.** One that stood still would fire every aimed pattern from the
same pixel and the player would learn the pixel rather than the pattern.

**Every enemy is drawn out of the pool, bosses included.** `enemy_draw` used
to skip anything carrying a `boss` struct on the grounds that "the boss draws
itself", and the controller drew it — through `boss_ref`, which is *the boss
the run is currently fighting*. Those are not the same set, and where they come
apart a boss is drawn by nobody while remaining perfectly able to fire and
solid to the touch.

There are two ordinary ways to have one. A beaten midboss keeps flying after
`boss_ref` is released, so it departed invisibly rather than "leaving under its
own power" as it is supposed to. And a boss inherited from a run that did not
clean up after itself was never referenced at all, so it was invisible for the
whole of the next one.

The pool is what exists and the pool is what is drawn; the controller's opinion
about which boss is interesting has nothing to do with visibility.

**A midboss is the same machinery with one flag.** `def.final` is false, so
beating it does not end the stage; the boss flies off the top under its own
power after its death throes and `enemy_step` culls it like anything else that
leaves the field. The difference between a midboss and a boss is one field, not
two code paths — and the midboss also skips the name splash, because the
ceremony is the *boss's* and spending it early would make the real arrival mean
less.

### The ceremony

A named spell gets a banner, an eye card, and a background of its own.

**The eye card is a close-up of the boss's whole face, not a pair of eyes on a
field.** The camera pushes in until the head runs off all four edges; the eyes
dominate because they are the brightest thing in it, not because they are the
only thing in it. Horns leaving the top of the frame and ears leaving the sides
are what say "this is a crop", and the crop is what says "close up". It is drawn
in card space rather than by scaling the sprite: at five times its size the
260px sprite is mush, and a face wants different proportions in close-up anyway.

**The spell background is drawn in code, and it belongs to the boss rather
than to the spell.** A painted background is a 1360x992 sprite per boss and a
texture page nobody wants to budget; what ships instead is a handful of
tintable motifs and a function per boss, so a new boss costs a `SPELLBG_*` on
its definition and a function in `bg_functions`.

**One background per boss, not one per spell.** An earlier version tinted each
boss's background with the current spell's hue, so Ziggy ran gold for `Cinder
Waltz` and crimson for `Meteor Fall`. That is worse than not having it: a
boss's arena is a *place*, and a place that changes colour every forty seconds
stops being one. The spell's own colour already lives on its bullets, its
banner and its notch in the health bar, which is enough.

`SPELLBG_SIGIL` — two counter-rotating magic circles — survives as the fallback
because it is genuinely right for some casters: the Warden is a carved stone
told to watch, and a circle of power is what one of those stands in. What it is
not is a default that suits everybody, which is what it used to be.

Ziggy gets `SPELLBG_BRIMSTONE`, fixed in red, grey and black: the world becomes
the inside of a forge. Black rock fracturing outward from wherever he is
standing, lit from underneath; a wavefront of heat travelling out along the
cracks every four seconds; columns of smoke, with grey ash and red cinder going
up through them; and his own horns rising out of the bottom corners, lit along
their leading edge — a black silhouette on a near-black wash is nothing at all,
so what reads is the contour and the eye completes it into a mass. Six layers
at four rates, and a vignette last, which is the cheapest single thing that
separates a background somebody made from one something generated.

The cracks radiate from *him* rather than from the middle of the field, which is
what gives the light a source.

Whatever the style, it works by **subtraction** — the same reasoning the spirit
in Wordsearch is built on. The field does not get brighter; the world behind it
stops competing. That rule is easy to state and easy to break: the first
textured version of the forge was drawn at an alpha that looked right on its own
and came back as an amber fog with the danmaku somewhere inside it. A crack has
to be the bright thing and the space between cracks has to be black.

**And the near parallax layer has to stand down for it.** That layer is the one
piece of scenery drawn *over* the field, so during a declaration it was the only
thing left competing with the pattern — the wash had correctly removed the world
and two columns of lit basalt were still standing over the top of it. A
background that works by subtraction cannot have a foreground that opted out.
`bg_draw_front` takes the same eased fade the wash uses.

The declaration holds the *stage*, not the field. Bullets already in flight keep
moving through it, which stops the screen freezing at the exact moment it is
trying to be dramatic.

**The banner leaves and the name stays.** A named attack in this genre is a
thing the player learns *by name* — it is how they think about the attempt, how
they talk about it and what they look up afterwards — and the first version put
the name on screen for two and a half seconds at the start of an attack that
then ran for another forty. Three seconds in, nothing anywhere said which spell
was being survived.

So the banner is announced across the field, at size, and slides out to the
right as it fades; and `hud_draw_spell_name` puts the name in the HUD column and
holds it until the attack ends. `spell_a` only eases up once `banner_t` has run
out, because the same words in two places at once reads as a bug rather than as
ceremony.

The plate **breaks the name at the double dash**, onto two lines. A Touhou spell
name is a type and a title — "Ember Sign" and "Cinder Waltz" — and set as one
string in a 446-pixel column it has to shrink to a third of its size to fit,
which puts the most evocative text in the game at the size of a footnote. The
split is free, because the names already carry the separator.

It also carries the one fact about the attempt still in play: whether the
capture is still live. A player who has been hit has nothing left to protect and
should be told at the time rather than on the result screen.

### Practising one attack

**This is Touhou's spell practice, and it is the only thing in the game that is
not a stage.** The Cuphead progression already answers "I do not want to replay
four stages to reach this boss"; what it does not answer is "I do not want to
replay four minutes of waves and six attacks to reach *this attack*", which is
the loop anybody tuning a pattern is in — whether they are playing it or
writing it. X on the rack opens the attack list for the highlighted stage, Z
starts one, and the panel at the end of it offers the same attack again.

**A practice run is an ordinary run with two things taken away and one added.**
The timeline is empty, the boss is put straight onto the field on the chosen
attack, and that attack ends the attempt rather than handing over to the next
one. Everything else — the console, the ledger, the spell ceremony, the
background, the grading — is the game's, untouched. It is written as a *mode*
rather than as a debug menu because the two are the same work and only one of
them is worth keeping.

The pieces are all seams that already existed or wanted to:

- **`global.practice` is the request**, and `obj_game` reads it in Create. Same
  seam `global.stage_def` uses to say which stage the rack chose, for the same
  reason: a room transition carries nothing with it. `undefined` is the whole
  of "an ordinary run".
- **The definition it carries is stage-def shaped**, so the run, the console
  and the background take it without knowing this mode exists. `name` is the
  attack, `subtitle` is its caster, `encounters` is 1, `build` returns an empty
  timeline — an empty stage rather than a suppressed one, because the
  alternative is a `practice` test inside `stage_step`.
- **`on_phase_end` is the third hook of its shape**, beside `on_boss_beaten`
  and `on_player_hit`, and it keeps the same direction: the boss decides, the
  run reacts. It is called from `boss_end_phase` because that is the only place
  that knows *how* the attack ended — the line above it pulls the health down
  to the threshold on a timeout as well, precisely so the bar cannot disagree
  with which attack the boss is on, which means nothing downstream can tell a
  spell broken from a spell survived.
- **A boss is listed as a function returning its phases, not as its phases.** A
  table built once at stage-definition time would be shared by every run that
  read it, and a phase struct is mutable. That is why `ziggy_midboss_phases` is
  now a function of its own rather than a list inside its spawner.

**Broken, survived and defeated are three outcomes, not two.** A spell run down
to its clock is a real result in this genre — it ends the attack, awards no
capture and moves on — so a panel folding it into either of the others would be
lying about the rules the attack is played under. A capture is a fourth word
again, because a spell broken untouched is the thing being practised *for* and
telling somebody who has just managed it that they merely cleared it reports
the good outcome as the ordinary one.

**Full life and full sigil, every attempt.** A practice attempt is about the
attack and not about what the four minutes before it left behind, and starting
one on whatever health a stage handed over would make two attempts at the same
pattern incomparable. The sigil is full for the same reason pointed the other
way: a bomb is part of how a spell is fought, and an attack that could only be
rehearsed without one is an attack whose real answer cannot be rehearsed.

**And the attack does not open on the first frame.** The first version did, and
it was reported immediately: no breathing room and no time to position, because
the player arrives at the default spawn with a pattern opening on them. So
practice arrives *inside* the boss's own between-attacks pause —
`practice_begin` sets `clear_t` and `next_phase` rather than calling
`boss_enter_phase` itself — and a `READY` count runs over it. `phase` stays at
-1 through the beat so nothing names an attack that has not begun; sitting on
`phase_i - 1` instead would have the boss's line counting down the *previous*
attack's clock.

`PRACTICE_READY` is two seconds rather than three because `BOSS_SPELL_LEAD`
follows it: a practised spell gets the beat and then its declaration, and this
is a mode whose whole value is how quickly it can be done again.

**It is gated on the stage being built and on nothing else.** Not on the stage
being unlocked, and not on the attack having been reached, which is what Touhou
does — the rack's locks pace a first playthrough, and gating a tuning tool
behind the progression it is used to tune is a circle. What it is gated on is
having something to practise: an unbuilt stage has no `bosses` field at all,
and a bare read of one raises rather than answering `undefined`.

**Nothing about it can touch the save.** `progress_record` is keyed on
`def.id`, and a practice definition's is the empty string — so there is no
stage to file a clear against, and the call is guarded as well because the cost
of being wrong is a stage marked cleared in a real player's save by somebody
drilling its first non-spell, permanently, with nothing to report it. The
console's BEST row instead reads `def.best`, which is the best on *that attack*
this session, held in a global map and never written to disk. It is refreshed
at the start of every run rather than at the end of one, because BEST during an
attempt has to mean the best from before it — writing this attempt's score into
it the moment the attack ends has BEST and SCORE converge on the same number
while the player watches, which says nothing and looks like a bug.

**The screen that begins a run is the screen that says which kind it is.** The
attack list deliberately leaves `global.practice` standing when it is left, so
returning to it puts the cursor back on the attack practised last — which means
the *rack* has to clear it when it starts a stage. That is exactly the shape of
the bug `run_clear_field`'s note is about: one entry path correct and every
other one inheriting.

Two things had to be hidden and both were found by looking. The boss's line
goes for the duration of a practice result, because the phase index does not
move until `clear_t` runs out — so for a second and a half the bar is still
naming the attack and counting its clock down, under a panel announcing the
same attack in the past tense. And the panel's own menu ran into the hint line
at the foot of the field, which is a failure no assertion can see: every one of
those coordinates is inside the field and none of them overlaps a console box.

## Stages

**A stage is a list of `{at, fn}` and nothing else.** A stage runs for minutes
and is made of two dozen scripted moments; the alternative is a two-hundred-line
`switch` on a frame counter, which is the same list with the structure taken out
of it and which cannot be inspected, reordered, or asserted on. `test_stage_table`
walks the table and checks it is sorted; `test_stage_run` plays the whole thing
headlessly, killing each wave a second after it arrives, and asserts the stage
reaches its end and puts a boss on the field on the way.

**A run begins by emptying the field, and `obj_game`'s Create is the only
place that says so.** Every pool in this game is a global, allocated once in
`obj_boot` and reused for the life of the process — which is the right shape
for a pool and is exactly why entering `room_game` says nothing at all about
what is on the field unless something says it. `run_clear_field` is that
something.

**It used to live on one entry path instead of at the entrance, and that cost
two bugs that sounded unrelated.** The clearing was inside `game_reset_stage`,
the pause menu's restart, so that route started clean and every other route
inherited the previous run's field. Finish a stage, take the result screen back
to the rack, pick a stage, and the run opened with the last attempt's bullets,
lasers, items and enemies still in the pools — the boss included, still
stepping his phase table and still firing patterns into a fight that had not
started.

He was also *invisible* while doing it, for a second and independent reason
(see below), so what actually reached the player was "Ziggy's patterns keep
firing at the start of the level" and "I take random damage from invisible
bullets". One cause, two symptoms, and neither reachable down the pause-menu
path — which is the path a developer naturally exercises and the one that
happened to be correct.

`test_run_starts_clean` proves `run_clear_field` empties everything.
`check_run_clears_the_field` proves somebody calls it, because the bug was
never in the clearing — it was in the calling.

**A gate stops the clock rather than skipping ahead.** The shape a stage wants
is "spawn these, wait until they are gone, spawn the next lot", and a wave that
takes longer than expected must not have the next one land on top of it. So a
gate freezes stage time until the field is clear, which means every `at` after
it stays true to the time the designer wrote.

The gate's half-second grace is load-bearing: a gate placed near a spawn would
otherwise see an empty field — the enemies do not exist until their own event
has run — and release immediately, collapsing the whole timeline into one frame.

The stage only advances while `boss_ref` is `undefined`, so a midboss that takes
two minutes does not eat the waves written after it.

### Nothing in a wave is a creature

The fodder is a wisp, a grimoire, a cut gem and a stone sentry — animated
furniture, somebody else's tools left running. That is a story decision before
it is an art one: the game is about an imp who is tired of being somebody's
trash mob, so filling his stages with trash mobs that are *people* would say the
opposite of what the game is about.

They are drawn greyscale and **tinted at draw time**, so one set of four serves
every stage in the game — crimson wisps over Ziggy's brimstone, jade ones in a
yokai forest, violet in a vampire's hall. That is why the art is built out of a
bright core and a dark rim exactly as the bullets are: a multiply maps that
structure onto any hue and keeps the reading, where a flat mid-grey would tint
to a flat mid-hue and disappear.

Hit feedback is **additive white on top**, not a blend to white — a blend loses
the silhouette against a bright background at exactly the moment the player most
wants to know they are hitting something.

**A silhouette is not enough, and that was the first version.** Each of these
was one shape run through `shade_shape`, which lights a shape by how deep inside
it a pixel is — the right answer for a *bullet*, which is a bead of light with
no interior, and the wrong one for an object, because an object has planes and
the planes are how the eye works out what it is looking at. Four flat lozenges
is what that produced.

Each is now three things multiplied together: the depth-shaded body, a **facet
map** giving each plane its own value, and a detail pass of grooves and grain.
`FACET_NEUTRAL` is high and `FACET_MAX` is low, so a facet map mostly *darkens*
— the body underneath is already nearly white, and a map centred on mid-grey is
free to multiply that core by 1.8, which clips, and a clipped facet is a flat
white region with no plane information left in it at all.

The gem is the case that proves it: a cut stone has no curvature whatsoever, and
everything the eye reads as sparkle is flat faces at different angles. Six
polygons and six numbers make a stone where one silhouette shaded by depth makes
a pillow.

**The grimoire has had three silhouettes and the reasoning behind each rejection
is the useful part.** Open and face-on, it was two panels meeting at a point,
which at this size is a bowtie. Shut and standing on its end, it was a rectangle
with a stripe down each side, which is a door. It is now open and seen from
*above*: two quadrilaterals lying at an angle either side of a gutter, with page
blocks at their outer edges — nothing about it comes to a point, so nothing
about it can collapse into a bowtie. The lesson underneath all three is that at
eighty pixels an object is read off its silhouette and its proportions, never
off its detail. Detail is what makes it look expensive once it is already
recognisable.

### Every speed is a property of the room

**The first pass of every speed in this game was tuned against the genre's own
numbers, and the genre's numbers are for a playfield 384 wide.** A player at 7.2
pixels a frame crosses this field in about four seconds where a Touhou player
crosses theirs in one; a wave at 2.6 is on screen for twelve seconds, which is
not a wave, it is a procession. Nothing was individually wrong — they were all
answers to a different question about the size of the room.

So the traversal *time* is what is held fixed rather than the pixel rate.
Movement, shots, bullets, waves and the background scroll are all up by roughly
half again, and the numbers live where they always did: in `constants` for the
engine and written out in `stage_ziggy` for the content, because a pattern is
meant to read as a paragraph and a hidden global multiplier would make every
number in it a lie. `PSHOT_DMG` came down as `PSHOT_PERIOD` did, so the damage
per second is unchanged and every `hp_end` in the phase table still means what
it did.

**Three things do not scale with speed, and all three were found by scaling
them anyway.**

A spiral's shape is the ratio of its turn rate to its bullet speed, so doubling
the speed and leaving the turn alone pulls every arm into a straight radial line
and the spiral stops being one — `ziggy_cinder_waltz` halves its turn as it
doubles its speed, and `ziggy_no_mere_pawn` does the same to its lashes' curl.

A laser's length is measured against the field's diagonal rather than against
its own idea of "long", because a wall of light that ends halfway across the
screen reads as the boss having missed.

And a curved laser's trail records one node per frame, so **the gap between two
nodes is the head's speed**. See `laser_draw_curve`.

## Stage one: the Brimstone Reach

Ziggy — short, stocky, red, Szuix's friend and rival. Seven attacks: three
non-spells and four spells, descending 1.00 → 0.90 → 0.75 → 0.65 → 0.50 → 0.40 →
0.20 → 0.

**All three non-spells are the same idea at three speeds**, which is what a
non-spell is for: it is the boss's handwriting, and the spells are the
sentences. The spells each introduce exactly one thing — a spiral, a splitting
bullet, a telegraphed beam — and the last one is everything the stage has taught
run at once, which is why nothing in it is new.

He is written as a *first* boss and a tutorial for the whole genre: his
non-spells are wide and slow, `Cinder Waltz` is survivable by standing in the
right place because nothing in it is aimed, and only `No Mere Pawn` plays for
real.

## The art

**All of it is generated** at 1920x1080 by the `tools/make_*.py` scripts, except
Szuix, who was commissioned. Everything is drawn supersampled 4x and downsampled
once, because PIL's draw calls are hard-edged and a bevel drawn at 1x reads as
"made by a script".

| Script | Output |
|---|---|
| `tools/art_common.py` | Palette, `Canvas`, the distance-field shader, glows, fbm noise, preview sheets |
| `tools/make_palette.py` | `scripts/palette` — the palette, in GML |
| `tools/make_bullets.py` | Every bullet sprite **and** `scripts/bullet_table` |
| `tools/make_fx.py` | Sparks, blooms, rings, laser textures, shards, the hitbox, the boss sigil |
| `tools/make_fonts.py` | The six sprite-font atlases |
| `tools/make_enemies.py` | The four fodder shapes |
| `tools/make_boss.py` | Ziggy and his eye card — **placeholder, see below** |
| `tools/make_bg.py` | The three parallax layers |
| `tools/make_ui.py` | The console's furniture: gilt corners, crescent dividers, the crest, attack marks, plate glint |
| `tools/make_player.py` | Szuix, from the commissioned sheet |

Each writes a preview to `tools/_preview/`. Look at it.

### A bullet is a bright core inside a saturated rim, inside a dark contour

This is the one art rule here that is not aesthetic. A bullet has to register as
an obstacle in a fifth of a second against a moving, lit, arbitrarily-coloured
background, and a flat coloured disc does not: over dark ground it is a dark
shape, over bright ground it is a light one, and the player finds out which by
dying. **A white core carries luminance that survives a bright background and a
saturated rim carries hue that survives a dark one**, so the shape reads against
both. `make_bullets.py` writes its preview sheet twice — once on near-black and
once over a bright, busy fbm ground — because a sheet on black only ever proves
half of it.

**And every bullet wears a hard dark contour, which is the half of the rule
that was missing.** The stage's background carries drifting embers — additive
orange blobs a few pixels across — and at fourteen pixels the pellet was the
same object: same size, same hue, same soft edge. A player cannot be asked to
tell an obstacle from scenery by watching which of them accelerates.

The fix is not "make the embers different", though they are now smaller, dimmer
and pushed toward a red no bullet uses. It is that **everything in the scenery
is drawn additively, and additive light cannot make a dark edge** — it can only
ever brighten what is behind it. A dark ring is therefore a mark the background
is structurally incapable of producing, and a shape wearing one reads as an
object in front of the world rather than as a light shining out of it.
`CONTOUR` in `make_bullets.py` is two pixels, traced at the final size rather
than at SS and shrunk with everything else, and traced around the *thresholded*
body rather than the alpha — every bullet has a soft halo, so tracing the alpha
draws a ring around the fog and not around the bullet.

The shapes also grew by about half. The hitboxes grew by a third, deliberately
less: the picture's job is to be seen and the hitbox's job is to be fair, and
growing them together would have turned a legibility fix into a difficulty
change.

The same contour goes on the fodder, for the same reason.

### One sprite per shape, one frame per colour

Eighteen shapes across fourteen hues is 252 combinations, and 252 GameMaker
sprites would be 252 `.yy` files and a texture atlas nobody could reason about.
So a shape is one sprite whose frames are its colours, and drawing a bullet is
`draw_sprite_ext(spr, colour, ...)`. Animated shapes fold both axes into the one
index — `colour * frames + tick` — and `bullet_frame` is the only thing allowed
to compute it. `test_bullet_table` asserts every sprite holds exactly
`BCOL_COUNT * frames` frames and that `bullet_frame` can never index past one.

**Oriented shapes point RIGHT at angle zero**, because GameMaker's `direction`
0 is right and `image_angle` is measured the same way. Drawing them pointing up
— which is how a Touhou sheet is usually laid out — would mean every draw call
carrying a `- 90`, and the one that forgets it is a bullet that is visually
sideways while being mechanically correct.

**`make_bullets.py` is the single source of truth for a bullet's hit radius**,
not just its picture, and it generates `scripts/bullet_table/bullet_table.gml`
to say so. The radius and the sprite have to agree; if the number lived in GML
while the picture lived in Python the two would be edited apart within a week.
The flame is the case that proves it — 46x30 of picture and 7 of hitbox, because
the tail is not the bullet.

### The distance field, and why a blurred mask is not one

`orb_field` shades a round bullet off a radius it can compute in closed form.
Everything else — an ofuda, a dart, a butterfly, a rock — goes through
`shade_shape`, which needs to know how deep inside the shape each pixel is.

The first version approximated that by **blurring the mask**, which is fine for
a blob and useless for anything thinner than the blur radius: a ring wall, a
star's arm and a needle all came out uniformly at the "edge" value, so every one
of them rendered as a dark silhouette with no hue and no core. So the distance
is *counted* — erode by one pixel and add what survives, the classic chamfer
transform. `MinFilter` is a square kernel, so raw output is Chebyshev distance
and a circle's core comes out as a rounded square; one small blur at the end
buys back the Euclidean shape.

**Normalising by the shape's own maximum is deliberate.** It means a rice grain
gets a white core down its middle exactly as a sphere gets one at its centre,
which is what makes fourteen hues across eighteen shapes read as one set.

The transform runs on a downscaled copy of anything large. Its cost is one
erosion pass per pixel of the shape's half-thickness, so it is quadratic in the
mask's size: a 2560x840 boss portrait wants four hundred passes over two million
pixels, which is minutes rather than seconds. Distance from an edge is a smooth
field, so computing it at a quarter scale and enlarging loses nothing a shading
ramp could show.

### A scrolling layer has to tile, and shading is what breaks it

Every parallax layer is one sprite drawn twice — at `y` and at `y - GAME_H` —
so it must be seamless top to bottom. Drawing the *shapes* three times at
different offsets is not enough: `shade_shape` works off a distance field, and a
field measured on a one-tile canvas treats the canvas edge as the edge of the
shape, so a boulder crossing the top of the tile is lit as though it ended there
while the copy drawn at the bottom is lit as though it ended *there*.
`shade_wrapped` shades three tiles' worth and keeps the middle.

The ground's molten cracks needed a second fix: a crack that wanders freely down
the tile arrives at the bottom hundreds of pixels from where it left the top. Its
wander is **de-trended** — the accumulated drift subtracted back out in
proportion to how far down each point is — which pins the last point to the first
without flattening the wander in between.

And the mottle underneath needed a third: two noise fields cross-faded by
`0.5 - 0.5*cos(2*pi*t)` makes the *weight* periodic while leaving both fields to
differ across the join, so the seam was reduced and never removed. `fbm_field`
takes `wrap_y` now, which repeats the noise grid's first row at its bottom
before upsampling, so the thing being interpolated is periodic rather than the
thing doing the interpolating.

`check_bg_seams` measures the join against the layer's own adjacent-row delta,
because a busy layer has a lot of difference between any two rows and a smooth
one has almost none — the only meaningful question is whether the join is worse
than an ordinary row boundary.

### The near layer keeps out of the middle, and is never opaque

It draws over the field, so anything it puts in the centre is somewhere a bullet
can be invisible. That is enforced by a **window that reaches zero at the
boundary**, not by arithmetic on each spire: getting it right per spire means
every one of position, width, lean and shading halo staying inside the budget,
and the first version missed by fifty pixels. A window cannot be got wrong, and
it fades the spires into the haze on the way in, which is what they should be
doing anyway. `BG_NEAR_EDGE` in `constants` and `NEAR_EDGE` in `make_bg.py` are
the same number and `check_bg_keepout` measures the shipped PNG against it.

**And the window was not enough on its own.** The keep-out treats the outer
band as safe on the reasoning that the player is rarely dodging there, and that
reasoning is wrong. This layer is drawn *over* live danmaku, so at ninety-four
per cent opacity it did not hide scenery, it hid bullets — and it was reported
the way this class of bug is always reported: "I am taking damage and there is
nothing on screen." There was something on screen. It was behind a spire.

So `BG_NEAR_ALPHA` caps the layer at 0.42, low enough that a lit bullet reads
straight through it, and the band came down to 0.13 of the field's width. What
is lost is a little depth; what is bought is that no arrangement of art in this
layer can ever cost the player a life. **Any future layer drawn in front of the
field inherits the same rule.**

### Rock is a Voronoi diagram

**The first version of this stage was six polygon calls and one noise field per
layer, and photographed at 1:1 that is exactly what it looked like**: flat brown
masses with orange squiggles laid over them. It read as *drawn by a script*,
which next to a commissioned player sprite is the one thing scenery cannot
afford to read as.

So the rock is built the way the Wordsearch slabs are, out of layers that each
answer a different question about the surface: where the stone is jointed, what
colour this patch happens to be, what it feels like at arm's length, which edges
the light from below is catching, and how far away it is.

What makes the result read as rock rather than as noise is that the joint
network is a **Voronoi diagram**. Real basalt cools into polygonal columns, so
plates meeting three at a time at something near 120 degrees is not a
stylisation — it is what the material does, and once that is right nothing else
has to be drawn. `worley` replicates its seed points a tile above and below,
which is the whole of what makes the network periodic in y; without it every
cell along the top edge is bounded by the canvas rather than by its neighbour,
which is `shade_wrapped`'s problem one layer down.

**The scale of the plates is doing the depth work** — 210 of them on the floor,
90 in the middle distance, 55 in the foreground. The same rock at three
distances has the same plates at three apparent sizes, and that reads as
distance far more strongly than the haze does, because it survives the haze
being subtle.

**And then all of it was darkened by about forty per cent, twice.** Detail does
not earn a background any extra value budget; if anything it costs some, because
a busy surface competes for attention in a way a flat one does not, and the
thing it is competing with is the bullets. The second pass found that the value
was not in the rock at all but in the *light* on it: the fissure glow is
additive over the neighbourhood of every crack, so its alpha is effectively
multiplied by how many cracks are near a pixel, and seven of them at 1.35 lit
most of the floor between them. The stage came back from the first darkening
pass no darker at all.

### A background is not a picture

**Dark, and deliberately much darker than it wants to be.** Two thousand lit
bullets have to read against it in a fifth of a second, and every point of value
spent on the scenery is a point the bullets no longer have. The first pass of
the brimstone stage was a handsome mid-brown ravine and it was useless — an
amber bullet over it was invisible. The rock is nearly black and the only bright
thing is the lava, which is narrow, deep orange, and **never white**. White is
what a bullet's core is.

Depth is value, not detail: the further away a layer is, the closer its colour is
to the ambient air. `rim_light` catches the upward-facing edges of a silhouette
by subtracting a copy of its own mask shifted down, which is what stops a dark
mass reading as a hole in the picture.

### Szuix, and upscaling pixel art

The one commissioned asset: `tools/source/szuix_sheet.png`, six frames of 55x45,
hard-alpha pixel art, a back view of him flying. He is a back view and the boss
is a front view — if both faced the same way the fight would read as a race.

**Upscaling him is not a resize.** A LANCZOS enlargement of hard-alpha pixel art
is mush: the filter has nothing to interpolate between but a pixel and its
neighbour, so every edge becomes a four-pixel gradient and he loses his
silhouette. A NEAREST enlargement keeps the silhouette and keeps the staircase,
which against smooth bullets reads as a sprite from a different game. So he goes
up hard and comes back down soft: NEAREST to six times, one blur at that size,
then LANCZOS down to two times. The blur happens where a pixel of the original
is six pixels wide, so it softens *within* an original pixel rather than across
several — which is the difference between an anti-aliased edge and a blurred one.

**Premultiplied, and that is not a detail.** Every transparent pixel in the
sheet is *white* — it was drawn on white and the background erased, invisible
while the alpha is hard. Blur it unpremultiplied and PIL blurs the colour
channels too, so that white bleeds into every edge: the first run came out with a
pale grey halo all round him, which read as a badly cut-out sticker.

His origin is on his chest, not in the middle of the box. The frame is mostly
wing and the wings are above the body, so the box's centre sits between his
shoulders — and a hitbox floating above a character's head makes a game feel
like it is cheating even when the numbers are right.

If the commission is ever redone larger, point `SOURCE` at it and set `SCALE` to
1; the rest still applies.

### Fonts are sprites, not font assets

A `GMFont` bakes glyph metrics into a `.yy` only the IDE can produce, and
`font_add` needs the typeface installed on the player's machine.
`font_add_sprite_ext` needs neither.

**Proportional spacing measures ink, and a space has none.** A fully transparent
space frame is zero pixels wide and every space in the game vanishes. The space
glyph is drawn as a bar at alpha 1: invisible, and it still bounds the box.

**`string_height` on a sprite font returns the atlas cell, not the ink.** Every
glyph sits in a uniform box with room for an ascender and a descender that a row
of capitals never touches. `FONT_INK_RATIO` is the measured correction and
`check_font_ink_ratio` re-derives it from the PNGs.

**And the sizes in `FONTS` are points on a 1920x1080 canvas.** The first set
were points on nothing in particular: 18, 25 and 34 are sensible for a
1280-wide window, and this game is drawn at 1920 and played full screen, so
every readout in it arrived about two thirds the size it needed to be. The
score, the graze count, the attack counter and the timer all ended up as small
grey text pushed against the edge of the frame, which is what a HUD should never
be. The smallest text in the game is 26px now and everything else is a step up
from it; the number of readouts did not change.

Cinzel and Spectral, both SIL Open Font License, bundled in `tools/fonts/` with
their licences. The Microsoft faces on this machine are deliberately unused —
baking one into a shipped game is not something their licence allows.

## Traps this project has already stepped in

These are inherited from the Wordsearch project and every one of them is real.

### The `score` trap

**Never name a variable `score`, `health` or `lives`.** They are built-in
*globals* GameMaker still carries from GM8, and an instance variable of one of
those names silently splits in two: `inst.score = 5` writes an instance variable
and a bare `score` inside that object's own events reads the global. It
compiles, it runs, nothing warns, and the number on screen never moves. The run's
points are called `tally` throughout for exactly this reason, and
`check_legacy_globals` refuses the names.

### An undefined macro is a variable

GameMaker does not refuse a `#macro` that was never written — a bare identifier
it has never seen is compiled as a variable read, so it builds cleanly and throws
at run time. And a run-time throw here is a modal error box, which under
`tools/shot.py` and `tools/test.py` is not a failure but a **hang**: both run the
game under `subprocess.run(..., timeout=...)`, so what comes back is "the game
did not exit within 120s" with no hint of the cause. `check_macro_references`
keys on SHOUTING_SNAKE, which is safe because GameMaker's own built-ins are
lower-case almost without exception.

### An undefined function is also fine, and so is a call with the wrong arity

GameMaker compiles a call to a function that does not exist, and it compiles a
call that passes too few arguments — binding the missing ones to `undefined` and
throwing wherever that value is finally used, which may be a Draw event no suite
ever reaches.

**`check_call_arity` earned itself on this project's first test run.** Four
`wave_cross` calls in the stage script passed eight arguments to a function
taking nine: the *colour* was missing, so a firing function was being read as a
colour index and `global.bullet_colour[<a function>]` threw the moment a wave
died. The build was clean, and the suite that found it did so by crashing in the
middle of an unrelated assertion.

`check_unknown_functions` reads the runtime's own `fnames` list so it knows what
a built-in is. It also knows about **instance methods** — `on_boss_beaten =
function(_e) {...}` in a Create event, called bare from that object's Step — and
about function-valued locals, since every local and argument in this codebase
starts with an underscore.

`check_gml_asset_references` knows about **project functions whose names start
with an asset prefix**: `fnt_small()` returns the handle
`font_add_sprite_ext` gave back, and reading a font through an accessor is the
point.

### A bare `draw_sprite` inherits the previous frame's GUI state

`draw_sprite` draws with whatever `draw_set_colour` and `draw_set_alpha`
happen to be set to. That is fine in a routine that has just set them and a
trap everywhere else, because **the state it inherits can have been left by a
different event on the previous frame**.

The two calls that laid down the parallax ground layer were the only bare ones
in the game; every other sprite draw passes `c_white, 1`. `draw_text_outline`
returned without putting the alpha back, and the stage-name splash fades its
title text out over 34 frames -- so the GUI event ended each of those frames
with the alpha wound down toward zero, and the first thing the *next* frame's
Draw event does is lay down the ground. The world faded out under the splash,
revealing the flat air colour behind it, and snapped back to full the frame the
splash stopped drawing. It was reported as "the background momentarily fades to
nothing before snapping back, right when the first wave appears" -- which is
exactly what it was, and the first wave arriving in the middle of the splash's
fade-out is a coincidence of timing rather than a cause.

Three things had to be true at once, and all three are now fixed: the leaf that
leaked (`draw_text_outline` and `draw_text_outline_scaled` restore the alpha and
the colour, as `draw_band` beside them always did), the consumer that inherited
(`bg_draw_back` states its own colour and alpha like everything else), and the
frame that started from nowhere in particular (`obj_game`'s Draw resets the
state before the world goes down). `text_style` is the deliberate exception to
the leaf rule, because setting the state *is* what it is for -- which is why the
rule cannot simply be "no function leaves the draw state set".

**Nothing in the tooling could see it and nothing was going to.**
`tools/test.py` never draws a frame. Every scene `tools/shot.py` poses is
photographed long after the splash has gone, so all fifteen were clean. It was
found by a person watching the game start, and confirmed by photographing every
frame of the opening and plotting the red channel of the field -- which climbed
steadily for 34 frames and fell off a cliff in one.
`check_sprite_draws_are_explicit` refuses a bare `draw_sprite` now.

### A sprite drawn from a centre it does not have

`gm_new.sprite` takes an `origin`, and `spr_ui_rule` is `topleft` because it is
stretched to a width and a top-left origin makes that arithmetic obvious.
`draw_rule` then passed its *centre* straight to `draw_sprite_ext`, so every
divider in the console was drawn starting at the middle of the column and
running off the right-hand edge of the plate.

**The symptom was not "a rule looks off-centre".** It was a rule whose lozenge
sat against the console's right edge with half the ornament drawn past it, which
reads as the *panel* having a crack in it — nobody looking at it thinks about
sprite origins. It survived one screenshot because the console had four rules
all wrong in the same way, and four consistent things look deliberate.

Nothing in the tooling can see this and nothing is going to: the call is legal,
the sprite exists, and `tools/test.py` never draws a frame. The general lesson
is the one `tools/shot.py` exists for, and the specific one is that a sprite's
origin is part of its contract with every call site — so a helper that takes a
centre has to subtract the half-width itself, in the helper, once.

### A font accessor without its parentheses

Which is the trap that teaching it that opened. `fnt_small` written without `()`
is a perfectly valid expression — a reference to the function itself — and GML
hands it to `draw_set_font`, which throws:

```
draw_set_font argument 1 incorrect type (script) expecting a font
```

**Nothing in the tooling could see it.** The build is clean because the
expression is legal. `check_unknown_functions` only looks at `name(` and so
never considers it. `check_gml_asset_references` was taught that `fnt_*` names
are project functions rather than missing assets, which is correct and is
exactly what stops it reporting this. And **`tools/test.py` never draws a
frame**, so no suite reaches the line. It shipped as a crash the first time a
boss threw floating text, and a person playing the game found it.

`check_font_accessors_called` closes it. A *general* "function referenced
without being called" rule would be wrong here — passing a function by name is
ordinary in this codebase, and every wave's fire routine and every boss attack
is handed over that way. What makes the font accessors different is that they
exist only to be called, so for that one family the rule is absolute.

Its own first run reported every correct call site in the project, because
`(fnt_[a-z_]\w*)\s*(?!\s*\()` lets `\w*` backtrack until the negative lookahead
succeeds — so `fnt_small(` matches as `fnt_smal` followed by `l(`. The `\b`
that fixes it is load-bearing.

### The global that was never assigned

**`??` does not save a read of a global that does not exist.** It handles an
undefined *value*; a missing variable raises. Every global the game reads is
initialised in `obj_boot`, without exception — a default that lives at its only
call site is a default that is not there the first time.

### Saving cannot be allowed to destroy a save

`file_text_open_write` truncates its target the moment it opens, so every save
has a window in which the live file is empty and the new contents are not there
yet — and anything that kills the process inside it leaves a half-written file. A
crash does it, a force-quit does it, and so does `tools/shot.py`, which runs the
game under a timeout and kills it.

Worse, reading answers `undefined` for both "there is no file" and "the file is
corrupt", and every caller reads that as "nothing saved yet". One interrupted
write takes every stage clear with it, silently.

So a save is built beside the live file and swapped in: full temp file, delete,
rename. `save_read_json` prefers the live file and falls back to the temp — which
is the *newer* save, not a scrap, since it is only ever left behind by a rename
that did not happen. A live file that does not parse is renamed to `.bad` rather
than left where the next write would replace it.

**No suite touches a real save file.** `test_save_atomicity` proves the
primitives on a scratch file of its own, because a suite that round-tripped
through `progress_save` would overwrite the player's cleared stages with its own
state, permanently, with nothing to report it. The same split is why
`progress_record` is called from `obj_game` rather than from `boss_finish`: the
boss decides, the run records.

### The save directory's name is not the project's name

GameMaker sanitises it, and this project's name has a space in it: `screen_save`
is sandboxed into `%LOCALAPPDATA%\Bullet_Hell`, not `Bullet Hell`. A harness
using the project name verbatim looks in a directory that does not exist, finds
no screenshot, and reports the run as having failed to save one.

### The IDE will quietly undo the generators

**Keep GameMaker closed while the `make_*` scripts run.** With the project open
in the IDE, its cached copy of a sprite is written back over the generated one
whenever it decides to save — which reverts the `.yy` to the old dimensions and
the frames to the old art, with nothing on screen to say it happened.

It was found on the fonts, because they are the one family whose *size* changes
when they are regenerated: `check_font_ink_ratio` and the `W`-frame check
started failing intermittently, passing immediately after a regeneration and
failing again some minutes later with the `.yy` back at the previous point size
and every glyph blank. Sprites whose dimensions did not change would revert just
as silently and nothing would report it at all.

It happened again, worse, and the second time nothing caught it:
`spr_bul_butterfly`, `spr_bul_flame` and `spr_bul_mote` — every animated bullet
in the game — came back at their previous dimensions with all fifty-six frames
blank. The build was clean, because a sprite of the wrong size full of nothing
is a perfectly valid sprite, and the only thing that noticed was a player
saying the animated bullets had gone.

`check_font_ink_ratio` had caught the first instance purely by accident: it
looks at the ink in a `W` for a completely unrelated reason and covers three
sprites. So the rule is general now. **`check_sprites_not_blank` refuses any
sprite with no ink in its first, middle or last frame**, which is every sprite
this project ships, and it is sampled rather than exhaustive because a sprite
inked in those three and nowhere else is not a failure mode anything here
produces.

`check_project.py` is the safety net — run it after any art pass, and if a
generated sprite has reverted, regenerate and run it again. The reliable order
is: **close the IDE, run the generators, run the checks.**

### A screenshot scene the game does not know about

`tools/shot.py` passes the scene name as a **separate argument**, not fused into
the flag, so `obj_boot` can refuse one it does not know. Wordsearch fused them,
and a scene whose switch nothing read did not fail: the game opened its menu and
sat there until the tool's timeout, with nothing in the output to say the scene
simply did not exist.

## Adding things

Everything goes through `tools/gm_new.py`, which is the one place that knows
where a resource has to be registered. A script is a `.gml`, a `.yy`, a line in
`Bullet Hell.yyp` and a line in `Bullet Hell.resource_order`; a sprite adds a PNG
per frame *and a second copy under `layers/`*; an object's events live both as
`.gml` files and as entries in its own `eventList`.

**Every GUID is derived from the resource name**, never generated fresh, so
re-running a generator writes byte-identical files and produces no diff.

To add a **stage**: a `stage_def` in `stage_list()`, a script beside
`stage_ziggy` with its timeline and its boss's phase table, a provisional
`encounters` count for the console's ledger, a `bosses` list of
`{name, spawn, phases}` so its attacks can be practised, and a palette entry in
`make_bg.py`. The rack lays itself out from the list and draws every unbuilt
entry as locked, and the attack list lays itself out from `bosses`, so filling
one in changes no screen code.

To add a **bullet shape**: an entry in `SHAPES` in `make_bullets.py` and a mask
function. Re-run it and `bullet_table.gml` follows.

To add a **spell**: a row in the boss's phase table and a function of `_t`. It
appears in the attack list by itself, because that list is read off the same
table the fight is.

## Current state

Playable end to end: the stage rack, stage one from its first wave through a
midboss to Ziggy's seven attacks, the result screen, and permanent progress —
plus attack practice, which drills any one of the nine attacks on its own.
252 assertions pass; all nineteen screenshot scenes render.

Not done, in rough order of how much it is missed:

- **No audio at all.** No sound assets, no `audio_functions`. This is the
  largest single gap in how the game feels — a bullet hell without a shot sound,
  a graze tick and a spell-declaration sting is missing most of its feedback.
- **Only one stage exists.** Seven more are named on the rack and marked
  unbuilt. Everything needed to add one is listed above; what is missing is the
  bosses, and each is a phase table and a character.
- **The boss art is a placeholder** and is expected to be commissioned. Ziggy
  is drawn from primitives and reads as "a red winged imp with horns"; the
  contract a painted replacement has to keep is in `tools/make_boss.py` — size,
  frame count, origin, and facing the player.
- **The sprite fonts have no kerning, and Cinzel's `Q` is where it shows.**
  `font_add_sprite_ext` with `prop = true` spaces every glyph by its own ink,
  so a `Q` — whose tail sweeps out to the right of its bowl — takes an advance
  wide enough to hold the tail and leaves a gap where the next letter should
  tuck under it. At `fnt_ui` on the title screen that gap is a few pixels and
  reads as nothing; at `fnt_head` it reads as a word break, and the first
  screenshot of the practice panel came back saying `Q UIT TO TITLE`. That row
  says `BACK TO TITLE` now, which is a dodge rather than a fix. The fix is
  kerning pairs in `make_fonts.py` — a table of overhanging pairs baked into
  the glyph advances — and nothing in the tooling can see the defect, because
  every glyph is present, inked and correctly sized.
- **Nothing is balanced against a human.** Every number in `ziggy_phases`,
  every fire rate, `PLAYER_SPD` and the whole of `constants` was reasoned about
  rather than played. The suites prove the fight *runs*; none of them can say
  whether it is fun, and the honest next step is somebody playing it a dozen
  times. **The speed pass made this more urgent, not less**: holding traversal
  time fixed across a change of field size is a defensible rule and it is still
  a rule applied to numbers nobody has played.
- **The bordered field has not been played either.** 1360x992 is what is left
  once the console has its column and the frame has its 44-pixel margin, and it
  is wide enough to keep the fast, horizontal game this is meant to be. Whether
  it is the right size is a question for somebody holding the keyboard; every
  coordinate that depends on it goes through `FIELD_*`, so changing it is four
  numbers in `constants`, the matching two in `tools/art_common.py`, and a
  re-run of `make_bg.py`.
- **The console has not been played either, and it is where the next honest
  gain is.** It was designed against fifteen screenshots, which is the right
  tool for legibility and says nothing about whether the *best* row earns its
  place over, say, a life-in-reserve count, or whether the control legend is
  charming on the tenth run or tiresome on the second.
- **The eye card is still drawn from the placeholder boss art**, so the one
  piece of ceremony that is a close-up of a face is a close-up of primitives.
  It improves for free when the commission lands.
- **Waves are not graded, and the ledger is half-built because of it.** A mark
  per encounter is in and the boss's attacks earn theirs for real; the stage's
  own waves do not, because a wave is a line in a `{at, fn}` timeline rather
  than a thing with a beginning, an end and an outcome. Giving it those is the
  next piece, and it is a change to `stage_functions` rather than to
  `rank_functions` — `rank_note` is already the seam. Until then
  `stage_def.encounters` is a hand-written count so the console can draw the
  sockets, and it will be wrong the moment a timeline is edited.
- **Nothing consumes the standing yet, and the labels are recorded for
  something that does not exist.** Every mark carries the name of what earned
  it and the console does not draw it: the result screen is the natural home
  for the itemised list and the stage's final grade, and `progress_record`
  would want to keep the best standing beside the best score.
- **The grading thresholds are guesses.** `rank_for_attack` is four branches
  picked by reasoning, and the 0.35 that separates gold from adamant has never
  been played. It is the same honest gap as everything else in `constants`.
- **`fire_spray` is the only random helper and it is used once.** A pattern made
  of noise is a pattern nobody can learn, which is why. Worth keeping an eye on.
- **The rest of ph3's shot surface, none of it load-bearing yet.** What is here
  covers the A- and B-series, the `AddPattern` chain, `AddShot`, a delete frame,
  spell resistance and laser grazing. What is not: a per-laser intersection
  width and dead zone (`SetIntersectionWidth`, `SetInvalidLength` — the kill
  width is a third of the drawn width for every laser in the game, which is a
  rule and not a setting); penetration and shot-erasing on the *player's* shots,
  which carry damage and nothing else; a per-bullet blend type; a query that
  answers with every bullet in a circle (`GetShotIdInCircleA1`), where the only
  thing that walks the pool by position is the sweep that clears it; and a
  settable auto-delete clip — `CULL_MARGIN` is one number for the whole game, so
  **a pattern that legitimately leaves the field and comes back cannot be
  written**, which is the one of these that would be missed first.
- **Nothing in the stage uses most of the new bullet kinds.** The arc, the wake,
  the timed fade and the mid-flight graphic change are all engine and all
  tested, and Ziggy is written the way he always was — a boss balanced against
  nobody is not made better by being rebalanced against nobody with more
  verbs in it. They are photographed by the `motion` scene rather than by a
  fight, which is where they should stay until somebody has played one.
- **No options screen**: no volume, no window mode, no key remapping, no way to
  clear progress.
- **The three fodder behaviours are `wave_line` and `wave_cross` and nothing
  else.** A stage that wanted a spiral entry, a formation that rotates, or
  anything arriving from the bottom would need a third.
- **`bullet_clear_circle`'s item conversion counts the bullets it has already
  swept**, so the every-seventh rule is by sweep order rather than by position.
  It looks fine and is not what the constant claims.
- **Two thousand bullets cost 4ms a frame under the VM.** Not a problem, and the
  fix if it ever becomes one is written down under "Bullets are structs".
