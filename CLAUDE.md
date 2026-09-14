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

**Every attack in the game except `Demon Sealing Hex` is a placeholder.** In
their finished versions, all spells are meant to be at the Hex's level of
artistry and complexity. The simple fans, rings and spirals in Ziggy's and
Velka's tables will be replaced -- they are there so the stages have something
to play through, not as the design. The point is for this to be worth playing
rather than another basic bullet hell, outshone by Touhou and the Danmakufu
fangames.

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
| `tools/check_project.py` | The project files are sound: `.yy` JSON, event lists matching `.gml` on disk, resources registered, every SHOUTING_IDENTIFIER a `#macro` that exists, no call with the wrong argument count, no legacy built-in globals, no sprite too big for its texture page, **every background layer tiling seamlessly**, the near layer keeping out of the field, no bare `draw_sprite` inheriting the draw state, **the hedgerow still covering the horizon it hides**, **the far chamber painted at the size it is hung at**, and **the rings eating the player's shots before the enemies are offered them**. |
| `tools/shot.py` | What it **looks like**: builds, runs with `-shot <scene>`, poses a real game state, saves a screenshot. A posed player can be made `untouchable` — see below. Forty-one scenes; `--all` does the lot, and `--burst 0,20,40` photographs one scene at several frames in a single launch and tiles them into a sheet. |

**`shot.py` is not a nicety, and in this genre it is the most important of the
four.** A bullet pattern that is arithmetically perfect and illegible is a bug,
and no assertion can see it. It renders thirty-four scenes and **fails on a game
error even when a screenshot appeared** — `obj_shot` calls `screen_save` from
its Step event and `game_end()` lets the current frame finish, so a throw in the
Draw event that follows happens *after* the file is on disk. The first crash
this project shipped did exactly that, and an early version of the harness
reported fifteen successes over it.

That check spent a long stretch **written down and never called**: `GAME_ERROR`
was compiled, commented at length, and matched against nothing, so the tool was
back to grading a crashed scene by whether it had photographed itself before
dying. A guard nobody invokes is indistinguishable from no guard, and the
comment above it is what makes that hard to notice — it reads exactly like a
guard that works.

**A posed player does not dodge, so it cannot be asked to survive.**
`player.untouchable` is the harness's flag and nothing in play ever sets it.
It is not a convenience: a hit sweeps a 190-pixel circle of bullets off the
field, which is right in play and means a posed player being hit *takes a bite
out of the pattern being photographed*. Every picture of `Demon Sealing Hex`
taken at less than full life had a hole in the ward whose entire claim is where
its gaps are, and nothing said so — the seal is redrawn twice a cycle, so the
evidence was gone by the next movement. What finally reported it was a scene
running long enough for the fourth hit to kill the player outright. It is
distinct from `iframe` rather than expressed with it, because `iframe`
*flickers*, and a screenshot of a half-transparent Szuix is a screenshot of a
state nobody is posing for.

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
- **The name hangs under the tube's left-hand end and is small**, tracked
  rather than large — see the note on tracking below. It was centred over the
  tube for a pass, which worked only while the boss held station well below the
  line: the caption could own the middle because nothing else was ever there.
  Raising the boss takes that away, so the name went back to the left end and
  the timer to the right, which is where the genre has always put them.

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
rule the boundary was built to keep. **The bar is pinned to the top of the
field and every word on the line hangs below it** — first the caster's name at
the left end and the timer at the right, then the spell's name under the
caster's. It was the other way round for a pass, with the type above the tube,
which spent fifty-six pixels of the top of the playfield on captions before
reaching the one part of this line that is read at a glance mid-dodge. A bar is
what wants to be pinned to an edge; type can hang off it. What makes it affordable is that the whole
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
nothing opaque. Whether the capture is still live goes at the *other end* of
the line rather than beside the name, so that losing it does not shift the name
— which would read as the spell having changed.

**It stacks under the caster's name at the same left margin rather than being
centred**, for the reason the caster's name moved there: the middle of this
line is the boss's face now. Set one under the other, the two read as one
block — who is casting, and what they are casting — which is what they are.

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

**It is borderless fullscreen, not exclusive.** A plain `window_set_fullscreen`
on Windows is exclusive, and Windows drops an exclusive app out of fullscreen
whenever something else takes focus -- the screenshot overlay does, and so does
alt-tab -- and the runner never goes back in. It was reported as the game
leaving full screen every time a screenshot was taken. `obj_boot` calls
`window_enable_borderless_fullscreen(true)` before the switch, which makes it
a borderless window the size of the display with no mode to lose.

`option_windows_allow_fullscreen_switching` is on, which is what gives the
player F4 back -- a game that seizes the display with no way out is worse than
a small window. Aspect is kept rather than stretched, so a display that is not
16:9 letterboxes.

**Neither harness takes the display, and the way that is arranged had to be
turned inside out.** It was `option_windows_start_fullscreen`, with `obj_boot`
calling `window_set_fullscreen(false)` on any run started by a tool. Both
halves of that are right about pixels and the second is too late about
everything else: **the option is read by the runner before a line of GML
executes**, so a harness run had already changed the display mode, raised a
borderless window over every other window on the desktop and taken the
foreground by the time `obj_boot` got a say. Giving the pixels back a frame
later does not give any of that back.

It was reported as the game window being forced to the front and blocking
whatever was being worked on -- and the tell was that the Wordsearch project
has the same two tools, run the same way, and has never once done it. The
whole of the difference was that one option.

So the option is **off** and the *player* asks for the display: `obj_boot`
calls `window_set_fullscreen(true)` when no harness flag was passed. The test
that used to say "a tool drops out of full screen" now says "only the game
enters it", which is the same rule with the exception removed rather than
inverted.

**And the window is opened minimised, from the Python side.** Not taking the
display is not the same as not appearing: a run launched from a terminal the
user is looking at inherits the right to raise a window and take the
foreground, and a windowed game flashing up twenty-two times over for `--all`
is the same complaint one notch quieter. `build.run_game` is the one place
either tool starts the game, and it passes a `STARTUPINFO` asking Windows for
`SW_SHOWMINNOACTIVE`. Nothing is given up: `screen_save` reads the game's own
surface and never the desktop, and a `-shot` run launched this way was measured
to save the same 1864x1048 picture with the same content.

**`window_set_visible(false)` is the version of this that does not work**, and
it was tried first because for `-selftest` it looks free. GameMaker stops
stepping a window it is not showing, so `room_test` never ran, nothing reached
stdout, and what came back was `tools/test.py`'s 180-second timeout -- the
exact failure mode the note about modal boxes is about, produced this time by
the fix. Minimising from outside the process is a different thing and the
runner is happy with it.

The price of all of it is that a screenshot comes back at 1864x1048, because a
1920x1080 window does not fit on a 1920x1080 desktop. That is 97% of design
size, everything in the picture scales together, and **nothing in the tooling
measures a screenshot** -- `check_bg_keepout` and its neighbours measure the
PNGs the generators write, not these. `tools/shot.py --fullscreen` passes
`-fullscreen` through *and* shows the window, for the times a photographed
pixel really does have to be a design pixel.

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
`fire_ring_stack`, `fire_fan_stack`, `fire_spray`. `fire` returns the bullet so a caller can set a
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

### Rings: the first object that is neither a bullet nor an enemy

**A bullet is something to dodge and an enemy is something to shoot. A ring is
neither.** It is furniture a boss puts down, it cannot be destroyed, and what
it changes is *where the player is allowed to stand and where they are allowed
to shoot from*. `ring_functions` is the pool; stage three is the fight built out
of it.

**Every ring is the same size and there is no way to make one that is
not.** `RING_R` is a macro and the struct has no radius field, which is the
difference between a rule and a convention: an attack cannot ask for a bigger
ring, so six on the field are six of the same object and the player learns one
shape once. The number is set against the *bullets* -- `BSHAPE_SPHERE` is the
largest thing the game fires at 108 pixels across and a ring is 167, moderately
bigger and nothing like the 400-pixel gates the first pass drew. Those read as
architecture rather than as the bands he wears: two of them walled the field,
and three concentric ones produced a boss who could not be shot at all from
outside. `test_rings` asserts both the constancy and the ratio to the largest
bullet, because both are the kind of number that drifts the moment somebody
wants one dramatic ring.

**It blocks along its band and not across its middle, and that is the whole
design.** An indestructible shield in front of a boss is the defect `BossMove`
exists to fix -- an attack that cannot be answered, only waited out. A *ring*
has a hole in it, so the answer is always there and it is a positional one:
line up through the middle, or go round. The player is never told to stop
shooting; they are told where to stand to keep shooting. `test_rings` asserts
the hole as hard as it asserts the band, because a ring that quietly blocked
across its disc would look identical and would only show up as a player slowly
concluding the fight is unfair.

Four verbs, and every one is a field on the struct:

- **Block.** Player shots crossing the metal are absorbed. Enemy bullets are
  not, because they are his -- and the bomb's seals are not either, which is
  what stops a walled boss making the one panic button in the game useless.
- **Kill.** A ring can be *charged*, after a visible warning, and then its band
  hurts. `ring_is_hot` has to test `warn` as well as `hot`, because
  `ring_charge` sets both at once: the first version killed for the whole of
  the build-up it was drawing to say it had not started. `test_rings` found it
  on its first run, and nothing else could have -- the picture, the cue and the
  timing were all correct.
- **Arc.** Two rings strung with a line of current: a lethal segment between two
  *moving* points, which the player reads off the objects at its ends rather
  than off the wall itself. The drawn bolt jitters, and the jitter is bounded by
  `ring_arc_half` so it never strays outside the band it kills in -- at
  twenty-six pixels off a nine-pixel kill line it was a bolt that visibly missed
  and killed anyway.
- **Fire.** A ring carries an `act`, called every frame exactly as a boss attack
  is, so it is a boss attack one level down. `ring_fire_rim` fires from the
  *metal* rather than from the centre (fired from the middle it looks identical
  for one frame and wrong for ever after, because the delay marks appear inside
  the hole) and `ring_beam` anchors a following beam at the centre, because the
  hole is what a ring is for.

**Blocking is swept, and the ordering is the mechanic.** A player shot travels
`PSHOT_SPD` against metal a fifth as thick, so a point test would miss two in
three and the ring would read as leaking -- the same defect `bullet_hit_index`
exists for, and the same fix. And `ring_block_shots` has to run *before*
`enemy_take_shots`: a shot absorbed by a ring must be gone before the boss
behind it is offered the pool. Run the other way round, a ring blocks nothing
while looking exactly as though it does -- the shots still spark on it, the
ring is still drawn, and the only difference is a health bar going down at the
normal rate. `check_rings_block_before_enemies` is the guard, and it was tested
against the wrong order before being believed.

**A ring is stamped with a serial and references are validated against it.** A
struct is reused out of the pool, so an attack that remembers three rings and
reads them two seconds later may be reading whatever took those slots.
`Demon Sealing Hex`'s seals answer the same trap by re-picking every frame,
which cannot work here: an attack that spawned three rings means *those* three.
`ring_valid` is the answer, and the case it actually catches is an arc whose far
end has been swept -- a lethal line drawn to a ring that no longer exists.

**A ring is drawn before the bullets, which is what makes an opaque object this
size affordable.** The near parallax layer is capped at `BG_NEAR_ALPHA` and kept
out of the middle of the screen because it draws *over* live danmaku; a ring
draws under all of it, so no arrangement of rings can hide a bullet. What they
can hide is the boss, which is the point.

**The sprite's proportion is the collision's proportion.** `RING_BAND_FRAC` is
half the metal's thickness as a fraction of the radius, it is quoted in
`tools/make_rings.py`, and because the sprite is scaled uniformly the band that
is drawn and the band that blocks a shot are the same shape by construction --
the property `capsule_half` buys the meters and `laser_draw_curve` buys a curve.

**And the ring is one sprite with its colour baked in**, which is the opposite
of what everything else here does. A ring is not a shape being lit, it is a
*marking*: the reference sheet draws the same band on Mika's tail, his biceps
and his wrists, and that pattern is the character. What the spell's colour gets
instead is the *charge*: the same sprite drawn again additively, so the chasing
blazes in the attack's hue and the metal underneath does not move. The marking
is the conductor, which is the whole idea of the fight.

**The marking is an interlace, not a row of links, and drawing it as links is
what made the first one read as a string of beads.** The reference is one
continuous ribbon that crosses itself: a lens opens between two crossings,
closes to a point, and the next opens on the other side of the line, with a
knot on every crossing. So what `make_rings.py` draws is literally two waves --
`+A cos` and `-A cos` -- and the lenses are what falls out between them, which
gives every link the **pointed** ends an ellipse cannot. Four hairlines rather
than two, as well: a line at each edge, a gap, then a second line bounding the
channel, so the chain reads as inlaid into a cuff instead of printed on a
strip.

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
reach the bullets and turn them into score on the way. What that wave is drawn
as, and what follows it, is below.

**A hit scatters shards.** Touhou drops your power on death; this is the same
idea turned round. Losing a quarter of the bar puts a handful of recoverable
points on the field, so the moment after a hit is a scramble rather than only a
loss. They are gold, not red — being hit must not hand back the health it just
took. And the bullets on top of the player are cleared, or the invulnerability
runs out inside the same wall and the player dies twice to one mistake.

### The shot is blue fire, and it took the colour out of the tint

**It was reported as looking like pointed missiles rather than fireballs**, and
two things made it one. The sprite was a single smooth teardrop with a white
stripe down the middle — a symmetric taper with no internal structure, which is
what a missile is — and it was drawn `draw_sprite_ext(..., COL_SZUIX_LIT)`.
**A tint multiplies**, so the white core the sprite was drawn with came out the
same flat periwinkle as its rim: one colour, one shape, no fire anywhere.

So `make_flame` draws it the way a fire shader does. A soft envelope — a ball
at the front, a taper behind — with turbulence **subtracted** from it: where the
envelope is thick the noise only roughens the edge, and toward the back, where
it is thin and the noise is allowed to eat more, it comes apart into separate
licks. The turbulence scrolls backward along the axis by exactly one period
over the eight frames, so the loop is seamless and the tongues peel off the
ball the way they would off anything moving through air.

**The colour is baked and it is drawn `c_white`**, which is the whole of what a
tint could not do: violet at the torn edges, azure through the body, white only
at the heart. Each shot starts at its own phase of the loop — a counter, not
`random`, since two barrels firing on the same frame at the same phase would
burn in lockstep and read as one shape copied. And a flame now sits at each
muzzle while the shot is held, so the stream is something he is *doing* rather
than something appearing above his head.

The same generator at twice the size is `spr_fx_wisp`, which is what the bomb's
seals are made of and what rides the rim of its sweep. Drawn rather than scaled
up: a flame enlarged is a blur with a flame's outline, and the licks are the
whole of what says fire.

### The special: a sigil that takes, and seals that give it back

**It was a flash and a ring, and it was reported as puny and underwhelming.**
A quarter of the meter bought a white wash, a shockwave and about half a second
of anything happening, which is a poor trade for the one resource the player
spends deliberately. It is four beats over two and a half seconds now, and the
mechanics behind three of them are new.

1. **The cast, on frame zero.** A violet wash, a shake, a hard local flash, a
   shockwave past the sweep's own radius, and his close-up. Everything that
   *answers the key* lands here — the same constraint `cue_bomb` is written
   to, which opens on its transient because a bomb heard a quarter of a second
   late is a bomb pressed twice.
2. **The sigil, which is the sweep.** `spr_fx_sigil` grows from the cast point
   to `BOMB_CLEAR_R` in step with the clearing circle, so its rim is exactly
   where bullets are being erased: three layers turning at three rates, rings
   in his violet, script in his cyan, the emblem at the heart. Thirty-two
   tongues of `spr_fx_wisp` ride the rim, so the wave erasing the pattern is
   made of the same fire his shot is.
3. **The theft.** `bullet_clear_circle` takes an optional per-bullet callback,
   and the bomb passes one: every second bullet it erases leaves a mote that
   *accelerates* into the sigil's heart, which fills as they arrive. Bound to
   the cast point rather than to the player, because that is where the sweep
   is anchored and a player is free to fly out of his own circle.
4. **The seals.** `BOMB_SEALS` wisps leave the heart at `BOMB_SEAL_AT` in a
   pinwheel, spread while they turn, then hunt the nearest thing they are
   allowed to hurt and burst on it — sweeping what they fly through and a
   circle of what they land in. Fantasy Seal's shape on a caster who steals
   magic: what goes back at the boss is what was just taken off it.

**The seals do damage, and that is a rule change rather than a picture.** The
special used to hurt nothing at all, and a wisp that visibly strikes a boss and
leaves its bar where it was reads as broken. `BOMB_SEAL_DMG` is ten apiece —
six together are two seconds of the shot held on target — and they pass through
a boss in ceremony exactly as shots do, which `enemy_take_seals` enforces
beside `enemy_take_shots` rather than inside the player. It is one constant,
and setting it to zero gives back the special that damaged nothing.

**Every seal is spent before the grace is.** `BOMB_SEAL_AT + BOMB_SEAL_LIFE` is
under `BOMB_INVULN`, because a seal still in the air once the player is
vulnerable again is a bomb that goes on fighting for them after it has stopped
protecting them. `test_bomb_seals` asserts the arithmetic rather than trusting
it, since it stops being true the moment somebody lengthens either number.

**The wake clears and does not pay.** `bullet_clear_circle` drops a shard for
the first bullet of every call, so a per-frame sweep asking for items would
mint one a frame per seal — five hundred over one bomb. The bursts pay instead.

**A seal's target is chosen again every frame rather than remembered.** An
enemy's struct is reused once it dies, so a stored reference is a reference to
whatever took that slot next; re-picking costs six distance checks against a
handful of enemies and cannot go stale.

### One hit from death

**He beats.** At `HP_PER_HIT` or less a red glow runs round his own silhouette
twice a beat — `spr_szuix_aura`, his outline grown and blurred, drawn
additively over the sprite, so the warning is made of pixels that are already
his and can neither hide a bullet nor be mistaken for one. The console's life
meter already pulses on the same threshold; this is that fact where the player
is actually looking.

**It was too bright the first time, and the fix was the onset rather than only
the alpha.** At a peak of 0.74 and a four-frame rise it was reported as
flashing distractingly — and a hard onset in the corner of the eye is the same
signal a bullet arriving makes, which is the one thing a warning must not
imitate. It swells over about ten frames at a third of that alpha now.

### The grace dial

**How long the player has left was a number the game never told anybody.** The
flicker says *that* he is safe and looks identical on its first frame and its
last, so the moment it ran out arrived without warning — which for the three
seconds after a hit is when they are most likely to be somewhere they could not
otherwise be. `player_draw_grace` draws Wordsearch's combo ring round him
instead: a faint circle for the whole grace and a bright arc for what is left,
sweeping clockwise back to noon, the head carrying the bloom because the head
is the part that moves. It tightens as it empties and flickers toward the
colour of being hit inside `GRACE_URGENT`.

It covers both kinds of grace, and the two **overlap rather than add** —
`player_grace_left` is the longer of `iframe` and `bomb_t`, and `grace_max` is
what the fraction is *of*, so a bomb cast inside a hit's grace refills the dial
rather than overfilling it. It is drawn under the danmaku with him, because it
is information about him and must not become one more bright thing between the
player and a bullet.

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

## The bar

`Demon Sealing Hex` is the reference for what a finished spell looks like --
see its own section under the drafting table for what went into it. New spells
are written on the drafting table (`stage_drafts`) and move to their caster
when they are done, which is how the Hex came to be Velka's.

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

**A boss holds station in the top quarter, and it used to hold it lower.**
`BOSS_HOME_Y` was `FIELD_Y0 + 320`, which with a drift of 74 and half of a
250-pixel sprite put the foot of the boss past the middle of the field on the
low half of its wander — a boss leaning over the player for the whole fight.
Reported as oppressive, and it was: a boss belongs at the top of the arena and
the player owns everything under it.

What was keeping it down was *type* rather than the bar. The name was centred
over the middle of the line and the timer sat beside it, so the station had to
clear a block fifty-six pixels deep standing exactly where the boss wanted to
be. Moving both to the two ends of the bar gave the middle of the line back
and the station came up with it, to `FIELD_Y0 + 250`. The one thing it may not
fly through is the fourteen pixels of tube, and `test_hud_layout` asserts that
and that the foot of the sprite stays out of the player's half.

**A boss drifts, and that is a default rather than a rule.** One that stood
still would fire every aimed pattern from the same pixel and the player would
learn the pixel rather than the pattern, so the wander is right for nearly
everything — and it stops being right the moment the player *cannot chase it*.

`Demon Sealing Hex` is what found that. It draws a ward round wherever the
player is standing and pins them inside it for seconds at a time, and a boss
that wandered 430 pixels off during those seconds was a boss nobody could
shoot: an attack whose whole idea is confinement quietly became one that could
only ever end on its clock. It was not too hard. It was **unanswerable**, which
is a different defect, and no assertion about the pattern could have seen it
because nothing about the pattern was wrong.

So movement is a column in the attack table — `move`, a `BossMove` — and
`boss_move` dispatches on it. **It belongs to the attack rather than to the
boss**, because the same caster wants different answers within one fight: a
wide non-spell wants the wander, and the spell after it may not.

- **`Drift`** is the lissajous wander, and it is what a phase that names
  nothing still gets. Every attack in the game was written before the column
  existed, so the read is `_p[$ "move"] ?? BossMove.Drift` — a bare `.move`
  would not merely default wrongly, it would *raise*, which is the same trap
  the `spell_bg` read one function over is about.
- **`Track`** trends toward the player's column while still wandering on top
  of it. For an attack that traps the player: the boss comes to them because
  they cannot come to it.
- **`Fixed`** takes the station and holds it, for an attack whose shape is
  measured from its own origin. `Seed & Bloom` is the case — the only draft
  with nothing aimed in it, so a moving origin buys it nothing and costs it its
  symmetry, smearing one rosette into a comma.

**The station walks at a capped speed rather than easing, and that is the whole
of what "loose" means.** A proportional ease is *fastest when the player is
furthest away*, which is a boss that runs with you; a cap at `BOSS_TRACK_SPD` —
a third of `PLAYER_SPD`, and within a whisker of how fast the drift's own
wander point already travels — is a boss that arrives eventually. A player who
crosses the field genuinely gets out from under it and keeps that for the
seconds it takes to walk back.

**And it still wanders while it tracks**, or the fix reintroduces the thing
drifting exists to prevent: a boss parked exactly overhead fires every aimed
pattern straight down. `BOSS_TRACK_SWAY` is about ten degrees either way
against a player near the bottom of the field. Only the horizontal axis tracks;
a boss that tracked in y would sink toward the player and off its own station,
which is a fight moving rather than a boss moving.

**The sway is squashed against the edge of the field rather than the station
being held off it.** Holding the station back by a whole sway would leave a
cornered player with the boss 240 pixels away and unhittable, which is the
exact situation tracking was added for. Clamped this way the wander flattens as
the boss reaches the side and it still passes over the corner.

**Nothing had to be added to make a `Fixed` attack open on its station.** The
pauses move for `next_phase` and the attack moves for `phase`, so a boss takes
up position during the pause and the declaration before an attack rather than
sliding into place across the first second of its own pattern. The ceremony was
already exactly the breathing room repositioning wants.

**The tracked column is dragged along behind the boss whenever anything else is
moving it**, so an attack that starts tracking picks up from where the boss
actually is. Without that, an attack following a tracking one opens by lurching
across the field to wherever that one left the column — which is the same shape
of bug as `run_clear_field`'s note, state inherited from the last thing that
used it.

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

**And it is centred on the caster's station, which it was not.** It drew on
`FIELD_CY` — two hundred and fifty pixels below where any boss in this game
ever stands — so what it actually put on screen was a circle of power with
nobody in it and a caster hovering above the rim. It went unnoticed until a
boss whose entire fight is rings was put in front of it, at which point it was
the first thing anybody said. The *station* rather than the live position,
deliberately: a boss drifts four hundred pixels either way, and a background
that slid with him would be a room following its occupant about.

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

### The drafting table

**A pattern is an idea long before it is a character**, and there was nowhere
to put one. Adding an attack meant adding it to a boss, and adding a boss means
a phase table, a name, a title, a sprite, a background and a place on the rack
— so the cheapest way to find out whether a pattern was any fun was to bolt it
onto Ziggy, play it out of context, and take it off again. That disturbs a
fight that is already tuned *and* judges the new pattern against a boss it was
never written for.

So there is one more card on the rack, it is not a stage, and every attack
filed under it is one nobody has claimed. It is `scripts/stage_drafts` and
**it is written as content rather than as a debug menu**, on the same terms the
practice mode itself is: a draft played through the game's own console,
ceremony, background and grading is a draft somebody has actually seen, where a
draft played through a diagnostic view has to be judged twice.

**Its whole surface is a row in `draft_list`** — a name, a hue, a clock, a
function of `_t`, and optionally a `move`. Everything else is derived:

- **A name is what makes it a spell.** Named, it gets the banner, the eye card,
  the wash and a taller notch; unnamed, it is a non-spell and opens at once.
  Writing `kind` and `bg` out as well would be saying one thing three times and
  getting it wrong once.
- **Every draft owns an equal share of the bar**, computed from how many there
  are. A hand-written `hp_end` column would mean the second thing you do after
  having an idea is arithmetic, and an idea inserted in the middle would
  silently reprice every one below it.
- **The boss's health is `DRAFT_SLOT_HP` times the number of drafts**, so one
  slot is worth the same however many there are. An attack tuned last week must
  not get shorter because somebody added one underneath it. The number is
  Ziggy's opening non-spell, near enough, so a draft takes about as long to
  break as the first attack in the game — a draft that could only ever end on
  its clock would leave "was that beatable" unanswered, which is half of what
  is being asked.

**Ziggy's sprite stands in for the caster**, because a placeholder that is
obviously a placeholder beats a new one nobody drew. What is *not* borrowed is
his hue or his arena: the aura is violet, which nothing on his stage fires, and
the background is `SPELLBG_SIGIL` rather than the forge. That fallback exists
for a caster with no place of its own, which is exactly what a draft is — and a
draft arriving in his colours in his forge would read as an attack of his that
had gone wrong.

**`build` is `undefined`, so the table is practice-only**, and that is the one
decision worth arguing. A one-line timeline putting the boss on the field would
work and is tempting. But a run of a whole *stage* is the path that reaches
`progress_record`, and the one thing a scratchpad must never be able to do is
write to somebody's save. `id` is empty for the same reason `practice_new`'s
is; the two locks agree, and Z on the card opens the attack list rather than
refusing — there is nothing else it could mean, and a refusal would be teaching
a rule about a card that exists to be opened.

**`rack_list` is the rack and `stage_list` is still the roster.** The drafting
table goes in the first and not the second, because `stage_list`'s docstring
says "every stage in the game" and this is not one — no waves, no place, no
clear to earn, no line in the save. A screen is allowed to show a superset of
what exists; the count under the title still counts stages, so it reads 8 and
not 9. The card appears only while `draft_list` has something in it, so
shipping is deleting rows rather than remembering to hide a menu.

**The first five are seed content and are meant to be thrown away.** What
they are for, beyond giving the card something to hold on its first day, is
that between them they use every verb the engine has and the stage does not
— the Cartesian model, a split, a wake, a lifetime, a mid-flight change of
graphic and a homing modifier. All of those were listed under "engine, tested,
and never played", and a verb nobody has felt is a verb nobody can judge. The
first row is deliberately the plainest thing in the file, because starting an
idea should be renaming a copy.

### Demon Sealing Hex, and what a composed attack costs

**It is Velka's now, and it was the sixth draft.** It was written on the
drafting table before anybody had said whose it was, and it moved to her fight
the way that table says an attack should: the function and its helpers into
`stage_grove`, a row in `velka_phases` with a real `hp_end`, and nothing else.
It is her last spell, because it is the one attack she has that was designed.
It keeps `DRAFT_SLOT_HP` of the bar, which is what it was played against, and
every attack before it keeps the health it had — her total grew by the Hex's
share rather than five attacks being squeezed to fit a sixth. The ward cues did
not have to be renamed, which is the argument `audio_functions` made for naming
them after the figure. `test_drafts` asserts it is on her table and off the
drafting one, because an attack in two places is two copies that will be tuned
apart.

**It is not a verb demonstration, and it was the first thing on the drafting
table that had to be designed rather than exercised.** A ward is drawn
round wherever the player is standing, they are shot at inside it, and it comes
apart — first thrown outward, then, on a second ward with gaps in it, pulled
back in to a point and detonated. Four movements on a twelve-second loop, and
the shape on screen means something for the whole of it rather than for the
second a bullet takes to cross.

**A pattern with a shape needs one thing this engine had no habit for:
somewhere to remember.** Every other attack in the game is a pure function of
`_t`, and that is the right default. This one is not, because a seal takes
fifty-four frames to inscribe and the player moves during them: read their
position every frame and the pentagram smears into a comet. It is one `static`
struct inside the attack function, which is the smallest scope that works — a
global would have to be declared in `obj_boot` and would outlive a draft whose
whole point is being deleted, and a field bolted onto the boss or onto the
phase table would be writing state into somebody else's data.

Three techniques in it are worth writing down, because each is something the
engine could always do and nothing had asked it to:

- **A rigid rotation is a speed and a turn rate that agree.** Give a bullet a
  tangent heading, a speed proportional to its distance from a centre, and one
  turn rate shared by every bullet in the figure, and the whole figure revolves
  as one object. Nothing has to store the centre or the angle, and the
  pentagram is still a pentagram a thousand frames later. Get the speed and the
  turn out of step and it opens into a spiral over the three seconds it stands
  for — which is why `test_hex_seal` measures the radius twice rather than
  once, and why a screenshot of the frame it closes on could not have caught
  it.
- **Traces of different lengths finish together by taking shares, not steps.**
  Seven pens draw at once — five arms of 563 pixels and two rings of 1860 and
  2237 — and a pen laying down one rune a frame would have the arms finished
  four times over before the rings were half round. Each lays down the runes
  whose index falls in *this frame's share of its own length*, so the arms
  crawl, the rings race, and every one of them puts its last rune down on the
  same frame.
- **A synchronised collapse is arithmetic, and it is the only part of this that
  is.** Runes 120 and 356 pixels out have to reach the middle on the same frame
  or what lands is a smear instead of a point, so the speed *and* the
  acceleration are proportional to the distance and scaled to sum to exactly
  it. That makes the contraction self-similar: the seal keeps its shape all the
  way down. The sum is `T*c0 + ca*T*(T+1)/2` rather than `(T-1)/2` because
  `bullet_step` applies the acceleration before it moves, which is a fencepost
  with a visible consequence — get it wrong and the whole seal overshoots the
  point it is collapsing onto.

**And a bullet cannot be found again, which is the constraint that shapes all
of it.** There is no query that answers "the bullets of this seal" and there
should not be, so every rune is told its entire future at the moment it is
placed: stop turning, then move, then either scatter or collapse, then either
burst or go out. That is four or five `BQ` entries against a ceiling of eight,
and it is the first pattern in the game to use the queue as anything but a
convenience.

**Three things about it were wrong and only a screenshot said so.** The red
ward's arms were spaced to leave an eleven-pixel corridor, which is a real
crossing arithmetically and *invisible* — a bead is drawn about as wide as the
gap, so at that spacing the arms overlap into rope and the player is being
asked to take the gap on faith. The two ring layers were thirty-four pixels
apart and merged into one thick band, so the counter-rotating pair that is the
whole motif read as a single circle. And the fans fired into the red ward were
ember, which is a few steps from crimson, so the one thing on the field that
had to be dodged right now was the hardest thing on it to find; they are white
in both movements now, because the seal is the room and the fan is the threat
and the colour should say which is which before the shape does.

**They were not, and the paragraph saying they were is what made that hard to
see.** `HEX_COL_FAN` read `BCOL_VIOLET` under a docstring explaining at length
why it had to be white — so against the *blue* ward the volleys were doing
precisely what the ember ones did against the red, with the argument against it
printed directly above the line. It is the same shape as the `GAME_ERROR`
guard: a comment that describes a fix is the hardest possible place to notice
the fix is not there. Nothing in the tooling could see it either — every hue in
the table is a legal argument, the build is clean, and `test_hex_seal` picks
the volleys out by shape. It was found by sampling the pixels of a screenshot.

**And the ring did not close, which is the one worth keeping.** The ward turns
while it is being inscribed, and a bead only starts turning when it goes live —
so the bead the ring comes back to has moved off the top since it was placed,
and what that leaves is one gap at the seam four times the width of every other
one, frozen in at the moment the last bead goes live, in a ward whose entire
claim is that it has no gap in it. Every number in the placement is uniform;
the *placing* is what is not. The fix is to lay the figure out in the ward's
own turning frame — add back the rotation each bead is going to miss, so the
pen runs slightly ahead of the figure and every bead turns into place behind
it. It was reported off a screenshot, and the assertion that now holds it down
had to be taught to wait `HEX_SEAL_DELAY` frames before measuring, because the
fix makes the ring *deliberately* not round on the frame it finishes.

**The ward is drawn in beads rather than in stones, and that was a legibility
call rather than a scale one.** The first version used `BSHAPE_RUNE`: fifty-odd
pixels of picture, two hundred of them, each big enough to be looked at
individually — which is the drawing of a seal rather than a seal. Halving the
bead doubles the count in the same figure and the figure is what the eye gets
instead of the pieces. The pellet is one step too far; a ward made of those
stops reading as an object at all, which matters here more than anywhere
because this is the only pattern in the game the player is asked to look *at*
rather than through.

**The broken ward goes everywhere, and it does not tidy itself.** Thrown
outward along their own radii the beads keep the figure's shape all the way off
the screen, which looks like the ward being lifted — and worse, leaves the room
it was enclosing as the one place in the field nothing is travelling through,
so a player who spent three seconds learning to stand in the middle of it is
rewarded with three more seconds of standing in the middle of it. Scattered
across the whole circle, half of it comes back through that room. **The
scattering is a hash of the bead's index, not `fire_spray`** — what makes noise
unlearnable is that it differs every attempt, not that it is irregular, and a
hash gives the same two hundred and seventy directions on the tenth attempt as
on the first.

They also carry no lifetime. An earlier pass expired them so the red ward was
certain to be gone before the blue one closed; it bought tidiness and paid for
it in the only currency this genre has, because a bullet that winks out
mid-field is one the player learnt to respect and was then told not to bother
with. `CULL_MARGIN` removes them like everything else, and a cap of two and a
half — under half what the stage's own waves travel at — is what makes that
affordable and what makes the debris something that can be outrun rather than a
second attack.

**The boss goes quiet before the ward moves.** Both breaks are things the
*ward* does rather than things the boss visibly does, so both need the player
looking at the ward; firing into the last frames before one means they are
reading a volley when the wall starts moving and find out about the collapse
from the health bar. It is the only way the blue half's question can be asked
honestly, too — the player is being told to leave, and being told while under
fire is being told to do two things at once.

**The two halves need different amounts of it, and one number could only ever
be right for one of them.** It was one number, and it was right for the red
half: that break is a *scatter*, the player is already standing in the safest
place there is, and what eighty frames of quiet buys them is a look at the ward
before it comes loose. The blue half's hold is not for looking. It is the
window in which the player has to find a gap, cross the ring and be outside it
— up to three hundred and fifty pixels through a wall with corridors thirty
wide — and eighty frames of that made the attack's honest answer "already be
leaving when the last volley is fired", which is asking somebody to act on a
cue that has not been given. `HEX_HOLD_RED` is eighty and `HEX_HOLD_BLUE` is a
hundred and twenty, with `HEX_BLUE_FAN` grown by the same amount so this is
time added rather than volleys taken away — both halves still fire four.

**And the collapse opens too slowly to be a lurch, which is the other half of
the same complaint.** `HEX_IMPLODE_RAMP` is the trade: every bead has to cross
its own distance in exactly `HEX_IMPLODE` frames, so a gentler start has to be
paid for by a steeper finish, and the number is how much. At twelve the outer
ring left at eight tenths of a pixel a frame and had covered nineteen in the
first twelve — which is a ward that has *plainly begun to move*, on a movement
whose only cue is the ward beginning to move. A player reading it correctly
still learnt about the collapse from the collapse. At twenty-six it leaves at a
quarter of a pixel a frame and has covered under seven after twelve, so the
first thing that happens is the figure going soft exactly as the scatter's
does. `HEX_IMPLODE` grew from 66 to 108 alongside it, so the finish did not
have to steepen to pay for the start: it arrives at six and a third rather than
at ten, and the whole gap between the last volley and the detonation went from
two and a half seconds to four.

**The detonation is seven kinds of debris and not one.** It was a hundred
pellets at one of three speeds, and what that draws is three expanding rings —
an arithmetically fine burst that reads as a *firework*. Reported, accurately,
as pathetic. The first attempt at fixing it had cut the *count*, which was
treating the symptom: three solid rings are a wall, and fewer of them is a
smaller wall rather than a detonation.

`hex_debris` is the fix and it is one table: a ball, a six-pointed star, a
rune, a crystal, an orb, a mote and a pellet, all cyan, **graded so the heavy
pieces are the slow ones**. That grading is doing three jobs at once. It reads
as mass, which is what makes a cloud look like something breaking rather than
something being fired. It sorts the burst along the radius by itself, so the
gaps in it are gaps something has *left* rather than gaps somebody authored.
And it pays out by distance: the player who answered the blue half and got out
is reached by the sparks, and the one still standing in the middle gets
everything — which is the one thing that half of the attack is asking for.

Everything else about it comes off three independent hashes of the rune's own
index — which way it throws, how hard, and what it throws — so the burst is
irregular, has no hole in it, and is the *same* burst on the tenth attempt as
on the first. **`frac` keeps its sign in GML**, so the hash had to be folded
into `[0, 1)`: `hex_spray_dir` never noticed, because a negative fraction of a
turn is the same heading as its complement, but an index into a table is not an
angle and half the runes would have come off as the table's first row. Which is
one shape at one speed, which is the shell the whole change exists to remove.

**The size is carried by the effects and the danger by the debris**, and
separating those is what lets the burst read as enormous at a count that is
still dodgeable — three rings, a flash and fifty sparks, none of which can hurt
anybody. Adding bullets to make it feel bigger is the move that produced three
solid rings the first time round.

**And a fan is a volley, which is `fire_ring_stack`'s missing sibling.** One
fan is a wall that arrives all at once and is answered with one sidestep;
`fire_fan_stack` sends the same fan at three speeds, so it arrives as three
arcs a beat apart and the answer is a move and then two more. Each row is
turned half a step off the one in front, because three rows down identical
headings put their gaps on the same radial lines and the whole volley has one
answer again.

**The attack list is measured before it is drawn, and that came out of this.**
Its plate was a constant, and the constant was the height of Ziggy's eleven
attacks; the drafts got the same plate with the difference left as a hole. It
is sized to its rows now, with the old height as the ceiling, and the two hint
lines follow it up — pinned to the foot of the screen they only moved the hole
from inside the plate to underneath it.


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

**He is the tutorial boss, and all seven attacks are placeholders.** He stays
the tutorial and gets cooler attacks later -- see "The bar". What is there now:
the three non-spells are one idea at three speeds, the spells each add one
thing (a spiral, a splitting bullet, a telegraphed beam) and the last combines
them. They are wide and slow, `Cinder Waltz` has nothing aimed in it, and only
`No Mere Pawn` presses the player.

## Stage two: the Hollow Grove

Velka — a fox who keeps a wood's dead, in a bone mask under antlers. **The
fight is mostly a placeholder and the background is the work.** Five plain
attacks built out of helpers that already existed, so that there is something
to look at the wood *through*, and then `Demon Sealing Hex` as her last spell —
the one attack she has that was designed, moved from the drafting table. When
she is written for real it is the five placeholder rows of `velka_phases` that
get replaced and nothing else on the screen has to change.

### A corridor, not a parallax stack

**Stage one is a floor and this is a corridor, and the difference is the
projection rather than the art.** The brimstone stage is three sprites the size
of the field sliding down the screen, which is exactly right for a pavement
seen from above: everything in it is the same distance away, so everything in
it moves at one rate and the depth is bought with parallax between three flat
plates.

A forest cannot be drawn that way. The player is flying *through* it at head
height, so a tree fifty metres off and a tree five metres off are not two
layers, they are one object at two depths — and the whole of what makes the
shot read is that a tree grows, slides outward, and leaves past the edge of the
frame, accelerating the entire time. That is one divide per prop and it cannot
be got from a parallax rate.

`scripts/bg_corridor` is the projection and the prop pool and knows nothing
about forests; `scripts/bg_grove` is what is arranged in it. The camera sits at
the origin looking down +z, `CORRIDOR_CAM_H` above a ground plane, and
everything comes off one quotient — `k = FOCAL / z`, the screen pixels one
world unit covers at depth z. A prop's position, its scale, how fast it crosses
the frame and how much air is in front of it are all that number, which is why
`corridor_k` is the one projection function and not four.

`bg_new` carries a `kind`, and `bg_step`, `bg_draw_back` and `bg_draw_front`
dispatch on it. Three entry points is the whole of what the two kinds share.

**There is a ring buffer, and the reason is depth order.** `bg_draw_embers`
derives its motes from the clock — a phase and a rate, and where a mote is this
frame is `frac` of the two — which is the right shape and does not work here.
The corridor accelerates half way through the stage, so a position derived from
`t` would teleport every prop on the frame the speed changed; that half is
fixable by deriving from an accumulated distance instead. The other half is
not: these props *overlap*, so they have to be drawn far to near, and a set of
positions derived by `frac` is sorted only up to a rotation that moves every
frame. So the order is kept — props live in a ring, `head` is the nearest, and
one that passes the camera is pushed to the back and becomes the farthest.

**The slots are evenly spaced in z and jittered inside their own slot**, and
the jitter is the ring's rather than the content's. Perfectly even slots keep
the order true for ever and read as a picket fence; the jitter breaks that and
is bounded by half a slot precisely so it cannot reorder anything. It was
applied inside the content's recycle hook first, where every lap added another
one — so over a couple of minutes the props wandered out of their slots, then
out of each other's order, and the depth sorting the whole corridor rests on
quietly stopped being true. `test_corridor` flies four thousand frames and
checks the order every thirty-seven of them, because that is a claim no
screenshot can make: a tree drawn in the wrong depth order looks like a tree.

**Every ring is drawn in one merged depth-sorted pass, not one pass per
ring.** Rings are separate because their depths are — the trees run out to the
far plane, the trunks to half of it, the ferns to less, and giving them one
shared span would either crowd the near ground with trees or spread the ferns
over four times the depth they belong in. For three passes that turned into
four sequential draw loops, which means **every trunk in the wood was drawn
over every tree in it whatever their depths**. Reported as a big tree fading in
*in front of* a small tree that was already closer, which is exactly what it
was. Depth order is a property of the frame, not of a ring. Each ring is
already sorted, so `corridor_merge_step` is a k-way merge — one linear pass, no
comparisons beyond the heads, output array allocated once. `test_corridor`
asserts the merged walk is monotonic in z and covers every prop.

**The canopy bands do not move on their own, and that took two goes.** They
carried a share of the drift, which was a pan; that became a bounded sway,
which was still the only thing left in the frame going sideways under its own
clock — and in a stage where the camera steers, that reads as a clash rather
than as wind. Reported as the branches moving left and right at random. What
says wind overhead is the boughs *ring*: props that come at the lens and sweep
out of the top corners, which is what a canopy does to somebody flying under
it. The bands behind them are the far canopy, and a far canopy slides for the
same reason a far wall of wood does — none.

`check_bands_are_rooted` holds it: a band's x must be `grove_rooted_x`, or a
parameter passed through from a checked caller, and the drift is legal only
inside `grove_draw_mist`. **Its first version carried a literal backspace where
it meant a word boundary** — an escape that compiled, ran against three
deliberate violations and called all three clean. Which is the `GAME_ERROR`
lesson again, and the only thing that separates a guard from a comment is
watching it fail.

**The canopy is a ring too, and it is the tree sprite upside down.** A canopy
drawn as a band sliding sideways is the one piece of this stage that could not
be right: in a corridor nothing distant slides, it grows. Reported as flat
transparent branches moving horizontally in front of the moon — a *sideways*
motion the camera is not making, which the eye reads as a sheet of acetate
being pulled across the picture. Boughs are ordinary props with their anchor
*above* the camera instead of on the ground and their sprite hung downward from
it, so they come at the lens and sweep off the top of the frame as the trunks
sweep off the sides. Because they are props they sort correctly against
everything else for free. What is left of the bands behind them is a slow sway,
which is the wind, and the far treeline is opaque now: a wall of wood does not
slide and you cannot see through it.

**A bough is a tree with its trunk taken off, and it keeps to the sides.**
Both halves were found in front of the moon. Hung upside down, the tree sprite
ends in its root — a ruled line that the right way up is buried in a mound of
litter and upside down is a trunk sawn off flat in the middle of the sky — so
`bough_from` in `make_grove.py` fades the root and the foot of the trunk out
and the crown hangs out of darkness. And the boughs were spread right across
the corridor, on the reasoning that the place a bough is most wanted is
directly ahead; a bough directly ahead and far away hangs straight down the
middle of the moon, and one did, in the frame that was reported as a tangle.
`GROVE_BOUGH_IN` is measured from a bough's inner edge exactly as
`GROVE_TRUNK_HALF` is, and it has to hold at the *back* of the ring, because
that is where a bough is level with the moon — `test_corridor` does the
arithmetic and then walks the ring. Kept to the sides, the boughs frame the
moon as an arch and sweep up and out of the top corners as they come.

**Every ring has to be stepped, and there is a suite that counts them.** The
trunks were built, placed, depth-sorted, lit, given ivy and drawn for several
passes with nothing advancing them — so the nearest and largest things in the
wood held station while the entire world went past, and what reached a player
was "those are static images lazily slapped on the background". They were.
Nothing about a prop's *drawing* says whether it moves; the only thing that
does is whether something calls `corridor_ring_step` on its ring, and a ring
nobody steps looks exactly like a ring somebody does until the second frame.

`test_corridor` walks the background struct, finds everything carrying a
`props` array, and refuses one that has not recycled anything after a lap.
Named individually the assertion would have passed the day it was written and
gone stale the day a fourth ring was added — which is the shape of the bug it
exists for.

**And a ring's far plane is not a free choice: it has to be far enough back
that the *air* does the arriving.** A prop's alpha is zero at its own ring's
far plane, so nothing ever appears out of nothing — and that is only half of
arriving unseen. Its *colour* has to already be the fog's too, or what fades up
is a shape in its own colour at a distance where a thing that size can still be
made out. The trunks recycled at 2800 units, where more than half the air is
still clear, so what faded up was a four-hundred-pixel shape: reported twice as
big trees popping in in front of smaller ones that were further back. Sorting
them correctly did not help, because they genuinely *were* in front — the fault
was the distance they arrived at, not the order they were drawn in.
`CORRIDOR_ARRIVE_HAZE` is the budget and `test_corridor` measures every ring
against it, which is what stops the next ring being the one that forgot.

**A prop fades in at *its* far plane, not at the corridor's.** `corridor_haze`
is measured against `CORRIDOR_Z_FAR`, the back of the whole world; a ring that
only reaches a third of the way out there was recycling its props into a place
where the air was still two thirds clear, so every fern and every trunk snapped
into existence at about seventy per cent opacity. It was reported as bad pop-in
on the grass, which is exactly what it was. `corridor_ring_fade` is a property
of the ring, so a ring added later cannot be the one that forgot.

**Everything a prop becomes is a hash of its lap, never `random`.** A wood
whose trees stand somewhere else on the second attempt is a wood nobody can
build a memory of — the same argument `hex_spray_dir` makes one file over, and
`corridor_hash` folds `frac`'s sign for the same reason `hex_debris` had to.

**And the corridor has a back wall.** The inverse of a perspective divide has
no far end: a row one pixel under the horizon reports a quarter of a million
units and a row *on* it reports infinity, so every reader of that number has to
cope with a depth no prop can ever have — and one of them did not. What it drew
was a thin dark red line across the field, a couple of pixels under the
horizon, in a stage that had not turned and would not for another two minutes:
the blood wavefront is parked *beyond* the far plane to mean "nothing has
happened yet", and the only thing further away than the parked wavefront was
the ground under the horizon. It read as a rendering artefact because that is
what it was, and no assertion was going to see it — every number involved was
inside its own range. `corridor_depth_at` clamps at `CORRIDOR_Z_FAR` now.

### What is in the picture

Ten layers at eight rates, which is the argument the forge is built on: each
of them is cheap and the depth is in there being ten.

| | |
|---|---|
| the sky | a vertical ramp, and stars that go out |
| the moon | on the horizon, centred, eclipsed once |
| the canopy | two bands of bough closing the top of the frame |
| the treeline | the far wall of wood, standing on uneven ground |
| the scrub | two rows of hedgerow along the foot of it |
| the floor | leaf litter, roots and moss, laid down the corridor |
| the mist | drifting bands, ground fog and dappled moonlight |
| the trees | forty billboards, hung with charms |
| the verge | seventy-eight clumps of undergrowth, both sides, all depths |
| the trunks | twenty-two more, taller than the screen, close to the path |

**Everything is drawn as luminance and tinted at draw time** — the same
decision `make_ui.py` records, load-bearing twice over here. The grove is lit
by one moon and half way through the stage that moon turns to blood, so every
tree, charm, fern and mist bank has to change colour together; a painted-in hue
would mean a second copy of the entire stage. Each solid thing ships as a body
and a **rim** — the moonward edge, drawn additively — because a dark mass with
no rim is a hole in the picture, and splitting them lets the body be night-blue
while the light on it is bone-white and then crimson without redrawing
anything.

**The far wood is a row of whole trees, and it used to be a lace.** It sits
directly behind the moon, so it is the one part of the wood that is always
looked at, and it was the messiest thing in it: thirty trunks and forty-six
separate branch systems, each rising from the ground independently. The
trunks tapered to a third of their width and simply stopped in mid-air, and
the branches were a second, unrelated thicket laid over the top — reported,
in front of the moon, as tangled and piled on rather than designed, with
posts visibly cut off half way up the disc. `_treeline_draw` draws a *tree*
twenty-two times now: a trunk that carries its width up to a fork, and two or
three limbs out of the fork that carry on from it, dividing twice and
tapering to nothing. **Nothing ends bluntly, because everything is the
continuation of something.** One tree to a stratum of the tile, so the moon
shows *between* trees rather than through a mesh, half the wobble, because a
branch that curves is a branch and one that zig-zags is a scribble, and a
window on the band's top edge so a tall crown fades rather than being sliced.

**The canopy got the same treatment for the same reason.** Its heavy boughs
were vertical wedges ending at a third of their width half way down the band —
sawn off in mid-air — and tapering them to a point made them a row of black
icicles, which is a different wrong. They are `limb`s now, leaving the top
edge at thirty-five to sixty-five degrees off vertical and forking twice,
because a bough overhead reaches *sideways* out of the dark. Thirty twigs that
hung to within a few rows of the band's bottom edge — which is a line across
the lower third of the moon — are fifteen that stop half way, and the fade is
eased over the lower half instead of dropping in the last tenth: a fade a few
rows long is a cut.

**The trunks are the layer that makes it a forest rather than a clearing.** The
wood was six frames of whole tree at every distance and it was reported as
looking like a pond: at any depth where a *whole* tree fits inside the frame
nothing in the picture is near, so however many of them there are the camera is
always across a field from all of them. A trunk is a fragment — it leaves the
top of its own frame, so the tree it belongs to is always bigger than the
screen — and it passes the camera rather than standing in front of it.
`GROVE_TRUNK_HALF` is measured from a trunk's *inner edge* rather than its
centre, which is the difference between framing the field and walling it: at
the first number the two nearest trunks met in the middle of the screen and the
picture was a pair of black slabs with a keyhole between them.

**Eight silhouettes and two numbers, because a frame drawn at one size is a
frame the eye learns in four seconds.** Four near-identical heavy columns were
reported as the same tree pasted over and over, and they were: the generator
varied a lean and a width, and every frame came out a slightly different post.
What tells two trunks apart across a screen is the silhouette — whether it
forks, whether it leans and recovers, whether it is squat or slender, where its
boughs leave — so `TRUNK_KINDS` is a list of those and the randomness fills
each one in. On top of that every prop carries its own `scale` and `aspect`, so
the same trunk comes past squat and then tall and narrow; eight frames become
effectively eight hundred for two multiplies at draw time.

**Which is why a trunk is placed by its inner edge rather than by its
middle.** `GROVE_TRUNK_HALF` is the clearance the *nearest edge* of a trunk
keeps from the centre line and `grove_make_trunk` adds the prop's own
half-width to it. Measured from the middle, the widest trunk would stand
exactly where the narrowest does and wall the field — the bug that constant was
already rewritten once to fix, waiting to come back the moment the widths
stopped being uniform. `test_corridor` walks the ring and asserts the
clearance, rather than a comment claiming it.

**A billboard has a flat bottom and the ground does not.** A trunk is drawn as
a fragment that leaves the top of its own frame, so its sprite necessarily ends
in a ruled horizontal line at the base — and at the size the near ones are
drawn, that line is the give-away: it reads as a cardboard cutout standing on a
floor rather than as something growing out of it. There is no fix for it in the
art, because the cut is the sprite's own edge. What fixes it is what fixes it
in a real wood: litter and roots bank up around a trunk, so the join is never a
line anywhere. `grove_draw_mound` is one soft dark bank at the foot of every
prop whose foot is on screen.

**And it is drawn as a strip, not as a bloom, which is worth writing down.**
The first version used `spr_fx_bloom` — the obvious choice, and wrong for a
reason that is easy to miss: `soft_glow` has a falloff of 2.9, so its alpha is
above four fifths only within seven per cent of its radius. That is exactly
right for a light and useless as a fill. Drawn at the width of a trunk it
covered the cut at about eight per cent opacity and the ruled line was still
plainly there. A triangle strip with per-vertex alpha — opaque along the ground
line, dissolving downward, tapering to nothing at both ends — is the shape that
was wanted, and it is one primitive.

**The palette is saturated, and that took a correction.** The first pass built
it by taking the brimstone rule — scenery stays dark, because every point of
value spent on it is a point the bullets no longer have — and applying it to
the *chroma* as well. What came back was reported as "all black and white".
Value and saturation are not the same budget: a deep teal at the same value as
a neutral grey costs the danmaku exactly nothing and is the difference between
a wood at night and a photocopy of one. It is the finding the console records
about gilt on indigo, one layer further in. The ivy is the one thing out here
that is a *hue* rather than a temperature, and it is why the stage is not two
colours.

**The moon is held at about half of white, and that is a fairness number.** It
sits behind the middle of the playfield, where the boss stands and the danmaku
is thickest, and the first pass of it was a pale disc at nearly full value —
which photographed as the brightest thing on the screen with bullets crossing
it. It carries its reading in maria and craters instead. A moon that has to be
a lamp to be a moon is a moon this stage cannot have.

**The charms are the one place allowed a second hue and they are bigger than
they look like they should be.** A hex at a seventh of a tree's height is
arithmetically a reasonable ornament and photographs as a two-pixel green
spark; the tree it hangs in is four hundred pixels tall at the distance anybody
looks at it. Where each one hangs is not a guess: `make_grove.py` works out
every tree's branch tips as it draws them and writes them into
`scripts/grove_table`, exactly as `bullet_table` carries a bullet's hit radius
beside the sprite it belongs to.

### The floor, which took three goes

**A ground plane shaded per screen row can draw nothing but horizontal bands**,
because in this projection a row *is* a depth. However carefully those bands
are tuned, what they draw is a set of stripes across the screen, and what the
eye makes of that is water. It was reported twice — first as a pond, then as a
flat expanse with props tossed on it — and both were right: there was nothing
on the floor that had a *position*.

So the floor is one tile of leaf litter, roots, moss and twigs, **periodic in
both axes**, laid down the corridor in bands. `fbm_field` wraps in y, which is
all a scrolling parallax layer needs; a floor tiled sideways as well needs the
first column repeated too, and it has to be the *grid* that is made periodic
rather than the upsampled field — which is the finding that function's own
docstring already records about cross-fading.

Three things about the laying-down are worth keeping:

- **The bands are a constant screen height, not a constant world depth.** A
  band is textured affinely — one `draw_sprite_part` stretched between two
  screen rows — where the perspective it is standing in wants the texture to
  compress as one over the depth. Over twenty-six pixels that error is under a
  pixel; over a band of fixed world depth, which is a quarter of the screen
  tall by the time it comes close, the near half of the tile is stretched to
  nearly twice its length and the texture visibly swims.
- **There is a mip chain and it is cross-faded.** A tile at one scale has to be
  faded out well before the vanishing point, and what that leaves is a hard
  horizontal line with a textured floor below it and nothing above. The tile is
  periodic, so laying it out at twice the world size is legal and halves how
  much of it a band has to show; doing that in doubling steps and blending two
  adjacent steps is a mip map by hand. The blend is the part that matters,
  because a *step* in texture scale across the floor is the same visible line
  the fade was there to remove.
- **The ground at infinity is the sky, because that is what a horizon is.**
  Aerial perspective removes most of the join on its own, and "most" is not
  enough for a line the full width of the field. Fading the far floor toward
  the same colour the sky is drawn in makes the two meet by construction rather
  than by tuning.

The colour ramp under all of it is the *air*, not the ground, so the floor is
drawn opaque where it is drawn at all — laid over at half alpha it was a floor
seen through half a screen of fog, which photographed as a flat green expanse
with a suggestion of something under it. And the tint is the floor's *brightest*
value rather than its average, because the texture carries its own range and
multiplying it by a mid colour halves the contrast it was drawn to have.

**And the ground flickered, which was a Nyquist failure.** The colour bands
under the texture are periodic in depth: one is many rows wide under the camera
and a fraction of a row near the horizon, and a pattern sampled below its own
rate does not draw finely, it draws a *coarse* pattern that crawls as the
camera moves. `corridor_draw_ground` hands each row how many world units it
covers, so anything periodic can fade itself out before it starts to alias.
There is no texture to mip there, so the fade lives in the function that makes
the pattern.

### The horizon, which was a ruled line

**A ruled horizontal line at the vanishing point is the single most
generated-looking thing a corridor can have**, and this one had one: the
ground's top row is a straight edge the full width of the field and the far
wood was a band sprite drawn at one y, which is a wood standing on a spirit
level. It was reported as the horizon looking unnaturally flat, and the fix is
not more raggedness in the art — the art is already ragged. It is that the
*ground the wood stands on* is not level either, and that something has to be
drawn over the ground rather than under it.

Three things do it and they are three different distances:

- **The far wood's crown rides up and down.** `corridor_draw_band_wave` draws
  a band as one textured triangle strip per tile, each column of vertices
  dropped by `corridor_band_wave` of its position along the tile. Two
  properties of the wave are load-bearing and neither is obvious. **Downward only**, because the ground is painted over the band's
  foot, so a slice *lifted* shows a strip of sky underneath a wood — every
  term is a raised cosine, which is in `[0, 1]` by construction rather than by
  being clamped, since a clamp would hide a sign error rather than make one
  impossible. And **periodic in the tile**, or the displacement puts a step at
  every seam, which is the defect `fbm_field`'s `wrap_y` exists to prevent one
  dimension over. The two copies get different amplitudes and seeds, so the
  near wood and the far wood disagree about where the hills are.
- **A hedgerow stands on the line itself**, drawn *over* the floor, which is
  the only way a foot can be visible at all. It **crosses the foot of the
  moon** and only dips where the path runs into it — see below for the
  version that parted there instead.

  **It also used to pan left for ever, and that is what a rooted band may
  never do.** The treeline, the hedgerow and the canopy each carried a share
  of `drift`, an accumulator that only grows, on the reasoning that a band
  pinned at one x reads as a photograph stuck to the screen. That reasoning
  was written for a camera that did not move, and it bought the look with a
  lie: a wall of wood travelling sideways in a stage flying straight down a
  corridor — the same "sideways motion the camera is not making" this file
  already records about the canopy and the treeline, left standing on the one
  band nobody had photographed. It was reported on the hedgerow, which is the
  worst place for it: that band exists to hide the join between the ground
  and the far wood, so it lies across the middle of the frame under the moon.
  At flying speed it walked a hundred pixels left every twenty seconds
  whatever the player did, and the steering could offset forty-eight of that
  only while the player stayed against a wall.

  **The bands are the layer where a yaw reads at all** — everything nearer
  has its own rushing motion to hide it — so a drift on them is a drift over
  the top of the only legible evidence that the camera turned. `grove_rooted_x`
  is the rule: a rooted band's sideways position is the camera's and nothing
  else. The mist keeps its drift, because fog is the one thing out there that
  genuinely travels, and the canopy trades its pan for a **sway**, because an
  oscillation is wind where a pan is the camera sliding. Measured over half a
  minute of flight with the player held still, a rooted band now moves 23px —
  which is the meander, and all of it — and 61px wall to wall on the steering.
- **The verge props stand along it in their own right**, being ordinary
  billboards at the far end of a ring that reaches the far plane.

**The hedgerow took three goes and the first two are the useful part.** The
first was the treeline sprite reused at a third of its size — and that sprite
is a lace of two-pixel twigs whose alpha is ramped away down its own height,
because it is drawn as a *distance* with the moon behind it. Laid small over a
lit floor the same art is a smear, and it was reported as transparent
messiness thrown at the problem. A hedgerow is a mass with no light through
it.

The second was a filled silhouette computed at draw time — a row of
overlapping lobes in one triangle strip. That is solid, which was the
complaint answered, and it was still the wrong answer: a row of arcs is a row
of arcs, and **a new layer means new art**, which is how it was put. So
`make_scrub` draws one: brambles and canes over a mass of overlapping domes,
with the odd sapling standing out of the top so the crown is broken rather
than scalloped. It is authored at **twice the field's width**, because it is
drawn at a fraction of its height — a hedge is sixty pixels, not three hundred
— and a band scaled to a third is a band that repeats three times across the
field, which is a rhythm the eye finds in about two seconds.

**And the one thing it may never do is fall below the line it is covering.**
That is a property of the hedge's *thinnest* stretch rather than of its
average, and it is the sum of four numbers living in three files: how tall the
band is drawn, how much of it stands above the horizon, how far the wave and
the dip push it back down, and where the art's own crown bottoms out. Every one
of them was individually reasonable and nothing was adding them up. The mat was
seventy scattered ellipses topping out anywhere between 0.64 and 0.83 of the
canvas, so between two of them the hedge was a sixth of its own height, the
crown there landed *below* the horizon, and the ruled join showed straight
through the layer built to hide it — reported as the border peeking out from
behind the hedgerow.

**The measurement is what said the art was at fault and not the tuning**: with
the wave and the dip both set to zero, the worst stretch still cleared the line
by one pixel. So the mat got a floor — more ellipses, wider, over a shorter
height range, so it is many times covered everywhere and its crown undulates
between 0.34 and 0.50 instead of falling away — and the wave and the dip came
down with it, because 26px and 22% on a band 116px tall is forty-four per cent
of it spent pushing the crown down, which leaves an art budget no hedge can be
drawn inside. `check_scrub_covers_horizon` does the addition against the
shipped PNG and was tested against both failures before being believed.

**It had always been broken, and what made it visible was fixing something
else.** The band used to slide, so the bare patch swept across the frame a few
pixels a second; parked to the camera it sits at one x and reads as a ruled
edge. A defect that travels is a defect nobody reports — every screenshot in
`tools/_preview` caught it too, and it looked like scenery. That is the same
shape as the note on `check_sprites_not_blank` sampling three frames: the thing
that hid the fault was the thing that made it move.

Its **crown is hard and its foot dissolves**, which is one alpha ramp doing
two jobs: a crown against the sky has to be hard or it is fog, and a foot on
the litter has to not be, or it is the cardboard-cutout edge
`grove_draw_mound` exists to remove. And it ships with a rim like everything
else, because this is the one opaque layer sitting on the horizon and a hedge
in front of a moonlit sky with no lit edge is a black bar across the picture.

**And then it could not be found on the screen, for three separate reasons at
once.** It was reported as "I'm not seeing any hedgerow here, just a bunch of
weird glitchy 1-pixel-wide vertical lines in front of the moon", and every
word of that was a different bug.

- **It parted at the moon.** The first version parted for the path wider than
  the moon is round, on the reasoning that undergrowth over the stage's
  centrepiece would be losing it. What that left was the most-looked-at
  stretch of horizon in the stage, under the brightest thing in the picture,
  ruled dead straight — the complaint the layer was built for. And it was the
  *only* place the hedge could have been seen: everywhere else it is dark
  against dark, and against the moon it is a silhouette. It dips there now
  (`GROVE_SCRUB_DIP`), and `test_corridor` holds the dip short of a parting.
- **Its crown was flat.** Fifty-odd narrow domes that mostly agreed about
  their height, with two-pixel canes over them: ninety-four per cent solid in
  its body and nearly level across its top, so across the moon it read as a
  straight edge with sticks on it. `make_scrub` builds it out of bushes now —
  clusters of lobes with a leafy fringe, spaced along the band and each a
  different height — because a hedge at a distance is read off the rhythm of
  its crowns.
- **The vertical lines were the band drawing, and they had nothing to do
  with the hedge.** The wave was first drawn as forty-eight
  `draw_sprite_part_ext` slices a tile, each a pixel wider than its share on
  the reasoning that a seam between two slices is a hairline of whatever is
  behind it. That holds for an opaque sprite and is exactly wrong for a
  translucent one: the extra pixel is a column the band is **blended twice**
  in, so every slice boundary of the mist bank at 17 per cent became a line at
  31. The far wood's foot is ramped translucent too, and both lie across the
  bottom of the moon, which is where a doubled column shows most. A strip has
  neither overlap nor gap, because neighbouring columns share their vertices.

**The strip then drew nothing recognisable, and that one is a trap worth
keeping.** Fed `sprite_get_uvs` — which answers in texture-*page* space and is
the obvious thing to hand a primitive — it drew the top-left patch of each
sprite stretched across the whole band: the treeline became a few blocky
trunks and the hedge became half a dozen tall bumps with flat-cut feet. **In
this runtime a primitive textured with `sprite_get_texture` reads its
coordinates in the sprite's own 0-to-1 space**, not the page's. It was pinned
down by drawing one quad both ways beside `draw_sprite_ext` — which is also
how "the hedge is invisible" was separated from "the hedge is covered": the
hedge drawn *last*, in magenta, was still only bumps. The trim in
`sprite_get_uvs` is still used, for placement; its first four entries are not.

`test_band_strip` is the guard, and **it is the one suite that draws**. It
renders a band at rest and the same sprite through `draw_sprite_ext` to two
surfaces from `obj_selftest`'s Create event and compares them a pixel at a
time: eleven of seven hundred samples differ from filtering, and with the page
coordinates put back, four hundred and nine do. Nothing else could have caught
it — `tools/test.py` never draws a *frame*, and the bug was arithmetically
spotless.

**One more, found on the way: the mist said "additive without exception" and
was neither.** Nothing in `grove_draw_mist` set a blend mode, so both passes
inherited `bm_normal` — which in the front pass meant a translucent sheet laid
over live danmaku, the one thing `grove_draw_front`'s rule forbids. It is the
`HEX_COL_FAN` trap again: a comment that describes the fix is the hardest
place to notice the fix is not there. The front pass is additive now. The
back pass stays normal on purpose and now says so, because that bank lies
across the moon, and added to a moon held at half of white for the bullets'
sake it would push the moon back toward the lamp it is not allowed to be.

### The edges of the frame, which went bare

**A fair coin over forty trees produces a run of six on one side about as
often as not**, and what a run of six looks like from inside a corridor is one
edge of the picture empty for two seconds. It was reported as the far left and
far right going bare depending on spawn luck. The wood was never too sparse.
It was *clumped*, which is what randomness does and what nobody ever means by
it.

`grove_side` places props in **stratified pairs** — two consecutive laps are
one prop on each side, and which of the two goes left is the hash. A run is
bounded at two by construction, both sides get exactly half of everything, and
there is nothing to predict, because the order within a pair is noise and how
far out and how deep each one stands is a hash of its own. It is the argument
`fire_fan_stack` makes about turning each row half a step: regular where the
regularity cannot be seen, random where it can.

**A weaker version shipped for one build and the measurement is why it did not
stay.** It alternated and let about one lap in three repeat, on the reasoning
that strict alternation would be a picket fence — and over four hundred laps
it produced runs of *ten*, barely better than the coin it replaced.
`corridor_hash` is the classic one-line shader hash, built for fractional
coordinates and visibly correlated along consecutive integers: whole stretches
of laps fall the same side of a threshold, so the "occasional" repeat arrives
in clumps. A stratum cannot have that failure, because it never asks the hash
whether to balance — only which way round. `test_corridor` measures the
longest run in the ring as it is actually drawn and refuses more than two; a
coin flip measures six there and nine to twelve over four hundred laps.

**And the verge is the layer that fills the space whatever the trees do.**
Seventy-eight clumps of undergrowth, from the edge of the path out past where
the trees stop, all the way back to the far plane, biased outward by a square
root because a uniform draw puts as many clumps in the first two hundred units
as in the last two thousand and the first two hundred are off the side of the
frame within a second.

**It is its own art, and that took saying twice.** The first version drew the
existing fern at two and a half times its size, which was reported as the same
sprite thrown at things over and over — a layer built out of another layer's
art scaled up is a layer the eye reads as the same thing twice, however many
of them there are. Which is the `TRUNK_KINDS` finding again. So `make_brush`
draws six *plants* rather than six seeds of one: a bramble mound, a bracken
clump, a fallen log, a stand of saplings, a grass tussock and a mass of dock.
The log is the one wide, low silhouette in the set and it is there for that
reason before any other — five upright plants at six sizes are still five
upright plants.

**All six start from a base of overlapping ellipses.** The existing fern is a
scribble of fronds with a small clump at its foot, which is right for
something a metre from the lens and wrong for a mass at the edge of a wood: at
any distance a lacy silhouette is a smear. And the spread of that base is held
well inside the frame, because **`soft_border` is not enough on its own** — it
fades the last few per cent of the canvas to nothing, which turns a hard cut
into a soft one, and a soft cut through the middle of a solid mass is still a
cut. A window fixes a branch that overshoots; it cannot fix a body that was
never going to fit.

### The arrival

**The stage used to begin at full speed on its first frame**, which is the one
moment in it nobody composed: the rack cuts and the wood is already rushing
past at a rate the player took no time at all to reach. So the corridor opens
deep in fog and nearly still, and the fog lifts as the flight picks up — one
number, `intro`, driving both, and the whole of the effect is that they are
the same number. It is the turn's own movement run once at the beginning and
in the other direction.

`GROVE_INTRO_SPD` is not zero, deliberately: a world that is completely
stopped for half a second reads as a frozen frame, as the game having hung
rather than as a flight beginning.

The veil is the one **opaque** thing this stage draws over the world, and it
is affordable because it is the *back* pass — every bullet is drawn over it,
and nothing has been fired yet on the frames it is dense. The moon is left
showing through it as a bloom, because a fog with nothing behind it is a grey
rectangle: what makes the opening read as a wood rather than as a loading
screen is that there is plainly something in there. `grove_draw_front` keeps
the additive rule without exception.

Three of the five grove screenshot scenes set `intro = 1` before they run,
because they are posed at a frame inside the arrival and would otherwise be
photographs of the veil. `grove` waits it out honestly and `grove_arrive` is a
picture of it.

### The camera

**Nothing was flying the camera, and that is what made the corridor read as a
slideshow.** A constant speed down a straight line is arithmetically a flight
and looks like a dolly on rails: there is no cadence in it and nothing the eye
can attribute to a body. What is there now is two things:

- **A swell**, which is a slow sinusoid on the *speed* and nothing else. It
  is kept off `spd` and applied through `rush`, because `spd` is the speed the
  stage is flying at — the number the turn sets and the number a suite can ask
  about — and folding one into the other would mean no assertion could ever
  say what the turn did. `test_corridor` asserts that four swells travel what
  four flat ones would, so a flight with a rhythm has not quietly changed how
  long the stage is.

  **It was a wingbeat, and too much of one.** A fifth of the speed either way
  every second and a quarter was reported as a little jarring, and it was: the
  eye reads speed off the trunks nearest the lens, which cross the frame in
  about half a second, and a change it can catch inside that is a lurch rather
  than a rhythm. What matters is not the size of the swing but how fast it
  happens, so that is what is asserted — the speed may not change by half a
  per cent in a frame. The wingbeat changed it by 1.65; the swell, at under a
  tenth either way over four seconds, by 0.24.
- **A slow wander in both axes**, two periods each and no two of the four
  sharing a factor, so the camera never comes back to where it was and never
  traces a line while it is away. It is a third of what it was, because it no
  longer has to carry the camera's whole character on its own.
- **A lean toward the player**, which is the larger half of the yaw now and
  the only part of the camera anybody is driving. The sway answers to nobody:
  it gives the flight a body and gives the *player* no part in it, so the one
  thing on screen that could plausibly be steering the camera was the one
  thing it was not reading — and it reads as arbitrary because it is, reported
  as the stage steering at random and mostly to the right, which is what two
  sinusoids seeded where these are seeded do for the first twenty seconds.
  The sign is the rail shooter's: a player against the left wall is a camera
  looking left, which puts the vanishing point out to the *right* and the
  player heading into it.

  **The follow is filtered twice and both halves earn their keep.** The
  player crosses this field in two seconds and dodges across it several times
  a second, so a camera reading their position directly would shake in time
  with the dodging — on the one line a danmaku player measures every bullet
  against, at exactly the moment they are reading bullets. The lag is what
  removes the dodge, because a flick left and back is a third of a second
  against a time constant of one; the cap is what makes it a *guarantee*
  rather than a tuning, on the same argument `BOSS_TRACK_SPD` makes about a
  boss that tracks — a proportional ease alone is fastest exactly when the
  player has just moved furthest, which is the worst frame to be fast on.
  Measured: a player who commits to a wall gets the full 36 pixels, a player
  teleporting wall to wall every frame moves the camera by its cap and not a
  thousandth more, and a real dodge at `PLAYER_SPD` moves it **0.94 pixels**.

  **The aim is pushed, not pulled.** `bg_step` takes it as an argument and
  `bg_new` carries it on the base struct beside `omen`, for the reason `omen`
  is there: the run knows where the player is and has no idea what kind of
  world it is telling. A background that read the player itself would have
  the rack and the attack list — neither of which has a player — steering
  toward wherever the last run left somebody standing, and a suite could not
  fly the camera without posing one. `player_field_aim` is the field's own
  fraction rather than a coordinate, and it is the one place the sign is
  written down.

**The meander is a rotation and the lean is a translation, and the difference
between them is where depth comes from.** Under a yaw everything on screen
shifts by the same number of pixels — the moon at infinity, the far wood, a
tree ten metres off and the ground under it — because they have all turned
through the same angle. That is right for an idle look-around and it is
exactly wrong for steering: a camera driven by nothing but a yaw is a camera
whose scene has no depth in it, and when the bands were first rooted to the
yaw alone the canopy sat at a fixed offset in front of the moon however the
player flew. Reported as the branches having lost their parallax.

So the lean is a lateral *slide*, in world units, and every band and every
prop takes `corridor_k` of its own depth: the moon does not move, the far wall
of wood shifts five pixels, the canopy overhead shifts forty and the nearest
trunk a hundred. It costs one subtraction in `corridor_draw_prop` —
`_wx - _v.lat` — because the projection was already there, and one argument on
`grove_rooted_x`, because a band is a backdrop at a distance like everything
else. Measured: steering from one wall to the other parts the canopy from the
far wood by **66.8px**, and the two sit together when the player is on the
centre line.

The two canopy bands are at two depths, so they part from *each other* as
well, which is what stops the roof of the wood reading as one sheet. So the offsets go into the two numbers every position in the
corridor is measured from, `cx` and the horizon, and nothing that draws a prop
has to know the camera exists. The three tiled bands are the exception,
because they are laid out from the edge of the view rather than from its
middle, and they take `-ox` off their own drift.

**The pitch was a wingbeat first and that came out twice.** At nine pixels a
beat it is what flying looks like, and it was reported as overkill and as a
clash with the genre — this horizon is also the level a danmaku player reads
the field against, so whatever it does at a beat's rate, every bullet on
screen appears to do with it. The *rate* was the worse half of it: what a
corridor wants overhead is not a cadence but a rise and fall on the same
timescale as the meander, so that the two axes are one movement and what the
camera is doing is drifting through a wood rather than flapping through one.
`test_corridor` asserts that a second of it moves the horizon by almost
nothing, which is a claim about the rate and the only part of it a still frame
could never show.

### The turn

Half way through, the stage changes. `bg_set_omen` starts it — **one line in
the timeline**, because the stage clock is already held while a boss is on the
field, so an event written just after the midboss's gate fires on the frame
that midboss is finished and not before. A stage says when its own second half
begins, in its own running order, where somebody reading it can see it. `omen`
lives on the *base* background struct so a run can say "the stage turns"
without knowing what kind of world it is saying it to; stage one never asks.

Four movements over `BG_OMEN_TIME`:

1. **The quiet.** The mist stills, the stars begin to go out.
2. **The eclipse.** A shadow crosses the moon left to right — one interval
   sliding, with a leading edge that covers and a trailing edge that uncovers,
   because an eclipse is a body going past and that is one movement to write
   where a darken-and-reverse is two.

   **It is drawn as slices of the moon's own sprite, and it took three goes to
   get there.** The first subtracted the moon's disc from itself with
   `bm_subtract`, which shipped a grey rectangle gliding across the screen:
   GameMaker's subtract blend does not weight the source by its alpha, and a
   PNG keeps its colour channels in fully transparent pixels — so a luminance
   field generated across a whole canvas with a *disc-shaped alpha channel* is,
   to that blend, a bright grey **square**. Found by rendering the frame twice
   with the umbra on and off and differencing the two: the affected region came
   back a filled rectangle rather than a circle, which is the kind of question
   a screenshot can be *measured* for even when looking at one only says
   "something is wrong there".

   The second drew the same disc in black through normal blending. That is
   artefact-free, and it was reported as looking weird in motion — correctly,
   because a disc darkens the *sky* wherever it is not over the moon, so what
   actually travels across the frame is a black circle. An eclipse is not a
   black circle passing in front of a wood.

   **What passes is a shadow, and it is only ever on the moon.** So the moon is
   drawn again in vertical slices of its own sprite, one `draw_sprite_part_ext`
   each, with a per-slice alpha, and the shadow is a soft-edged band in x
   sweeping across them. Clipped to the disc by construction, because the disc
   *is* the thing being drawn — the same difference in kind as a window versus
   a margin. The diff that caught the first version now comes back as a
   circular arc with a soft edge inside it and nothing anywhere else.

   **And the shadow is copper, not black.** A total lunar eclipse turns the
   moon dark red, because the only light reaching it has been bent through the
   whole of an atmosphere — which is to say the eclipse is not something that
   happens *before* the blood moon, it is the reason for it. Two movements of
   the turn collapse into one fact.
3. **The relighting.** The moon comes out of the shadow red and brighter than
   it went in, and a ring leaves it.
4. **The wavefront.** The red travels *down the corridor* toward the player.

**The wave is a depth, not a screen radius, and that is the whole trick.**
Every prop and every row of ground already knows its own z, so "has the wave
reached this yet" is one compare — and what it draws is red arriving out of the
distance and rolling over the wood toward the camera, the far trees first and
the near ones last, every charm flaring as it passes. A ring expanding across
the *screen* would have been the obvious version and it would have turned the
near trees first, which is backwards. `test_grove_turn` asserts that something
far is redder than something near at every moment of the wave, because that is
the claim and a still frame is the thing least able to make it.

**The wood is darker than its palette says, and the number is
`GROVE_NIGHT_LIGHT`.** The palette was tuned against a frame with the moon in
full, and it came out hazier and flatter than the *same wood half way through
its eclipse* — where the mist stops glowing, the rims come down, the floor goes
nearer the colour of the air, and the hanging charms become the brightest
things in the picture. That frame was the better one, and it was better for a
reason worth keeping: a night wood is not short of *colour*, it is short of
*light*. So the light the stage runs at by default is three quarters, and the
moon — which is not dimmed by it — is left as the one bright thing in the
frame. Turning the palette down instead would have taken the chroma with it,
which is the mistake this stage already made once.

**And totality takes the light out of the wood, not just off the moon.**
`_b.light` is one number because there is one source: at totality the mist
stops glowing, the rims go out, the floor goes to the colour of the air, and
the only things left burning are the hexes in the trees and the wisps between
them. Dimming the moon alone — which is what the first pass did — photographed
as a wood in full moonlight with the moon missing.

The corridor also speeds up behind the wave, which is the cheapest way a
background has of saying the second half is worse: nothing about the fight
changed and the room is going past half again as fast.

### The one rule the foreground keeps

**Every draw in `grove_draw_front` is additive, and that is a fairness rule
rather than a look.** Stage one's near layer is opaque art held down to
`BG_NEAR_ALPHA` and kept out of the middle by a window, because an opaque
foreground over live danmaku does not hide scenery, it hides *bullets* — which
reached a player as "I am taking damage and there is nothing on screen".

A corridor cannot keep out of the middle: the whole idea is that things come at
the camera. So it takes the stronger rule instead. Light can only ever brighten
what is behind it, so an additive foreground cannot conceal a bullet at any
alpha, at any size, in any arrangement — a guarantee the keep-out window only
ever approximated. What is given up is the ability to put a solid branch in
front of the player, and that is not a loss worth arguing about.

**Nothing in this stage is `spr_bg_*`, and that is deliberate.**
`check_bg_seams` and `check_bg_keepout` measure every sprite under that prefix
and both are asking questions about a *scrolling tile*: does its last row match
its first, and does it keep out of the middle of a layer drawn over the field.
Neither means anything about a tree. The prefix here is `spr_scn_` — scenery —
and the rules those checks enforce are enforced for this stage where they can
be, by the additive foreground above.

## Stage three: the Gilded Sanctum

Mika -- a black fennec in gold, head mage to Ashiah, the Living God of Death.
Seven attacks: three non-spells and four spells, and **every one of them is
built round a ring**. The stage exists for the same reason the Hollow Grove
exists for its background: a mechanic cannot be judged from an engine test, so
there is a fight to play it in.

**His palace exists now**, and it is the third projection in the game: a room
rather than a floor or a corridor. See below.

**Every one of his spells washes indigo and none of them washes in its own
colour**, which is two rules at once. One background per boss, because an arena
is a *place*. And the wash has to be the colour his rings are not: the first
pass ran `Gilded Aperture` gold on gold and photographed as three gold bands
dissolving into a gold field, which is the `Cinder Waltz` finding exactly.

`SPELLBG_SIGIL` nearly did not work here for a subtler reason -- **the
fallback's own motif is a ring**. Two counter-rotating magic circles behind a
caster whose whole fight is rings is scenery drawn in the same shape as the one
object that has to be told apart from scenery, which is the ember-and-pellet
finding at four hundred pixels. What separates them is value and hue rather
than shape, and the indigo wash is what does it.

**`Gilded Aperture` is the fight's one real idea, and the aperture is the
*gap*.** Six rings on one orbit round him, turning: the windows between them
are the only line to the boss, and they sweep, so the answer is to find where
one is now and be under it. That is a positional question whose answer is
always somewhere.

The first version was the same name over a different shape -- three enormous
rings concentric on him, on the reasoning that each one the player got inside
was one fewer band in the way. It reads well written down and in practice it is
a boss who cannot be shot from anywhere sensible, which is the unanswerable
defect `BossMove` was invented to fix, arriving from a new direction. The
volleys are tangential rather than radial either way, because radial ones would
put a wall in every window the attack exists to open.

The rest of the table is a placeholder in the sense the whole game's is. What is
not placeholder is the vocabulary: between the Proctor's two attacks and Mika's
seven they use every verb a ring has, which is the argument the drafting
table's first five drafts are chosen on.

### The hall, and the sky over it

**Stage one is a floor, stage two is a corridor, and this is a room.** The
projection is a real camera with a real perspective matrix and the GPU's own
depth buffer -- which is what the other two could not be, because the stage
opens nine hundred units up aimed at the marble and then rises and levels out,
and pointing a camera at the floor is a *rotation*. `scripts/bg_sanctum` is
the whole of it and its own docstring is the long version; what follows is the
part about what is over the nave.

**The hall had a ceiling and taking it off is what stopped it reading as a
corridor.** It was capped at `HALL_CEIL_H` by a coffered plane with a
starfield painted on its underside -- a picture of a sky on a lid, and a lid
is exactly what a tunnel has. Floor, two walls and a ceiling is four edges and
no way out: every ray the camera casts lands on something a couple of bays
away, so however deep the shelving is modelled the room can never be bigger
than its own cross-section. It was reported as a basic corridor bounded by a
barebones ceiling texture, which is precisely what it was.

**What the sky is allowed to be is a wedge, and the wedge is a rule.** A long
horizontal edge at height H and half-width X projects, from a camera at
`HALL_CAM_FLY`, to a straight ray out of the vanishing point with slope
`(H - cam) / X` -- so the visible sky is the cone above the steepest such edge
in the hall, and every unit built on top of the wall narrows it for the whole
length of the hall. That makes the parapet's height the *price of the sky*,
paid once and paid everywhere, and it is why there is no upper storey: a
second register of stacks set back far enough not to close the wedge is a
register that is entirely hidden behind the first, which is what "inside the
silhouette" means. `test_hall_sky` does the arithmetic against the orrery's
own screen radius, because the failure it guards is "the landmark this stage
was opened up for is behind the masonry" and no assertion about either piece
alone could see it.

So what stands on the wall is a **coping, a parapet and a post**. An obelisk
over every pilaster on the ordinary bays and a brazier on the alcove ones --
thin things, which close the wedge only at their own bay rather than along the
whole hall, and what the eye gets is a rhythm of dark verticals marching away
against the stars. A gilt pyramidion on each is the only part actually lit,
which is enough: a dark shaft with a bright point on top is read as a whole
obelisk.

**The sky is a dome centred on the camera, drawn first, with the depth test
off.** That is the whole of a skybox and it is the only construction that gets
both halves right at once -- it turns correctly under the pitch and the lean,
and it does not translate at all, which is what "infinitely far away" means.
The reveal swings the camera through fifty-three degrees over four and a half
seconds and every frame of that has to read as the camera rising rather than
as a picture sliding, which is the defect `bg_grove` records about the canopy
bands reading as acetate pulled across the frame. Its radius is arbitrary and
has to be inside the frustum anyway, because the near and far planes clip
whether or not the depth test is on.

Four things were wrong with the first sky and every one of them is the same
mistake: **it was built for a sky nobody in this stage can see.**

- **It was derived from the fog by multiplication**, which keeps the join at
  the horizon exact and cannot add chroma -- so a desaturated haze made a
  desaturated sky at every elevation it was asked for. Reported, exactly, as a
  grey void with something caught in it. It is the grove's own correction one
  layer out: value and saturation are different budgets, and a deep blue at
  the same value as a neutral grey costs the danmaku nothing. `hall_sky_col`
  is three stops now, the lowest of which *is* `HALL_FOG` -- so the far end of
  the hall still dissolves into the sky rather than meeting it at a line,
  which is the finding about the ground at infinity being the sky.
- **Its gradient was spread over ninety degrees of elevation.** The camera
  never looks up: the top of the frame is twenty-seven degrees above the
  horizon and the wall tops cut off everything under about ten, so the whole
  visible sky is one narrow strip low down and every stop of the ramp was out
  of shot. `HALL_SKY_LOW_EL` and `HALL_SKY_HIGH_EL` are inside the strip.
- **Its extinction was too.** Stars have to fade out before the wall tops do,
  or the architecture closes into haze with a crisp starfield behind it and
  the join is the line the fog exists to hide -- but a ramp from two degrees
  to thirty put every star actually on screen at a third of its brightness.
  The assertion that holds it is measured **at the elevation the orrery hangs
  at**, because the first version asked whether a star well above the ramp's
  own end was lit, which is true of every ramp there is and is therefore not a
  question.
- **There were not enough of them.** Nine thousand stars, for about a hundred
  on screen: the dome is a hemisphere and the wedge is a narrow triangle, so
  ninety-eight per cent of any count is spent out of shot. Measured rather
  than guessed -- at two thousand six hundred the frame held thirty-nine and
  read as an empty sky with something wrong with it.

**And the handful of things there are only a handful of are composed for the
camera.** The stars are spread over the whole dome because there are enough of
them that the wedge gets its share wherever they fall; the nebulae and the
constellations are not, and at a uniform azimuth exactly one short segment of
one figure landed on screen out of nine. A sky is a backdrop and is allowed to
be arranged for the one direction the stage is ever flown, which is the same
call `bg_grove` makes when it puts the moon on the horizon and centres it
rather than hanging it where a hash landed. `HALL_SKY_SPREAD` is how far
either side of dead ahead, and it is wider than the lens so that nothing reads
as a fan.

A constellation is **local**: a seed direction and the four brightest stars
near it. Joined in index order instead, bright stars are scattered all over
the dome and what gets drawn is a cat's cradle the width of the sky.

**And the shafts of light went with the ceiling.** The hall used to have four
soft blades of light falling through the coffers in every other bay, with a
pool where each landed on the marble. They were right while there were coffers
to fall through; with the roof off they were two columns of haze arriving out
of nowhere, and what they actually did to the frame was grey the one part of
it the roof had been opened to show. What lights the hall now is the orbs set
into the wall and the braziers on the parapet, both of which are objects that
are *there*.

### The grand orrery

**The thing at the end of the hall, and the reason the roof came off.** A
corridor with nothing at the end of it is a corridor: the eye follows the
perspective to the vanishing point, finds haze, and comes back. It is an
armillary the size of a building hanging above the nave, and it is this
stage's moon in the sense `bg_grove` means one -- **a fixed direction rather
than a place**, anchored to the camera's own depth so the flight never reaches
it. That is a lie the player cannot catch, because at nine thousand units
nothing about it would change over the five minutes a stage runs even if it
were real.

**Where it sits is derived rather than chosen.** Its centre has to clear the
parapet's silhouette by its own screen radius, and its top has to be inside
the field; between them those fix the height and the size, and
`test_hall_sky` is the addition.

**It is real geometry rather than a painted card, and that is not
extravagance.** It is the only way it can *turn*. A ring seen face-on and the
same ring seen edge-on are different shapes, and an armillary whose rings are
continuously becoming one and then the other is the whole of what says
"instrument" rather than "logo". Six rings at six rates, no two tilts and no
two rates alike so it never settles into a shape the eye can learn, with the
outer limb **not turning at all** -- an armillary has a fixed meridian
everything else is measured against, and something stationary in the middle of
all that movement is what makes the movement legible.

**Gold is contrast, not hue, and the first limb was neither.** It was drawn as
a pale ground with dark divisions cut into it -- arithmetically a graduated
band, and at nine thousand units it averages to a flat mid-tone which the tint
then turns into a flat mid-brown. Reported as reading like thin wood rather
than ornate gold, which is exactly what an even texture in a warm hue is. Two
things fixed it and only one of them is the colour:

- **The band has a section.** A dark shadowed edge, a body rising to a hot
  specular line well off centre, a fall to a mid tone, and a second cooler
  line where light bounces back up off whatever is underneath. That profile
  across four pixels of screen is worth more than any amount of detail along
  the band, because it is the thing that *changes as the ring turns*. The
  divisions are cut into the body only and stop clear of the specular, so the
  highlight runs unbroken down the whole limb -- a graduation that crosses it
  breaks the one line doing the work.
- **`HALL_ORRERY_DIM` went from 0.62 to 0.80**, which is the multiply that had
  been turning (206, 170, 92) into (128, 105, 57). Gold is read off the
  *distance* between its lit and its shaded faces, and a dim applied to both
  ends of that closes it.

**The armature is the half of it that is not the rings.** Six hoops sharing a
middle are six hoops. A polar axis through them ending in a point at each end,
with collars down it, lens-shaped glass bubbles hung off it and a long pointed
plumb beneath, is an *instrument somebody mounted* -- and every one of those
is silhouette rather than detail, which is what survives at three hundred
pixels. The pillar below is longer than the finial above because the thing is
hanging: what is over it is a cap and what is under it is a plumb. The bubbles
are the one part that is not metal and they have to say so by being **cool and
bright against the gold** rather than by being a different grey; drawn in
`HALL_GLASS` -- which is the colour of an hourglass six hundred units from a
lamp -- they came back as dull grey lozenges.

**It is depth-tested and depth-written, unlike the sky.** A solid object drawn
with the test off shows its own far side through its near one, which on six
nested rings is a tangle of wire. It is nearer than the far plane and further
than every bay the hall draws, so the depth buffer sorts it against itself and
the hall paints over it exactly where the hall is in the way. **The fog is off
for it and the dimming is a multiply**, because hardware fog at nine thousand
units is total and a fogged orrery is a rectangle of fog colour; what distance
does to something bright is take its contrast away. And **it breathes by scale
rather than by alpha**, because a vertex buffer's alpha is frozen into it and
its size is one matrix.

**Its core is blue rather than white**, and that is a fairness line rather
than a taste. Driven hard enough to clip every channel it came back as a
twenty-pixel white-hot blob -- which is what a bullet's core is, in a sky
bullets cross.

### The chamber at the end of the hall

**The sky needed a floor.** With the roof off, the hall's own perspective ran
out at the vanishing point and everything past it was stars -- so the nave did
not read as a room open to the night, it read as a corridor trailing off into
space. What was missing is what every real view of a horizon has: something
the ground *becomes*.

It is **one painted quad at a fixed depth**, and painted is the point. A
second room in three dimensions at the end of an endless hall is a room the
flight would have to either reach or visibly never reach, and both of those
are worse than a backdrop -- which is what `bg_grove`'s moon is and what this
is. It is drawn with the depth test off immediately after the sky, which is
what puts it in front of the stars: a building occludes what is behind it.

**Only the far wall is drawn, and that is not a saving.** The chamber's near
rim is a third of the way closer than its centre, which puts it inside the
bays the hall is already drawing -- so it would be behind the shelving whether
it were painted or not. What is left is the half of a cylinder facing us,
which is the half that reads as a room. Its galleries are a real projection
rather than a curve somebody liked: a horizontal ring above the eye projects
to `Y / (1 + rho cos t)`, so its far point is furthest away, subtends least,
and sits **lowest** on the screen -- the arcs sag in the middle and rise at the
ends. Drawn the other way round the chamber reads as a basket.

**It is wide and short, because that is the shape of the hole it fills.** The
band available is the vanishing point up to the orrery's skirt -- two hundred
and sixty pixels of a 992-pixel field -- so the card is three times as wide as
it is tall. The first one was drawn on a square-ish canvas and hung over the
whole wedge: its galleries swept up past the orrery and read as a set of pale
arcs across the sky rather than as a building under one. `test_hall_sky`
asserts the top of it is under the orrery now, and that its foot is *below*
the vanishing point -- the hall's floor runs out a few thousand units short of
it, so a chamber stopping above the line would leave a band of bare sky
between the marble and the building, which is the ruled line the open roof was
built to avoid rather than to introduce.

**And everything on it is drawn at the size it will be seen at.** Eight tiers
with a one-pixel parapet and a row of one-pixel windows is, at the distance it
is actually read from, a grey smear with stripes in it. Four tiers, a
four-pixel parapet, windows at three, and one **large lit archway dead ahead**
is what survives -- and the archway is the part that matters, because the
wedge is narrowest at the vanishing point, so whatever is directly ahead and
low down is the part the player actually gets. The arch is dark and what is
inside it is the light: the first one filled its whole opening with a pale
grey and read as a featureless dome, which is the brightest thing in the frame
doing the least.

**The painting computes its own perspective, so it has to know how wide it
will be hung.** How much a gallery ring is foreshortened depends on how far
above the eye it sits *in the finished frame*, which means
`HALL_ROT_HW_SCREEN` in `tools/make_sanctum.py` and `HALL_ROT_HW` /
`HALL_ROT_Z` in `constants` are the same fact twice.
`check_rotunda_scale_agrees` does that division, because nothing else would
notice them drifting apart: the card would still be a valid PNG at a valid
size on a valid quad, and what it would draw is a round room whose rings curve
by the wrong amount.


### The review card

**A background cannot be judged from a still, and it cannot be judged from a
stage either.** `tools/shot.py` answers "does this frame read", which is what
it is for and what it is the only tool for; what it cannot answer is anything
about *movement* -- whether the reveal is paced right, whether the camera's
swell is a rhythm or a lurch, whether the orrery turns at a rate that reads as
an instrument or as a spinner. The only way to watch those used to be to play
four minutes of waves and a midboss and hope the turn came when it was
convenient.

So the background gets what an attack got when `practice_functions` was
written. `stage_preview` is a card on the rack -- **THE EMPTY ARCHIVES** --
that flies the hall with no enemies in it, holds phase A, runs the reveal,
holds phase B, and goes round again twelve times. It is the same argument as
attack practice and takes the same shape: **written as content rather than as
a debug view**, so what is being looked at is the stage's own console, field,
frame and camera rather than a diagnostic that would have to be judged twice.

**The cut back to phase A is a cut.** `bg_set_omen` is one-way because a stage
turns once; `bg_clear_omen` is the rewind, it lives in `bg_functions` because
which fields the turn is made of is that file's business and not a timeline's,
and nothing that is actually a stage should call it. A hard cut is right here
anyway -- the two poses are what is being compared, and a cut is how two poses
get compared.

**Nothing on it can touch the save**, on the drafting table's terms: `id` is
the empty string, so there is no stage to file a clear against, and there is
no boss for `on_boss_beaten` to fire on, so the path that reaches
`progress_record` is never entered. Unlike the drafting table its `build` *is*
defined, because this one genuinely is a run; the two locks are what stand in
for that. `bosses` is absent rather than empty, so `practice_available`
answers false and X on the rack opens nothing rather than an empty panel.

**And the rack says what it is.** "NOT YET CLEARED" is true of the card and is
a lie about it -- there is no boss on it, so nothing could ever clear it, and
a card advertising a condition it cannot meet reads as broken.
`stage_is_preview` is the flag, read through `[$ ]` like `stage_is_draft`
because every other entry lacks the field and a bare read raises.

Deleting the file and its line in `rack_list` removes the whole feature, which
is deliberate: it is a tool for a stage that is being built.


**Mika is cut out of the owner's own reference sheet**, which is the second
commissioned asset in the project and the first the owner drew themselves --
the rule Szuix's painted art is under is about *other people's* work, and it
does not apply here. `tools/make_mika.py` keys the flat background off the
sheet's own corner pixel and finds him by **flood fill rather than by
cropping**: the legend runs down the left of the sheet and his raised hand
reaches back under it, so no vertical line separates the two, and what does is
that he is one connected mass and the legend is forty small ones.

**He is skinned, and that is the third attempt.** The first ran the whole
figure through a travelling horizontal shear — correctly reported as a piece of
paper flapping in the wind, because a shear is one deformation applied to a
body with no joints, so nothing in it moves *relative* to anything else. The
second cut him into parts and turned each about its own pivot, which is the
textbook answer for a single illustration; it produced a new defect every time
a boundary moved — his head splitting, an ear tip left behind, a shoulder
coming away, a foot travelling with the cape.

**Every one of those is the same fault, and it is not a misplaced polygon — it
is the cut.** A hard boundary through solid fur shows the moment the two sides
move differently, and this figure has no narrow necks to hide one in: his head
runs into his ruff, his ruff into his shoulder, his leg into his foot. Moving
the seam moves the problem. Four rounds of moving it is the evidence.

So there are no layers. Each part is a **bone** — a region, a pivot and an
angle — and every pixel is displaced by the *weighted average* of what those
bones would do to it, the weights blending smoothly from one to the next. A
weighted average of two rigid motions is continuous, so there is nowhere left
for a seam to be. It is one displacement field and one resample: nothing is
composited, nothing drawn twice, and the alpha comes through whole rather than
losing a few per cent at every boundary the way the layered version did.

What it costs is that nothing can pass in front of anything else, so the bones
keep to small angles and none may cross. At four to five degrees that is not a
constraint anybody would notice.

Three things make a rig read as animation rather than as wobble:

- **Every bone lags the one it hangs from.** The head follows the body, the
  ears follow the head, the tail follows the hips, each by a fraction of a
  cycle. Follow-through is what separates a rig from a set of independent sine
  waves, and it costs one number per bone.
- **The pivot is the attachment point.** Turning about a part's middle drags
  its root about; turning about the root moves the tip, which is what a limb
  does.
- **The weights are wide** — twenty pixels of falloff at this size. A tight one
  is a soft-edged cut and behaves like one; a wide one means an ear's base is
  half ear and half head, which is what an ear's base is.

**Both hems are bones, and the right-hand one taught the rule.** An early rig
had it half inside the tail's region, so half the fur at his ankle swung and
half stayed — reported as a fault, and then, once it was explained, asked for
deliberately on both sides. That is the right call: drapery is the part of a
standing figure that should still be moving after the body has stopped.

**`Image.paste` with an RGBA image as its own mask applies the mask to the
*alpha channel too***, so alpha comes back squared and every feathered edge
loses half of itself. It cost the layered version a measurable slice of his
coverage before the whole thing was replaced, and it is worth knowing
independently: nothing in this project should paste RGBA through itself.

**And every region coordinate was read off a grid over the whole figure, and
every one was wrong the same way.** His box has a raised hand at one edge and a
tail at the other, so his head is centred at x 0.34 rather than the 0.29 it
looks like — enough that the ear polygons ran across his forehead. What settled
it in a single pass was **drawing the polygons back onto the art**, outlines and
pivots over the drawing, in one picture. `MIKA_RIG_DEBUG=1` does that. Reading a
region map by eye instead means reading a *padded* canvas, and the padding is
the same size as the error being looked for.

**Twelve frames, which is not Ziggy's six.** `boss_draw` holds every frame for
seven game frames whatever the sprite says, so six is a seven-tenths-of-a-second
loop -- a wingbeat, and right for him. A hovering mage wants an idle nearer a
second and a half, and the only way to buy that is more frames.

**How big he is, is measured off Ziggy rather than chosen.** Ziggy's sprite is
a 260x250 box and his *ink* is 198x208: most of a boss sprite is empty margin,
so matching the box put Mika -- whose cut-out is tight to his outline -- a fifth
larger than the other boss on the rack, and it was reported that way. What has
to agree between two characters is how much of the screen each one covers,
which is the ink.

**A bone's region still has to follow anatomy**, and the tail's got it wrong
at both ends before skinning made it forgiving: along the bottom it ran from
the hip to the frame's corner in one segment, straight through the fur fringe
at his ankle; at the top it leaned inward to x 0.58, which is through the outer
tufts of his right ear and through the middle of his raised claws. Its ink up
there does not begin until x 0.66. A region that is a little off now blends
rather than tearing, which is most of the argument for skinning over cutting.

**Every one of those was a coordinate read off a grid laid over the whole
figure, and every one was wrong the same way.** The figure's box has a raised
hand at one edge and a tail at the other, so his head is centred at x 0.34
rather than the 0.29 it looks like -- enough that the ear polygons ran across
his forehead and the boundary between them lay over the middle of his face.
What settled it in a single pass was **drawing the polygons back onto the
art**: every outline and pivot over the drawing, in one picture. Measuring what
each region actually *captures*, in figure coordinates, is the other half --
reading a region map by eye means reading a padded canvas, and the padding is
the same size as the error being looked for.

**Two things the sheet cannot supply and the cut has to add.** A *rim*, cool
against his blue-black fur, because he is drawn for a mid-brown page and this
stage is near-black -- a dark mass with no lit edge is a hole in the picture,
which is the rule every solid thing in the grove already keeps. And an
*origin*: his tail is nearly half the width of the frame, so the box's centre
lands between his hip and the base of it, and the origin is what
`enemy_take_shots` measures against. His head is found instead -- the ears are
the topmost ink, so their mean column is the line he stands on -- and the hit
circle goes on his chest under it, which is the same finding `make_player.py`
records about Szuix's wings.

**The eye card is his face, found rather than assumed.** Cropping the top third
of the figure is not cropping his head: the tail rises nearly as high as his
skull, so the first card came back with his face in the left third and half the
plate empty. The ears give the head's span, and **the eyes are found by being
blue** -- nothing else on him is -- so the card puts that centroid on its own
centre line rather than a fraction of a crop that changes.

The primitive-drawn version it replaced was wrong four times over and every one
of them was a reading the sheet already answered: the plumes are a fur mantle
from the shoulders rather than tails, he has one tail, he has digitigrade legs
and a tabard, and the ring marking is an interlace rather than a row of links.
**When the reference exists, use it** is the finding, and it cost four passes to
learn.

## The sound

**Nothing plays a sound. `sfx` casts a vote and `sfx_step` counts them**, once
a frame, and that inversion is the whole of the audio system.

A boss non-spell fires a hundred and twenty bullets on a single frame and a
spell that opens with a wall fires three hundred. If `fire` played a sound,
that frame would start a hundred and twenty voices of the same 75-millisecond
cue within a few samples of each other — which is not a hundred and twenty
shots, it is one shot at a hundred and twenty times the amplitude,
comb-filtered by its own copies into a burst of noise. It would also exhaust
the mixer's voice pool, so the *next* thing that mattered — the hit, the graze,
the spell being named — would be the thing that failed to sound.

The usual answer is a cooldown checked at the call site, and it is the wrong
shape three times over: it puts the rule in a hundred places, it fires on
whichever bullet happened to be first rather than on the volley, and it cannot
know that a hundred and twenty went out rather than four. So instead:

- **`sfx(cue)` is free.** It increments a counter. Every bullet, every shard,
  every grazed bullet may call it as often as it likes and nothing can go
  wrong — which is why the call sits inside `fire`, the hottest function in
  the game, with no guard around it.
- **`sfx_step()` resolves the frame.** At most one voice per cue, at most
  `SFX_VOICES` cues in total, and the *count* is what sets the gain and the
  pitch — so a volley of a hundred and twenty sounds bigger and lower than a
  volley of four, out of one voice.

That makes "a pattern must not machine-gun the mixer" a property of the API
rather than a rule every caller has to remember, which is the same bargain the
delay marks and the near layer's keep-out window make: a thing that cannot be
got wrong beats a thing that has to be got right. `test_audio_budget` states
it as a ratio — three hundred requests, one voice.

**Louder and lower together, because either alone reads as the wrong thing.**
Gain on its own is the same shot turned up; pitch on its own is a different,
larger object firing once. Together they are more of the same object, which is
what a volley is. The swell is logarithmic, because loudness is: a linear ramp
would put a forty-bullet volley off the top of the mix and leave four and eight
sounding identical.

**The backlog is dropped, not held.** A request that could not be afforded this
frame is about something that has already happened, so carrying it forward
would sound the shot after the bullet had crossed half the field — and would
let one busy second play out over the quiet one after it.

**Votes do not cross a room boundary, and the guard has to be in `sfx` as well
as in `sfx_step`.** That second half cost the boss's arrival cue. Entering
`room_game` runs `obj_game`'s Create — which in attack practice calls
`boss_spawn`, which asks for `BossAppear` — and only *then* the first Step.
With the check living in `sfx_step` alone, that first step saw a room it had
not seen before and cleared the request Create had just made: a cue requested
*after* the change, thrown away by the guard against requests made *before* it.
`sfx_sync_room` is called from both ends now, which is one integer compare in
the hottest path and puts the votes on either side of a room boundary on the
correct side of it. It was found by a suite rather than by ear.

**`sfx_step` is called from the top of a controller's Step, before anything
that might `exit`.** That costs one frame of latency — sixteen milliseconds,
well under the ear's ability to bind a sound to a picture — and buys that no
early return can skip it. `obj_game`'s Step has five `exit`s and three of them
are states where a cue most needs to sound: the pause menu, the result panel,
and the menu on it.

### Neither harness makes a sound

Same reasoning as neither taking the display, and the same shape of fix.
`tools/test.py` runs the game once and `tools/shot.py --all` runs it
thirty-two times, minimised, while somebody is working on something else — and
a build that played a boss dying through their speakers thirty-two times is the
complaint about the window coming to the front, one notch louder. `audio_init`
reads the command-line mode, so silence is expressed as *the game asking for
sound* rather than as a tool switching it off, and there is no frame in which
it was on.

**The flag is checked at the single point where a voice would start**, so
everything above that line runs under a harness exactly as it does in play and
`test_audio_budget` grades the real decision. And `audio_master_gain` is set to
zero *as well as* the flag — which is what lets `test_audio_playback` make the
real `audio_play_sound` call, silently, for all twenty-eight cues. Without it
the one statement that actually ships would be the one statement no suite ever
executes, and a wrong argument count there is not a compile error in GML: it
binds the missing one to `undefined` and throws when it is used, which under
either tool is a modal box and therefore a *hang*.

### What the set is

Touhou's shape rather than Touhou's content: cues are tiny, they are dry, they
are all clearly different from each other, and the enemy shot is the quietest
thing in the game despite being the most frequent.

- **Short, and dry.** A tail is a voice that outlives its own event. At the
  rate this game fires, a shot cue with a 400ms tail is a drone — and it is
  loudest exactly when the screen is fullest, which is when the player most
  needs to hear the one cue that matters.
- **Narrow, and in different bands.** Anything in the set can sound on the same
  frame as anything else, so two cues sharing a band mask each other. The shots
  live at 400–2500Hz, the graze sits at 3–5kHz where nothing else goes, the
  player's own shot is deliberately thinner than the enemy's, and the ceremony
  is the only thing allowed below 200Hz. Same argument the bullets' art makes
  about a bright core inside a saturated rim: a cue has to be identifiable in a
  fifth of a second against everything else, and being *loud* is not how that
  is bought.
- **Levelled in the generator by loudness, not by peak.** This was got wrong
  first and it is the single reason the first set was inaudible. A 26ms click
  and a 1.7-second boom normalised to the same *peak* are nowhere near the same
  loudness — the click has one sample up there and the boom has eighty thousand
  — so a mix levelled on peaks makes every short cue vanish. Measured, the
  hex's fan volleys were arriving at **-17.5 dBFS**: not quiet by design, quiet
  by measurement error. `finish` normalises to the RMS of the loudest 100ms
  window with a peak ceiling as a guard, and the gain column in
  `audio_functions` is then *computed* from the measured files rather than
  guessed.

Three shot cues across eighteen shapes, grouped by what a shape reads as rather
than by what it is: round things puff, pointed things ring, the big drawn ones
land. `sfx_for_shape` is in `audio_functions` rather than in the generated
`bullet_table` — which is the other defensible home, since `SPIN` is a property
of a shape for exactly the reason a voice might be. The deciding argument is
what re-running `make_bullets.py` costs: it redraws eighteen sprites and
rewrites every frame of them, which is the operation this project has twice
shipped a blank sprite through. **A change to how a bullet sounds must not be
able to blank a bullet.**

**Broken and survived are different cues, not one cue at two volumes** — the
same three-outcomes rule the practice panel keeps. And a capture plays *over*
the break rather than instead of it, which is why it is drawn thin and high:
the break already said the attack ended.

### The first set sounded like a match-three game

Reported in exactly those words — which is the same complaint the bullets
themselves once got, and it had the same root cause one medium over: a thing
lit by a generic model instead of built as a made object.

Measured, the diagnosis was unambiguous. The shot cues came out at crest factor
11.7 and tonality 0.05, which is the arithmetic definition of a click: nearly
all the energy in one transient spike, spread flat across the spectrum, nothing
ringing. The cause was that **every filter in the file was at Q around 1**. A
non-resonant filter shapes noise and lets it die; it never sings. There was no
resonator anywhere in a set of sounds whose entire subject is struck and
charged objects.

So the toolkit gained the audio equivalent of `art_common`'s cut bodies.
`struck` is a bank of *inharmonic* partials — harmonic ratios sound like a
plucked string, and the arcane and stone ratios used here sound like something
with mass being hit, which is what every bullet in this game is drawn as. `zap`
is a rich waveform swept downward through a *resonant* filter, which is the
difference between a puff of air and a projectile leaving. And saturation is
used far harder, because it is what fills in the harmonics that make a
synthesised hit sound struck rather than typed.

`snd_shot_sharp` — the cue the hex's fan volleys fire with, and the one that
was reported — went from crest 11.7 / tonality 0.05 to crest 3.9 / tonality
0.34, and about 11 dB louder.

**The set is laid out by spectral centroid and the gaps are checked**, because
two cues in one band mask each other and the shots are the ones that cannot
afford it: 453Hz (a shot landing), 940Hz (heavy shots), 1.5kHz (round shots),
3.0kHz (the player's bolt), 4.4kHz (the graze), 5.3kHz (needles). The player's
own bolt took two attempts to place — a hard-driven sweep up at 1.7kHz measured
*less* tonal than the click it replaced, and dropping its fundamental to fix
that put it at 2.2kHz, directly on top of the enemy's round bullets.

### A cue that does not decay

`check_envelopes` refuses one, and it has caught the same bug three times.

A cue whose level is still near its peak when the file ends does not sound like
a long sound — it sounds like a sound that was *cut off* — and nothing else can
see it: the peak is right, the duration is right, the spectrum is right, and
the waveform on the preview sheet looks like a confident block rather than a
mistake.

It found `snd_boss_die` holding an RMS of 0.65 for seven hundred milliseconds,
because `soft_clip` over a whole mix lifts everything behind the transient it
is compressing. It found `snd_boss_appear`'s arrival hit running at full
amplitude into the end of the file, because its `zap` had simply been written
without an envelope — one missing term in one expression, in a file where every
other `zap` has one. And it found `snd_hit` still at 68% of peak on its last
window, which for the one cue the player has to go straight back to dodging
through is the worst place in the game to spend a mix.

**And the guard was tested against a deliberately flat cue before being
believed**, which is the lesson `GAME_ERROR` taught: a check that is compiled,
commented at length and matched against nothing is indistinguishable from no
check at all, and the comment above it is what makes that hard to notice.

The other two envelope findings are worth keeping beside it. The first
`snd_bomb` opened with a rising swell, which put 250ms of near-silence between
the player pressing X and anything happening — a bomb heard a quarter of a
second late is a bomb pressed twice; the transient is at sample zero now and
the bloom follows it, which is the shape the drawing already had. And `finish`
fades its two ends by very different amounts: at two milliseconds each the head
fade was eating the attack of every plucked cue, and a 26ms click is *all*
attack, so the head gets 0.4ms and the tail keeps 3ms.

### The ward cues, and a telegraph that costs no pixels

`Demon Sealing Hex` gets four of its own — `WardClose`, `WardScatter`,
`WardPull`, `WardBurst` — and `WardPull` is the one worth writing down.

The collapse's whole difficulty is that its only cue is the ward beginning to
move, and `HEX_IMPLODE_RAMP` deliberately makes that gentle: a quarter of a
pixel a frame for the first fifth of a second, so the movement does not open as
a lurch. The cost, already written down beside the constant, is that a player
reading it correctly still learns about the collapse *from* the collapse.

A rising, tightening tone that arrives at the top exactly as the ward reaches
the middle says the same thing a second and a half earlier and spends not one
pixel of the field to do it — which is the trade the ramp could not make,
because a visual cue big enough to read is a visual cue that has already moved
the ward. So `snd_ward_pull` is written to `HEX_IMPLODE`'s own length, 108
frames, and resolves onto `snd_ward_burst`.

That is one fact in two files and nothing in the build would notice it
drifting: a cue half a second short resolves onto nothing, a cue half a second
long is still climbing when the detonation lands, and both are perfectly valid
audio. `test_audio_budget` asserts the two agree.

**They are named for the figure rather than for the attack**, because drafts
are meant to be thrown away and a cue called `HexImplode` would be four sounds
to rename the day the pattern moves to a real boss.

The inscription needed nothing added. Every rune goes through `fire`, so two
hundred beads laid down over ninety frames coalesce into one soft shot cue
every four frames — which is a pen on stone, and is what the coalescing sounds
like when it is handed something that genuinely is one continuous event.

## The art

**All of it is generated** at 1920x1080 by the `tools/make_*.py` scripts, except
Szuix, who was commissioned. Everything is drawn supersampled 4x and downsampled
once, because PIL's draw calls are hard-edged and a bevel drawn at 1x reads as
"made by a script".

| Script | Output |
|---|---|
| `tools/art_common.py` | Palette, `Canvas`, `Cut` and the cut-body shader, the distance-field shader, glows, fbm noise, preview sheets |
| `tools/make_palette.py` | `scripts/palette` — the palette, in GML |
| `tools/make_bullets.py` | Every bullet sprite **and** `scripts/bullet_table` |
| `tools/make_fx.py` | Sparks, blooms, rings, laser textures, the shards, the hitbox, the boss sigil, **Szuix's fire** (the shot and the bomb's wisps) and **his sigil** |
| `tools/make_fonts.py` | The six sprite-font atlases |
| `tools/make_enemies.py` | The four fodder shapes |
| `tools/make_boss.py` | Ziggy and his eye card — **placeholder, see below** |
| `tools/make_bg.py` | Stage one's three parallax layers |
| `tools/make_grove.py` | Stage two's scenery: trunks, trees, ivy, hanging charms, ferns, the moon, the forest floor, the far treeline, the canopy, mist — **and `scripts/grove_table`** |
| `tools/make_ui.py` | The console's furniture: gilt corners, crescent dividers, the crest, attack marks, plate glint |
| `tools/make_sanctum.py` | Stage three's hall: the marble, the joinery, the statues and banners -- **the sky over it** (stars in three magnitudes, nebulae, the graduated limb the orrery's rings are made of) **and the chamber at the end of it**, which is one painting rather than a second room |
| `tools/make_rings.py` | Mika's ring, **one sprite with its colour baked in** -- see the note under "Rings" |
| `tools/make_mika.py` | Mika and his eye card, **cut out of the owner's own reference sheet**, plus his idle as a shareable GIF |
| `tools/make_player.py` | Szuix, from the commissioned sheet; his aura, for the low-life warning; and his eye card, drawn from nothing |
| `tools/make_sfx.py` | Every sound effect, and the preview WAV and sheet |

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
`cut_finish`'s contour is two pixels, traced at the final size rather than at
SS and shrunk with everything else, and traced around the *thresholded* body
rather than the alpha — every bullet has a soft bloom, so tracing the alpha
draws a ring around the fog and not around the bullet. It is the hue at an
eighth rather than flat black, which is still near-black and still a mark
additive scenery cannot make, and it keeps a crimson bullet warm to its very
edge instead of ringing all fourteen hues in the same grey.

The shapes also grew by about half. The hitboxes grew by a third, deliberately
less: the picture's job is to be seen and the hitbox's job is to be fair, and
growing them together would have turned a legibility fix into a difficulty
change.

The same contour goes on the fodder, for the same reason.

### A bullet is *cut*, not lit — and that is the second time this was wrong

The core-inside-rim rule above is correct and was never the problem. What was
wrong is the *way* the three bands were laid down, and it took a second report
to see it: the whole set was **reported as belonging in a match-three game
rather than in a fantasy shooter** — smooth, bubbly, candy.

Two things did that, and neither is a matter of taste:

- **A specular highlight kicked up and to the left.** `orb_field` and
  `shade_shape` both add one, because both were written to light a shape the
  way a photographer lights a bead. An off-centre gloss says *polished convex
  plastic under a studio lamp*, and nothing else says it as loudly.
- **Bands that are a fraction of the shape rather than a number of pixels.**
  `depth_field` normalises by the shape's own deepest point, so a two-pixel rim
  on a 24-pixel pellet becomes a seven-pixel rim on an 88-pixel sphere, and
  every shape inflates into a pillow of its own hue.

A magical projectile is not a lit object. It is a **cut** object lit from
inside, so `art_common`'s "Cut bodies" section replaces both for anything the
player has to dodge:

- **No light direction anywhere.** What brightness there is is concentric or
  axial, because the source is the thing itself.
- **`edge_dist` is unnormalised**, in final pixels, so a lip is a lip and a rim
  is a rim at every size. It alternates 4- and 8-neighbour erosion to get an
  octagonal metric, because a square kernel is 41% generous on the diagonals
  and a rim 41% thicker at four points of a circle is visibly not a circle.
- **The interior stays saturated and a small drawn core carries the
  luminance.** The first pass ran the interior a third of the way to white and
  came back as pale lozenges with a coloured edge, which is fourteen hues
  reduced to three.

**And a shape is no longer a silhouette.** It is up to four masks — `body`,
`groove` cut into it dark, `bevel` for the planes that face the light, and
`core` — because **authored internal structure is the whole of the difference
between a shape that looks generated and one that looks designed**, and no
shading model buys it. So every bullet is a made object: a bead in a bezel with
a hoop engraved round it, a kunai with a collar and a lit spine, a talisman
with an inscription burning along it, a rune tile with a sigil struck into it.

Three failures found by looking at the sheet, all of them the same mistake at
different scales — **a structure that repeats the silhouette's own symmetry,
at the silhouette's own scale, all the way to its edge, panels the shape
instead of cutting it**:

- The round family was a brilliant cut seen from above: a hexagonal table with
  six facet breaks running out to the girdle. Six equal panels round a hexagon
  is a **football**. What replaced it is concentric — a bezel, a hoop, and
  small ticks that stop well short of the core.
- The moth was a delta wing swept hard back on a long thin body with a bright
  line down all of it and two streamers off the front, which is a **fighter
  jet**. Broad wing tips, a short thorax, a short lit axis and two antennae
  fixed it; the antennae are three pixels of sprite and the cheapest thing in
  the set.
- The ofuda was dark ink on a pale field in a frame with one clipped corner,
  which is a **luggage tag** — and the marks were not the problem, the
  silhouette was. It is a swallowtailed pennant now, with lit writing on a
  coloured strip, which is also what stopped its hue living in two pixels.

**`heart` is gone and `rune` is in its slot.** A heart is the most cute-coded
shape in the genre and there is no rendering of one that reads as somebody's
warding sigil. Nothing outside the generated table referenced it, so the swap
cost one line in a file `make_bullets.py` writes anyway — and it bought the set
a second glyph-bearing shape, which is deliberately *not* the ofuda's idea
twice: a talisman is paper somebody wrote on, and a rune is a stone somebody
charged.

**And the pickup took four goes, each of which drew a bullet a different
way.** It began as five flat polygons with a highlight line — a pentagon token
in three tints, the same structureless read, on the one object the player
actively chases. Then a cut quartz point, which was simply a bullet that
happened to be collectable: the same `Cut`, the same saturated hue, the same
hot core, and photographed against Ziggy's amber volleys **a gold one and an
amber bullet were the same colour at the same size with the same finish**.
Then a jewelled pendant, where being handsome was the problem twice over — it
was **bright and pointed downward**, which is to say pointed at the player,
which is what a bullet *is*; and at 42x46 it was larger than every bullet on
the field, so a shower of them after a bomb hid the pattern underneath. Then
flat enamel, which fixed all of that and stopped reading as a gemstone at all.

What ships is a **dark cut stone in a gilt bezel**, and every property of it is
load-bearing:

- **Small.** Thirty by twenty-four of drawing, under half the pendant and
  smaller than the `orb` half this boss's patterns are made of. It is drawn
  *over* the field, so the near-parallax rule applies to it: nothing that is
  not a bullet may be big enough to hide one.
- **Blunt.** No point anywhere on it. A shape coming to a point aimed down the
  screen is aimed at the player, and nobody stops mid-dodge to check whether
  this particular one is friendly.
- **Dark.** The stone is the hue at under half strength, which puts the whole
  token below the value of anything being dodged.
- **Lit rather than emissive, which is the rule worth keeping.** Every bullet
  is a light: no direction to its brightness and a white core burning in the
  middle. The pickup has no core at all and one small hard glint up and to the
  left — an *object catching* light. That is exactly the specular this redesign
  took off the bullets, put back on the one thing that should always have had
  it, and it inverts a bullet's most recognisable property in four pixels.
- **Two materials**, which no bullet in the set has. `COL_GILT` is a muted
  brass and every bullet hue is above 240 in its dominant channel, so the
  bezel is a family nothing a boss fires can reach — and the right family,
  since gilt on indigo is the console's, the console is the player's, and a
  pickup is loot Szuix is taking off somebody.

It is two `cut_shade` passes composited, because that function takes one hue
and the point of the shape is that it has two.

**What makes it findable is not the token.** It is the soft additive bloom
`item_draw` already lays under it, and that division of labour is why the token
itself is allowed to be this quiet: a coloured glow is a mark the scenery makes
constantly and no bullet can make at all, so it attracts the eye without ever
being mistaken for something to dodge.

### The sprite's edge is a hard clip

Both things `cut_finish` lays round a body run *past* the silhouette — the
contour grows outward by its own width, and the bloom is a Gaussian. A shape
drawn to within a pixel of its canvas therefore comes back with its outline
sliced flat along that side and its glow ending in a straight line.

Four of the eighteen bullets shipped exactly that way. The give-away was not
the sliced contour, which is two pixels and looks like a design choice; it was
the *glow*, reported as "their transparent glow visibly cuts off at the image
border" — the only part of the defect big enough to see. Measured afterwards,
`card`, `crystal`, `dart` and `rice` all had border alpha 245, which is the
body itself against the edge, and every other sprite in the set had 40 to 68.

`cut_pad` is the fix and it is derived rather than chosen: two sigmas of blur
puts the bloom under one part in two hundred of its peak. `cut_finish` pads the
canvas by that much before it draws anything, so **no shape function has to
know**, and it windows the last two pixels to zero on top — because a margin is
arithmetic that can be got wrong and a window cannot, which is the same bargain
`BG_NEAR_EDGE` makes one layer out. The sprites are correspondingly larger and
`global.bshape_w` / `_h` record the padded size; nothing in the game reads
either, and `hit` is unchanged, so the padding costs atlas and nothing else.

`orb_field`, `shade_shape` and `depth_field` are all still here and still
right — for the scenery, the fodder and the boss, none of which have to be told
apart from a bullet at a glance while being dodged.

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

**A star-shaped bullet turns, and the rate is a property of the shape.** The
engine has always had a per-bullet `spin` and exactly two hand-written patterns
ever set it; `SPIN` in `make_bullets.py` writes a default per shape into
`bullet_table.gml`, and `fire` reads it. Making it the caller's business would
mean a spell with half its stars spinning and half not, which reads as a bug in
the spell rather than as a choice.

The phase comes free: `fire` starts `angle` at the firing direction, so a ring
of stars is scattered rather than turning in lockstep — thirty synchronised
stars read as one object rotating. **Nothing oriented may carry one**, because
there `angle` *is* the heading and `bullet_step` overwrites it from `dir` every
frame; `test_bullet_table` asserts that rather than trusting the table, and
asserts the value reaches a fired bullet as well, because a default nothing
reads is not a default. A delayed bullet does not turn — the warning mark holds
still and the live bullet starts moving, which is the delay rule getting the
answer right for free.

**`make_bullets.py` is the single source of truth for a bullet's hit radius**,
not just its picture, and it generates `scripts/bullet_table/bullet_table.gml`
to say so. The radius and the sprite have to agree; if the number lived in GML
while the picture lived in Python the two would be edited apart within a week.
The flame is the case that proves it — 66x42 of picture and 9.5 of hitbox,
because the tail is not the bullet.

### The distance field, and why a blurred mask is not one

`orb_field` shades a round shape off a radius it can compute in closed form.
Everything else — a fodder gem, a boss's horn, a rock — goes through
`shade_shape`, which needs to know how deep inside the shape each pixel is.
(The bullets and the shards used to and no longer do; see "A bullet is *cut*,
not lit" above for the band that has to be a number of pixels rather than a
fraction of a shape.)

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
`tools/test.py` never draws a frame (one suite draws to a surface, and it
is about something else — see `test_band_strip`). Every scene `tools/shot.py` poses is
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
sprites. So the rule is general now: **`check_sprites_not_blank` refuses any
sprite with a frame that has no ink in it.**

**It used to sample three frames and pass the sprite if any of them had ink,
and the third occurrence walked straight through that.** Mika's sprite went
from six frames to twelve; the IDE wrote its cached six back over the first
half and left the second half empty, so he was on screen for seven tenths of
every second and gone for the other seven — and the check reported the project
sound, because frame 0 had ink. It reached a person as "his sprite is appearing
and disappearing periodically". The stated reason for sampling was that a
sprite inked in some frames and blank in others is not a failure mode this
project produces. It is now, and the exhaustive scan costs **0.9 seconds over
1129 frames**, which was never a budget worth defending.

**Its first exhaustive run then reported a sprite that was perfectly fine**,
and the mistake is worth keeping. `spr_scn_charm_lit` had two blank frames of
seven, which was called damage from the IDE twice before anybody looked: they
are a bundle of bones and a stick with feathers, and `charm_fetish`'s own
docstring says "no light in it at all". Some sprites are a **catalogue** rather
than an animation, and an empty entry in a catalogue is an answer.
`BLANK_FRAMES_OK` is the exemption and it carries its reason, because an
allow-list without one becomes a place to put anything inconvenient. The
failure message stopped asserting a cause at the same time -- it names both
possibilities now, because for one of them it had been confidently wrong.

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
`{name, spawn, phases}` so its attacks can be practised, and a background —
either a palette entry in `make_bg.py` for a parallax stack, or a `bg_*`
function returning a `BGKIND_CORRIDOR` struct and the scenery to fill it. A
stage whose second half looks different puts `wave_bg_omen()` in its running
order. The rack lays itself out from the list and draws every unbuilt
entry as locked, and the attack list lays itself out from `bosses`, so filling
one in changes no screen code.

To add a **bullet shape**: an entry in `SHAPES` in `make_bullets.py` and a
function returning a `Cut` — its `body`, and whatever `groove`, `bevel` and
`core` it wants. Re-run it and `bullet_table.gml` follows.

To add an attack built round a **ring**: `ring_new` puts one down and
`ring_attach`, `ring_grow`, `ring_charge` and `ring_link` are the rest of the
surface. A ring carries an `act` of its own shape `(ring, run, frame)`, so the
usual answer is to give it its whole behaviour at birth and never hold the
reference; when an attack genuinely needs one back -- pairing two for an arc --
keep the `gen` beside it and read through `ring_valid`. See `stage_sanctum`.

To add a **spell**: a row in the boss's phase table and a function of `_t`. It
appears in the attack list by itself, because that list is read off the same
table the fight is. Add a `move` to the row only if the pattern is fighting the
drift — see `BossMove`; saying nothing is saying `Drift`, which is right for
nearly every attack.

To add a **background worth watching rather than playing**: a card in
`rack_list` shaped like `preview_stage_def` -- an empty `id`, no `bosses`, and
a `build` whose whole running order is `wave_bg_rewind()` and
`wave_bg_omen()` on a loop. See "The review card".

To add an **attack with no boss yet**: a row in `draft_list()` in
`stage_drafts` — a name (or `""` for a non-spell), a hue, a clock and a
function, plus a `move` in the one case where the drift is wrong for it — and
the function beside it. The span of the bar, the kind, the
background and the caster's health all follow, and it is on the drafting table
the next time the game runs. Moving it to a real boss later is moving the
function and writing a proper `hp_end`.

## Current state

Playable end to end: the stage rack, stage one from its first wave through a
midboss to Ziggy's seven attacks, stage two through a wood that turns to blood
half way down it, stage three through a hall of rings to Mika, the result
screen, and permanent progress —
plus attack practice, which drills any one of the twenty-six attacks across
six casters on its own, the drafting table, which does the same for five
attacks that have no boss yet, and the review card, which flies stage three's
hall with nothing in it so the reveal can be watched rather than played for.
529 assertions pass.

Not done, in rough order of how much it is missed:

- **Every attack but `Demon Sealing Hex` is a placeholder.** Ziggy's seven,
  Velka's other five and both midbosses' attacks are simple shapes, all to be
  replaced; finished spells are meant to be at the Hex's level. See "The
  bar".

- **There is sound, and none of it has been heard by anybody playing.** The
  mixer is right and the cues are placeholders: twenty-eight synthesised WAVs
  drawn to designed peaks, which is enough to tune a *mix* against and is not
  the same thing as a sound somebody recorded. Replacing one is a file drop —
  see `tools/make_sfx.py`'s note on the contract. **No music**, which is the
  larger of the two remaining gaps and is not this file's shape at all: a cue
  is at most a second and a half and streams nothing, where a track loops for
  five minutes and wants `compression` and `preload` pointed the other way.
- **Stage three is a placeholder fight around a finished mechanic, and the
  two halves are at very different stages.** The ring pool is engine and is
  tested; Mika's nine attacks are the plainest arrangements of it that make
  each verb visible, and only `Gilded Aperture` is an idea rather than an
  exercise. **The hall is the finished half** — a real room under an open sky
  with the orrery at the end of it — and the fight standing in it is not.

- **The hall's sky is unplayed, in the same sense everything in `constants`
  is.** It was designed against screenshots and against arithmetic, which is
  the right pair of tools for "does the orrery clear the masonry" and says
  nothing about the two questions that matter: whether a landmark at the end
  of the hall is something a player looks at or something that pulls their
  eye off the field, and whether nine thousand stars and a constellation
  behind a wall of gold danmaku is legible or busy. The one that worries most
  is the second — the wedge sits directly above where the boss stands, which
  is where the pattern is thickest. `HALL_STARS`, `HALL_CONST_A` and
  `HALL_ORRERY_HALO_A` are one number each.
- **The chamber at the end of the hall is a painting and cannot be reached.**
  It is `bg_grove`'s moon on the same terms -- a destination that stays at a
  fixed distance for ever -- and whether five minutes of flying toward
  something that never arrives reads as *distance* or as a cheat is a question
  for somebody playing it. The honest answer if it reads as a cheat is to let
  it grow very slowly over a stage, which is one line in `hall_draw_far` and a
  number nobody has any feel for yet.
- **There is no upper storey, and the reason is a constraint rather than a
  choice.** A second register of stacks set back far enough not to narrow the
  sky is a register entirely hidden behind the first, so above the bookcases
  the hall is a parapet and a row of obelisks and then nothing. What that
  gives up is the tiers of galleries the reference has; what it buys is the
  sky the orrery hangs in. Anything that wants both has to widen the nave,
  which is `HALL_HALF_W` and every number tuned against it.
- **Six more stages are named on the rack and marked unbuilt.** Everything
  needed to add one is listed above; what is missing is the bosses, and each is
  a phase table and a character.
- **Stage two is unlocked from the start, and that is temporary.** The rack's
  locks pace a first playthrough, and pacing a playthrough of a stage that
  exists to be *looked at* is a circle — the same one the drafting table's
  gating note is about. `needs` goes back to `1` on the day Velka has a fight
  worth reaching, and it is one number.
- **Stage two's fight is mostly a placeholder and says so.** The Hollow
  Grove exists for its background: Velka has a name, a title, a colour, a
  caster's background, five attacks that are deliberately the plainest things
  this engine can produce — because a background cannot be judged from a still
  and there had to be something to look at the wood through — and `Demon
  Sealing Hex` as her last spell. Her handwriting is the next piece, and it is
  five rows.
- **The grove's own art is still generated rather than drawn.** The trunks are
  eight silhouettes and read as trunks; nobody has painted a tree. It improves
  the same way the boss art does, and the contract is the same — two sprites, a
  body and a moonward rim, tinted at draw time.
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
- **Every number a ring has is unplayed**, in the same sense as everything in
  `constants`. Whether `RING_BAND_FRAC` makes a ring feel solid or merely
  awkward, whether `RING_WARN` is long enough to read a charge coming, whether
  three concentric bands is one too many for `Gilded Aperture`, and whether
  being walled off from a boss is interesting for forty seconds or maddening
  for five are all questions for somebody holding the keyboard. The one that
  worries most is the last: an obstacle that stops the player *doing damage* is
  a new kind of frustration in this game, and the gradient the aperture is
  built on is an argument rather than a measurement.

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
- **The bosses' eye cards are still drawn from the placeholder boss art**, so
  the one piece of ceremony that is a close-up of a face is a close-up of
  primitives. It improves for free when the commission lands. **Szuix's own
  card is drawn rather than painted** — cel-shaded from curves in
  `make_player.py`, and the better of the two by some way, but it is still
  shapes written out in card pixels rather than a drawing. **The painted
  commissions of him are reference only and must not be shipped**: the crop
  that was in here for one pass came out again on the grounds that the rights
  are not the game's. Anything that replaces this has to be original or
  licensed, at 1280x420 with the eyes on the centre line.
- **Every one of the special's numbers is unplayed**, in the same sense as
  everything in `constants`: `BOMB_SEAL_DMG`, how long the seals take to leave,
  how hard they turn and how much they sweep were reasoned about against the
  shape of the sequence rather than against a fight. The damage in particular
  is a balance decision made by argument — a seal that strikes a boss and does
  nothing reads as broken — and it is one constant to take back out.
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
- **Nothing in the stages uses most of the newer bullet kinds yet.** The arc,
  the wake, the timed fade, the mid-flight graphic change and the homing
  modifier are all engine and all tested; the placeholder attacks do not use
  them, and the drafting table's first five drafts use all of them between
  them.
- **The drafts are as unplayed as everything else, and the drafting table does
  not make them less so** — it makes them *playable*, which is a different
  thing. Five patterns picked to exercise five engine verbs are five patterns
  chosen by what they demonstrate rather than by what they are like to dodge,
  and at least two of them are visibly too dense on a screenshot. That is the
  mode working: they are on a table because nobody has decided about them.
  **`Demon Sealing Hex` — Velka's now, and a draft when this was written — is
  the least played attack in the game and the most in need of it**, because
  it is the only one whose difficulty is a *shape* rather than a rate — and it is the one that turned out to be unanswerable rather
  than hard, which is why `BossMove` exists: whether the red ward's cell is small enough to make five
  aimed fans hard and large enough to make them survivable, whether ninety
  frames is long enough to find a corridor out of the blue one, and whether
  a player who reads the collapse coming can actually beat it out are three
  questions four screenshots cannot answer between them. The numbers they
  turn on — `HEX_R_IN`, the three gaps and the two fan beats — are one line
  each.
- **`BossMove`'s numbers are as unplayed as everything else.** That an
  attack which pins the player needs the boss to come to them is an argument
  about the rules and holds without being played; whether
  `BOSS_TRACK_SPD` at a third of the player's speed is *loose* rather than
  sluggish, and whether `BOSS_TRACK_SWAY` varies an aimed fan enough to
  matter, are questions for somebody holding the keyboard. A screenshot can
  say the boss is over the player, which is what the pictures of the hex now
  say; it cannot say how it felt getting there.
- **The attack list does not scroll.** Its plate is sized to its rows with the
  old fixed height as a ceiling, so a boss with more attacks than fit would run
  off the bottom rather than paging. The longest list is Ziggy's seven,
  Velka's six is next and the drafting table has five; the line to change is
  the one that computes `_y2` in `obj_practice`'s Draw.
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
