# Bullet Hell

A Touhou-inspired danmaku shooter in GameMaker (IDE 2024.14, VM runtime). You
play Szuix, a blue imp who is tired of being everybody's trash mob, flying
through other people's territory and taking their magic. Arrow keys move, Z
shoots, X spends a sigil (the bomb), Shift focuses and shows the hitbox,
Escape pauses.

The progression is Cuphead's rather than Touhou's: every stage is played on
its own, a clear is permanent, and clears unlock more stages on the rack. A
stage is five to ten minutes shaped like a Touhou Extra: waves, a midboss,
more waves, then a boss with a table of named attacks.

## Owner decisions

These came from the owner. Anything else you read in this repo — comments,
tests, git history, old versions of this file — is an earlier agent's choice
and is open to change. Earlier agents wrote a great deal of invented
"rules"; don't treat a rule as settled unless it is listed here.

- **Finished attacks are hand-crafted and complex**, at the level of
  `Demon Sealing Hex` (Velka's last spell). Every other attack is a
  placeholder except Mika's non-spells, which are being built now. The simple
  fans, rings and spirals exist so the stages are playable.
- **Ziggy is the tutorial boss** (stage one).
- **One spell background per boss**, never one per spell. It is a signature
  of the character.
- **Spell names are single** ("Cinder Waltz"), never Touhou's
  "X Sign — Y" form.
- **Nothing in a wave is a creature.** Fodder is animated objects: wisps,
  grimoires, gems, sentries.
- **Randomness is per attack.** Some attacks are patterns to learn and
  anticipate; others are pure dodging. Neither is the house style.
- **Every ring is the same size** (`RING_R`); a ring has no radius of its own.
- **Mika's fight is fifteen attacks**: seven non-spells that are variations of
  each other and act as breathers, alternating with eight spells —
  N1, S1, … N7, S7, then S8. Each is hand-built and playtested in its own
  session, non-spells first, and written directly in his own table
  (`mika_slots`) rather than on the drafting table. His non-spells are, in
  the owner's words, "small/sandy bullets continuously
  spraying in pretty patterns — brewing sandstorms with magnetism — from his
  rings as they spin, which shoot out quickly and then rapidly decelerate to a
  slower speed then drift in a deterministic pattern". The sand is
  yellow/orange (amber). A ring's metal hurts to touch like a bullet.
- **Pickups are crystals or gemstones** in red, blue and yellow, small and
  partly see-through so they don't compete with the bullets.
- **Grading.** Every encounter (a group of waves, or one boss attack) gets a
  mark: STONE, BRONZE, SILVER, GOLD, AMETHYST. A clean encounter is GOLD; each
  hit costs two rungs and each sigil one; beating the score threshold adds
  one. A stage where every mark is AMETHYST is ABSOLUTE AMETHYST, which is a
  standing, not a sixth tier.
- **UI is gilt on indigo**: a dark saturated violet ground, small areas of
  bright old gold, crescent and four-point-star motifs, cyan as the accent,
  serif type (Cinzel, Spectral). Aimed at old-school danmaku players; never
  mobile-game or match-3 styling.
- **Reference art is reproduced faithfully.** When the owner supplies art for
  a character or prop, match its anatomy, ornament and colours rather than
  reinterpreting it. Mika is cut from the owner's own sheet
  (`tools/source/mika_ref.png`), and his ring sprite has its colours baked in
  to match his markings.
- **The painted Szuix commissions are reference only.** No pixels from them
  may ship. Nobody has said whether the in-game pixel sheet
  (`tools/source/szuix_sheet.png`) has the same restriction, so ask before
  building on it.

## How to work here

- Do what was asked and no more. Don't write rules, constraints or
  justifications into docs, comments or tests that the owner didn't state. If
  you make a judgement call, say so in your reply rather than recording it as
  law in the repo.
- Attacks are in active playtesting. Don't write tests or docs that pin a
  pattern's numbers, counts, densities, timings or look; leave a short factual
  comment saying what the numbers do. Tests are for things that break
  silently: crashes, pool limits, a hitbox that disagrees with its sprite,
  collision, save safety.
- Label placeholders as placeholders.
- Verify only the blast radius of a change: build, tests and checks, then
  screenshot the one or two scenes the change touches (usually a non-spell
  and a spell of the affected boss). Don't run `shot.py --all` unless asked.
- Close the GameMaker IDE before running any `tools/make_*.py`. An open IDE
  writes its cached copy of a sprite back over the regenerated one, silently.
  Run `check_project.py` after any art pass.
- Record what changed and what was measured, not the story of how you got
  there. Git holds the history.

## Tools

```bash
python tools/build.py && python tools/test.py && python tools/check_project.py
```

| Tool | What it does |
|---|---|
| `tools/build.py` | Compiles with the runtime's `Igor.exe`; a cached build takes seconds and reports real diagnostics. `--run` launches the game, `--clean` drops the cache. |
| `tools/test.py` | Builds, runs the game with `-selftest`, and grades the suites in `scripts/selftest` from stdout. `-v` lists every assertion. |
| `tools/check_project.py` | Static checks GameMaker doesn't do: resource registration and `.yy` shape, object events, undefined macros and functions, call arity, legacy globals, blank sprite frames, sprite and font metrics shared with the generators, plus guards for specific past bugs (rings must block shots before enemies take them, `run_clear_field` must be called, grove horizon bands stay rooted to the camera, hall vertex buffers must match their sprite's texture). |
| `tools/shot.py <scene>` | Builds, poses a scene with `-shot <scene>`, and saves `tools/_preview/<scene>.png`. `--burst 0,20,40` photographs one scene at several frame offsets and tiles a sheet. `--fullscreen` gives exact design-size pixels. It fails a run whose output shows a GameMaker error even if a picture was saved. Scenes are listed in `shot_scene_list()` (`scripts/shot_scenes`) and in `SCENES` in `shot.py`; both must be updated together. |
| `tools/gm_new.py` | Importable module, no command line. It creates and registers resources: `script`, `sprite`, `shader`, `obj`, `room`, `sound`, `folder`, `delete`. GUIDs are derived from names, so regenerating writes identical files. |
| `tools/make_*.py` | The asset generators (see Art). Each writes a preview sheet to `tools/_preview/`, which is git-ignored. |

Harness behaviour:

- Both harnesses launch the game minimised through `build.run_game`, and
  silent: `audio_init` sets master gain to zero unless the game was started
  normally. Only a normal launch (or `-fullscreen`) goes full screen.
- A GML runtime error is a modal dialog, which under a harness is a hang until
  the timeout. An unknown shot scene is refused rather than hanging.
- `shot.py` moves the real save aside while it runs and puts it back
  afterwards. The save lives in `%LOCALAPPDATA%\Bullet_Hell\` (GameMaker
  turns the space into an underscore).
- A posed player can be made `untouchable` (a harness-only flag), so a hit
  doesn't clear a bite out of the pattern being photographed.

## Code layout

Game logic is plain functions over structs; objects are thin controllers.

| Object | Role |
|---|---|
| `obj_boot` | Initialises every global and pool, parses `-selftest`, `-shot <scene>`, `-burst <list>`, `-fullscreen`, and routes to a room. Every global must be assigned here. |
| `obj_title` | The stage rack. Starting a stage clears `global.practice`. |
| `obj_practice` | The attack list for practising one attack. It leaves `global.practice` set, so returning reselects the last attack. |
| `obj_game` | One run: timeline, player, bosses, HUD. Its Create calls `run_clear_field()` first, because the pools are globals that outlive a room. |
| `obj_selftest`, `obj_shot` | Test runner; screenshot poser. |

| Scripts | Contents |
|---|---|
| `constants`, `palette`, `bullet_table`, `grove_table`, `sanctum_table` | Macros and tables. All but `constants` are generated. |
| `danmaku_functions` | Bullet pool, the firing API, the event queue, collision, graze, the player's shots |
| `laser_functions`, `ring_functions`, `item_functions`, `enemy_functions`, `fx_functions` | The other pools |
| `player_functions` | Player, input, the sigil and its seals, grace, hitbox |
| `boss_functions` | Boss phase machine, movement modes, ceremony timing |
| `stage_functions` | Stage timeline, gates, wave helpers, encounter windows, `run_clear_field` |
| `stage_ziggy`, `stage_grove`, `stage_sanctum`, `mika_nonspells` | Stages one to three: timelines, bosses, attacks. `stage_list()`, the roster of all stages, lives in `stage_ziggy`. |
| `stage_drafts` | The drafting table, plus `rack_list()`: the roster and the extra cards the rack shows |
| `stage_preview` | The review card, which flies stage three's hall with no enemies |
| `stage_sanctum_old` | Stage three as it was before Mika's rebuild, frozen on its own rack card. Delete it once his slots are filled, along with its rack line, `test_old_sanctum`, its line in `test_stage_run` and `stage_is_old_draft`. |
| `practice_functions` | Single-attack practice |
| `rank_functions`, `rank_card` | Encounter grading and the medal card |
| `bg_functions`, `bg_corridor`, `bg_grove`, `bg_sanctum` | Backgrounds: dispatch and stage one's parallax, the corridor projection, stage two's wood, stage three's 3D hall |
| `hud_functions`, `ui_functions` | The console, the boss's health rail, menus; drawing helpers, fonts, gauges |
| `audio_functions`, `save_functions` | The sound mixer; saving |
| `selftest`, `shot_scenes` | Test suites; screenshot scenes |

## Engine

**Fixed-step and frame-based.** Everything steps at 60 Hz and measures time
in frames. Code in `scripts/` must not read `delta_time`; `check_project.py`
enforces it. This is what lets the tests drive hundreds of frames headlessly.

**The screen.** The design resolution is 1920x1080, and
`display_set_gui_size` pins the GUI layer to it. The playfield is
`FIELD_X0/Y0/W/H` (1360x992 at 44,44), with the console plate to its right
(`HUD_PANEL_*`). Waves are authored in field coordinates: `wave_line` and
`wave_cross` add `FIELD_X0/Y0` themselves. The frame round the field is drawn
in the GUI event as opaque margin rectangles. Anything drawn after it with
world coordinates must be clamped to the field (`fx_draw_text` does). Screen
shake is a world matrix in the Draw event, so the GUI never shakes.

**Pools.** Bullets, lasers, rings, items, enemies and effects are structs in
flat global arrays, not instances. Removal swaps with the last live entry, so
step loops run backwards. Dead structs are reused, so steady firing allocates
nothing. A full pool refuses: `fire` returns `undefined` past `BULLET_MAX`,
and every caller copes. Because slots are reused, don't hold a reference to a
pooled struct across frames. Rings carry a `gen` checked by `ring_valid`;
bomb seals pick their target again every frame.

**Firing** follows Danmakufu ph3. `fire(x, y, spd, dir, shape, col, delay)`
returns the bullet; `fire_ring`, `fire_fan`, `fire_stack`, `fire_ring_stack`,
`fire_fan_stack` and `fire_spray` build on it. `fire_xy` with `bullet_force`
is the Cartesian model, needed for forces along one axis. A later polar
instruction puts a bullet back on the polar model. Continuous behaviours are
`BMod` (`Home`, `Wander`). Scheduled events are `BQ` entries (`Aim`, `Move`,
`Accel`, `Turn`, `Force`, `Split`, `Shed`, `Graphic`, `Fade`), added with
the `bullet_*_at` helpers, at most `BULLET_QUEUE_MAX` per bullet. Split and
shed children inherit the parent's shape and colour, and can be dressed by a
callback. Things that bite:

- `life` increments at the end of a step, so an event at frame `_at` fires on
  step `_at + 1`.
- `bullet_step` applies acceleration before moving, which matters for
  closed-form trajectories.
- `BQ.Accel` takes `min(spd, floor)` as the floor, so a floor above the
  current speed silently becomes the current speed.
- An odd fan puts a bullet on the aim line; an even fan leaves a gap there.
- A bullet's `r` (hitbox) is set from `bullet_table` for its shape. If you
  draw a bullet at a different `scale`, change `r` with it.

**Delay and warnings.** For its `delay` frames a bullet is a harmless,
stationary warning mark, drawn in a second pass above live bullets. Lasers go
warn → fire → fade and kill only while firing, at about a third of their
drawn width.

**Collision is swept.** `bullet_hit_index` measures distance to the segment
the bullet moved this frame, behind a bounding-box reject covering the whole
segment. Graze pays once per bullet; lasers and ring bands pay on a cooldown.
`resist` bullets survive `bullet_clear_circle` (bombs, the clear after a
hit) but not `bullet_clear_all` (phase changes).

**Lasers.** `laser_beam` is anchored and telegraphed; it can follow a `src`
and re-aim at a `look` point every frame. `laser_ray` travels and is culled
when its tail leaves. `laser_curve` draws the trail of its head's past
positions.

**Rings** (`ring_functions`) are furniture a boss puts down:

- They absorb player shots on their band but not through their hole.
- They hurt to touch.
- They can be charged, which widens the lethal band after a warning, and
  linked into a lethal arc.
- They carry an `act` that fires like a boss attack.

`ring_block_shots` must run before `enemy_take_shots` (checked). To fire from
a moving ring, use `ring_rim_at_x/_y`, which give where the metal will be when
the delay ends. Otherwise bullets appear inside the hole.

**The player** is a struct. `player_step` takes an input struct, and
`input_gather` is the only code that reads a device, so tests can drive the
player. On the same frame, a sigil is checked before shots and hits. A hit
clears nearby bullets and scatters recoverable shards. The focused hitbox is
drawn last, at exactly `PLAYER_R`.

**The HUD reacts by watching.** Nothing in the game calls the HUD to report
a hit, a score or a new mark. `hud_step` compares what it is showing with the
true values and animates the difference. That includes the boss's health
rail, which lowers when a boss is on the field and rises when it leaves, and
the rank card, which is thrown when the ledger grows. The rail is drawn before
the field frame, so it can hide above the field.

**Bosses.** `boss_spawn(x, y, hp, phases, def)`. A phase is
`{kind, name, col, bg, hp_end, time, attack, move?}`, and
`attack(_e, _g, _t)` is called every frame with the frames elapsed.

- A phase ends on health (checked first) or on time, and either way the bar
  is pulled to `hp_end`. A capture needs the spell broken with no hit and no
  sigil.
- A named spell gets a banner, an eye card and its boss's spell background.
  It waits `BOSS_SPELL_LEAD` (the eye card) before firing, and a boss can't be
  hurt during its entry, its declarations or the pause between phases
  (`boss_vulnerable`).
- `move` is a `BossMove`: `Drift` (the default), `Close`, `Track`, `Fixed`
  or `Step`. Read it as `_p[$ "move"] ?? BossMove.Drift`, because a bare read
  of a missing struct field raises.
- `def.final == false` makes a midboss.
- Phase tables are built by functions (`ziggy_phases()` and so on), never
  shared, because phase structs are mutable.

**Stages.** A stage def is `{id, name, subtitle, needs, make_bg, build,
bosses}`.

- `build` returns a timeline of `ev(at, fn)` and `ev_gate(at)` entries. A gate
  freezes stage time until no fodder is on the field, after a short grace so
  a gate placed just after a spawn doesn't release at once.
- Stage time doesn't advance while a boss is up.
- A group of waves is graded as the window during which fodder is on the
  field (`stage_encounter_step`), and `stage_count_encounters` counts a
  stage's encounters.
- `bosses` lists `{name, spawn, phases, turned?}` for practice and counting;
  `turned` starts practice in the stage's second-half background.
- A def whose `id` is empty can never write a clear: `progress_record` refuses
  it. Practice, the drafting table, the review card and the old stage three
  all rely on that.

**Practice.** X on the rack lists a stage's attacks, and a practice run is an
ordinary run with an empty timeline:

- The boss is placed on the chosen attack, with full life and full sigil.
- A `READY` count runs inside the boss's between-phase pause.
- The health rail shows the practised attack's own span (`hud_boss_span`).
- Nothing is written to the save. Best scores live in `global.practice_best`
  for the session only.

The drafting table works the same way. Each draft gets an equal share of the
draft boss's bar, the boss's health is `DRAFT_SLOT_HP` times the number of
drafts, and the table has no `build`, so it can only be practised.

**Audio.** `sfx(cue)` only casts a vote; `sfx_step()` resolves each frame's
votes: one voice per cue, at most `SFX_VOICES` a frame, and the count scales
gain and pitch. So bullets can call `sfx` freely. Call `sfx_step` at the top
of a controller's Step, before any `exit`. All cues are synthesised
placeholders from `tools/make_sfx.py`, and there is no music yet.

**Saving.** `save_write_json` writes a temp file and renames it over the live
one. `save_read_json` falls back to the temp and renames an unparsable file
to `.bad`. No test touches the real save.

## Backgrounds

There are three kinds, dispatched on `bg.kind` by `bg_step`, `bg_draw_back`
and `bg_draw_front`.

- **Parallax** (stage one, `bg_brimstone`): three layers from `make_bg.py`.
  They must tile vertically. The near layer draws over the field, so it is
  translucent (`BG_NEAR_ALPHA`) and kept out of the middle;
  `check_bg_seams` and `check_bg_keepout` measure the PNGs.
- **Corridor** (stage two, `bg_grove` on `bg_corridor`): one perspective
  projection (`corridor_k = FOCAL / z`), with props in depth-sorted ring
  buffers.
  - Every ring is drawn in one merged far-to-near pass.
  - A prop's variety comes from `corridor_hash` of its lap, so the wood is
    identical on every attempt.
  - `grove_draw_front` only draws additively, so it can't hide a bullet.
  - Horizon bands follow the camera (`grove_rooted_x`, checked), and only the
    mist drifts.
  - Halfway through, `wave_bg_omen()` turns the stage: an eclipse, a blood
    moon, and a red wave travelling down the corridor by depth.
- **Room** (stage three, `bg_sanctum`): real 3D with a perspective matrix,
  the depth buffer and the project's only shader, `sh_hall`. The shader does
  distance fog, fades far bays out, and does its own alpha test. Bays are
  frozen vertex buffers. Two things bite:
  - `vertex_submit` takes one texture, so a buffer may only hold geometry
    UV-mapped from the sprite frame it is submitted with.
    `check_hall_frame_textures` and `check_hall_buffer_textures` enforce this.
    A wrong pairing looks fine until the atlas repacks, then shows garbage
    intermittently.
  - Restore every GPU state you change (culling, shader, depth). A leak breaks
    the HUD.

Spell backgrounds (`spell_bg_*`, chosen per boss by `def.spell_bg`) darken
the world rather than brightening it, and the front layers fade with them.

## Art

Everything is generated by `tools/make_*.py` at 1920x1080 and drawn 4x
supersampled. The exceptions are the commissioned Szuix sheet and the
owner's Mika sheet in `tools/source/`.

| Script | Makes |
|---|---|
| `art_common.py` | Shared canvas, shading, noise and preview helpers |
| `make_palette.py` | `scripts/palette` |
| `make_bullets.py` | Bullet sprites **and** `scripts/bullet_table`: hit radius, default spin, frame counts. A bullet's radius is defined next to its picture. |
| `make_fx.py`, `make_items.py`, `make_ui.py`, `make_fonts.py` | Effects plus Szuix's shot and sigil; pickups; console furniture, medals and the boss rail; sprite fonts |
| `make_enemies.py`, `make_player.py`, `make_boss.py` | Fodder; Szuix from his sheet; Ziggy, whose art is a placeholder. `make_boss.py` states what a painted replacement must keep. |
| `make_mika.py`, `make_rings.py` | Mika from the owner's sheet (a skinned rig; `MIKA_RIG_DEBUG=1` draws its regions over the art); Mika's ring |
| `make_bg.py`, `make_grove.py`, `make_sanctum.py` | Stage one's layers; stage two's scenery and `scripts/grove_table`; stage three's materials and `scripts/sanctum_table` |
| `make_sfx.py` | All sound effects |

- Most art is luminance and gets tinted at draw time, so one set of fodder
  serves every stage. Mika's ring and characters taken from reference sheets
  keep their own colours.
- A bullet is a bright core in a saturated body with a hard dark contour
  (`cut_finish` in `art_common`). The dark contour is what additive scenery
  can never produce. Each shape is one sprite with one frame per colour; get
  the index from `bullet_frame`. Oriented shapes point right at angle 0.
- Some numbers exist both in a generator and in `constants`.
  `check_project.py` compares the font metrics, the near layer's keep-out and
  the rotunda's scale. Nothing compares `UI_CORNER_DEPTH` or `BOSS_INK_ABOVE`,
  so re-measure those by hand when their art changes.
- `check_sprites_not_blank` refuses a sprite with an empty frame, which is how
  IDE damage shows up. `BLANK_FRAMES_OK` lists the few sprites whose empty
  frames are intentional.
- Szuix is scaled up by NEAREST to 6x, blurred, then LANCZOS down, all with
  premultiplied alpha: the sheet's transparent pixels are white.
- Fonts are sprite fonts built from bundled OFL faces. Don't bake in the
  system's Microsoft fonts. There is no kerning, which shows on Cinzel's `Q`.

## GameMaker traps (each has bitten this project)

- `score`, `health` and `lives` are legacy built-in globals. An instance
  variable with one of those names silently splits in two, so the run's
  points are called `tally`. Checked.
- An undefined `#macro` compiles as a variable read and throws at run time. A
  call with too few arguments binds the rest to `undefined`. Both are
  checked, and under a harness a throw is a hang.
- `??` handles an undefined value, not a missing variable. Assign every
  global in `obj_boot`, and read optional struct fields with `s[$ "name"]`.
- `round()` rounds halves to even (`round(2.5) == 2`); use `floor(x + 0.5)`.
- `frac()` keeps its sign. Fold a hash into `[0, 1)` before using it as an
  index.
- A bare `draw_sprite` uses whatever colour and alpha a previous event left
  set. Use `draw_sprite_ext(..., c_white, 1)`. Checked. Helpers that change
  draw state put it back.
- A sprite's origin is part of its contract: a helper that takes a centre has
  to subtract the half-size for a `topleft` sprite.
- Font accessors are functions: write `draw_set_font(fnt_ui())`, not
  `fnt_ui`. Checked.
- `string_height` on a sprite font returns the atlas cell rather than the ink
  (`FONT_INK_RATIO` corrects for it). The space glyph needs an
  invisible-but-present bar, or spaces vanish.
- `draw_roundrect_ext` silently clamps its radius, so the gauges build their
  own capsule contour.
- A primitive textured with `sprite_get_texture` reads UVs in the sprite's
  own 0–1 space, not the texture page's.
- `window_set_visible(false)` stops the game stepping.
  `option_windows_start_fullscreen` is read before any GML runs, so it stays
  off; `obj_boot` enters borderless full screen itself.
- `file_text_open_write` truncates at once, which is why saving writes a temp
  file and renames it.
- In Python, `Image.paste(rgba, mask=rgba)` squares the alpha. Blur
  premultiplied images.

## Adding things

Create every resource through `tools/gm_new.py`.

- **An attack**: a row in a boss's phase table and a function
  `(_e, _g, _t)`. It appears in the practice list by itself. Add `move` only
  if the default drift works against the pattern.
- **An attack with no boss yet**: a row in `draft_list()` in `stage_drafts`
  (a name, or `""` for a non-spell; a colour; a time; the function; an
  optional `move`). Moving it to a boss later means moving the function and
  giving it an `hp_end`.
- **One of Mika's slots**: its row in `mika_slots()` in `stage_sanctum`, where
  the `hp` column is per slot and the thresholds are summed, and the attack
  itself in a script under `Scripts/mika`. Practise it with X on the rack and
  photograph it with `python tools/shot.py mika_n3` (there is one scene per
  slot). The picture is taken four seconds into the attack, and `--burst`
  offsets count from there.
- **A ring attack**: `ring_new`, then `ring_attach`, `ring_charge` and
  `ring_link`. Where possible, give the ring its whole behaviour as an `act`
  when it is created.
- **A stage**: a def in `stage_list()`, a script with its timeline and
  bosses, and a background: a palette in `make_bg.py` for parallax, or a
  `bg_*` function returning a corridor or room struct. Put `wave_bg_omen()`
  in the timeline if its second half changes.
- **A bullet shape**: an entry in `SHAPES` in `make_bullets.py` returning a
  `Cut`. Re-run it and `bullet_table` follows.
- **A screenshot scene**: add it to `shot_scene_list()` and to `SCENES` in
  `tools/shot.py`.

## Current state

What's playable:

- The rack.
- Stage one: Ziggy, and the Warden as midboss.
- Stage two: Velka, and the Husk as midboss. The wood turns to blood halfway
  through.
- Stage three: Mika, and the Proctor as midboss, in the finished 3D hall.
- The result screen and permanent progress.
- Practice for every attack.
- The drafting table.
- The review card.
- The old stage three.

Stages two and three are unlocked from the start. Six more stages are named
on the rack and not built.

Mika's slots (`mika_slots()` is the source of truth):

| Slot | State |
|---|---|
| N1, N2 | Written: two rings milling sand, and the same mill turned the other way. Mika himself fires nothing. |
| N3–N6 | Drafts, unplayed: the mill with four rings, then with six, each followed by its mirror |
| N7 | Draft, unplayed: six rings whose orbit reverses on each of his hops, with an aimed bolt from each ring at every reversal |
| S1–S3, S8 | Old placeholders: `Gilded Aperture`, `Ashiah's Circuit`, `Three Open Gates`, `Grand Orrery` |
| S4–S7 | Stubs (`Unwritten Spell 4` to `7`) |

Known gaps:

- Nothing has been balanced against a human; every tuning number is a first
  guess.
- These are placeholders: all attacks except the Hex and Mika's non-spells
  (Ziggy's, Velka's first five, the midbosses', every draft), Ziggy's art and
  therefore his eye card, the grove's tree art, and every sound. There is no
  music.
- `Sand Burst` on the drafting table is Mika's sand thrown as a two-stage
  burst, parked to be tried before any slot uses it.
- There is no options screen: no volume, window mode, key remapping or
  progress reset.
- Fodder can only move as `wave_line` and `wave_cross` describe.
- Missing parts of ph3's shot API:
  - a hit width per laser (every laser kills at about a third of its drawn
    width);
  - penetrating player shots;
  - a blend mode per bullet;
  - a query for the bullets inside a circle;
  - a cull margin per bullet. `CULL_MARGIN` is global, so a bullet cannot
    leave the field and come back.
- `bullet_clear_circle` turns every Nth cleared bullet into an item in the
  order it sweeps them, not by position.
- Frame cost: the grove is the expensive stage, at roughly 10 ms a frame,
  because it draws hundreds of billboards from GML every frame. Stage one and
  the hall take about 6 ms.
