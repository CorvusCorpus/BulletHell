# Nexarchon

`Nexarchon` is the working title, shown on the rack. The GameMaker project,
its window and its save folder are still named `Bullet Hell`.

A Touhou-inspired danmaku shooter in GameMaker (IDE 2024.14, VM runtime). You
play Szuix, a blue imp who is tired of being everybody's trash mob, flying
through other people's territory and taking their magic. Arrow keys move, Z
shoots, X spends a sigil (the bomb), Shift focuses and shows the hitbox,
Escape pauses. In a conversation Z turns to the next line and X skips it.

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
  placeholder except Mika's non-spells, `Storm Cage` and `Chakram Blitz`,
  which are being built now. The simple
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
  The exception is apparent depth in a 2.5D effect (`depth`), asked for in
  Chakram Blitz: a ring nearer or further looks, and collides, larger or
  smaller.
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
- **The hall's ornament is realistic material work**: fine inlay and
  carving of varying weight, never flat fills or lines of one weight (both
  read as cartoon or MS Paint). Mika's library is fancy and pristine, not a
  ruin: no wear, flaking or tarnish. Motifs must read as Egyptian at a
  glance; a star in a circle doesn't.
- **Pickups are crystals or gemstones** in red, blue and yellow, small and
  partly see-through so they don't compete with the bullets.
- **Grading.** Every encounter (a group of waves, or one boss attack) gets a
  mark: STONE, BRONZE, SILVER, GOLD, AMETHYST. A clean encounter is GOLD; each
  hit costs two rungs and each sigil one; beating the score threshold adds
  one. A stage where every mark is AMETHYST is ABSOLUTE AMETHYST, which is a
  standing, not a sixth tier. The score thresholds lean lenient: decent play
  passes them without aggressive tactics or grazing skill, and keeping your
  fire on a boss (beating the attack about as fast as you can) is enough on
  its own. A boss attack that times out never earns AMETHYST unless it is a
  survival attack.
- **UI is gilt on indigo**: a dark saturated violet ground, small areas of
  bright old gold, crescent and four-point-star motifs, cyan as the accent,
  serif type (Cinzel, Spectral). Aimed at old-school danmaku players; never
  mobile-game or match-3 styling.
- **Gameplay is 2D against a 3D backdrop**, as in Touhou: the 3D look is for
  stage backgrounds only. Foes, bosses and bullets are 2D sprite art.
- **The sand golem (stage three's midboss) is a sand elemental**, a body of
  sand, not a carved-stone construct.
- **Reference art is reproduced faithfully.** When the owner supplies art for
  a character or prop, match its anatomy, ornament and colours rather than
  reinterpreting it. Mika is cut from the owner's own sheet
  (`tools/source/mika_ref.png`), and his ring sprite has its colours baked in
  to match his markings.
- **The painted Szuix commissions are reference only.** No pixels from them
  may ship. Nobody has said whether the in-game pixel sheet
  (`tools/source/szuix_sheet.png`) has the same restriction, so ask before
  building on it. The standing drawing in `tools/source/szuix_ref.png` is the
  owner's own art, given as a placeholder conversation portrait, and may be
  used.
- **Szuix and a stage's boss talk before they fight**, in the same style
  and at the same quality as the spell cut-in. Touhou's pre-fight dialogue
  is the baseline for what it does, not for how it looks. The boss's name
  and title are presented as part of it.

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
- The same goes for scripts: an IDE left open saves its cached copy of a
  `.gml` back over one edited outside it (it did so to `selftest` when the
  game was run from it), unless the owner reloads when it asks. If the IDE
  is open, check an edit is still on disk before relying on it.
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
| `obj_game` | One run: timeline, player, bosses, conversation, HUD. Its Create calls `run_clear_field()` first, because the pools are globals that outlive a room. |
| `obj_selftest`, `obj_shot` | Test runner; screenshot poser. |

| Scripts | Contents |
|---|---|
| `constants`, `palette`, `bullet_table`, `grove_table`, `sanctum_table` | Macros and tables. All but `constants` are generated. |
| `danmaku_functions` | Bullet pool, the firing API, the event queue, collision, graze, the player's shots |
| `laser_functions`, `ring_functions`, `item_functions`, `enemy_functions`, `fx_functions` | The other pools |
| `player_functions` | Player, input, the sigil and its seals, grace, hitbox |
| `boss_functions` | Boss phase machine, movement modes, ceremony timing |
| `stage_functions` | Stage timeline, gates, wave helpers, encounter windows, `run_clear_field` |
| `stage_ziggy`, `stage_grove`, `stage_sanctum`, `mika_nonspells`, `mika_storm_cage`, `mika_chakram_blitz` | Stages one to three: timelines, bosses, attacks. `stage_list()`, the roster of all stages, lives in `stage_ziggy`. |
| `sanctum_waves`, `sanctum_ring_waves`, `sanctum_foes`, `sanctum_golem` | Stage three's way to Mika: its timeline and fodder waves (`sanctum_wave_table()`), the two waves of his rings, its foes' look and deaths, and the sand golem |
| `enemy_routes` | Fodder flying routes of legs (`leg_curve`, `leg_orbit`, `leg_aim`, `leg_path`, `leg_exit`, `leg_appear`), spawned by `foe_spawn` / `ev_foe` |
| `title_card` | The stage title card a timeline plays (`wave_title_card`) |
| `spell_cutin`, `cutin_table` | A spell's cut-in (`cutin_draw`), and where its portrait's eyes are (generated by `make_mika.py`) |
| `stage_drafts` | The drafting table, plus `rack_list()`: the roster and the extra cards the rack shows |
| `stage_preview` | The review card, which flies stage three's hall with no enemies |
| `stage_sanctum_old` | Stage three as it was before Mika's rebuild, frozen on its own rack card. Delete it once his slots are filled, along with its rack line, `test_old_sanctum`, its line in `test_stage_run` and `stage_is_old_draft`. |
| `practice_functions` | Single-attack practice |
| `rank_functions`, `rank_card` | Encounter grading and the medal card |
| `bg_functions`, `bg_corridor`, `bg_grove`, `bg_sanctum` | Backgrounds: dispatch and stage one's parallax, the corridor projection, stage two's wood, stage three's 3D hall |
| `hud_functions`, `ui_functions` | The console, the boss's health rail, menus; drawing helpers, fonts, gauges |
| `audio_functions`, `save_functions` | The sound mixer; saving |
| `talk_functions`, `talk_table`, `name_card`, `mika_talk` | A conversation before a boss fight (`talk_draw`) and where its portraits' eyes are (generated by `make_portraits.py`); a boss's name card (`namecard_draw`); what Mika and Szuix say |
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
- They hurt to touch, tested swept along the way both the ring and the
  player moved that frame (the player keeps `px`/`py` for it), so a thrown
  ring can't step over the player.
- They can be charged, which widens the lethal band after a warning, and
  linked into a lethal arc.
- They carry an `act` that fires like a boss attack.
- They can flash the lane they are about to be thrown down
  (`ring_lane_flash`), drawn under every ring. It is decoration and never
  kills.
- They can fake depth: `depth` scales a ring's size, drawn and collided
  alike (`ring_radius`); `shade` dims it; and a ring `behind` its caster is
  drawn before the enemies (`ring_draw_behind` before `enemy_draw`) and
  neither hurts, grazes nor blocks (`ring_touchable`).
- They are culled once wholly off the field, unless `cull` is off (Storm
  Cage's rings ride the player past the walls).

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
`{kind, name, col, bg, hp_end, time, attack, move?, at?, fire_at?, par?,
score?, survival?}`, and `attack(_e, _g, _t)` is called every frame with the
frames elapsed. The last three are for grading (see below).

- A phase ends on health (checked first) or on time, and either way the bar
  is pulled to `hp_end`. A capture needs the spell broken with no hit and no
  sigil.
- A named spell gets a cut-in (`spell_cutin`) and its boss's spell
  background. It waits `BOSS_SPELL_LEAD` (the cut-in's length) before firing,
  and a boss can't be hurt during its entry, its declarations or the pause
  between phases (`boss_vulnerable`). The cut-in is drawn from the boss's
  `cutin_t`: a tilted band with the caster's portrait (`def.cutin`) whose
  eyes snap open partway, its own cue for the cut that opens it, the
  declaration cue timed so its gong lands as the eyes open
  (`boss_cutin_step`), and the spell's name on a plate that then flies to
  its place under the rail. The name is gilt through `sh_gilt_text`.
- `move` is a `BossMove`: `Drift` (the default), `Close`, `Track`, `Fixed`
  or `Step`. Read it as `_p[$ "move"] ?? BossMove.Drift`, because a bare read
  of a missing struct field raises. `at` (`{x, y}`) gives a `Fixed` attack its
  own station instead of the boss's; the boss glides there during the pause
  before it.
- Before every attack the boss plays a charge cue (`boss_charge`, the Hex's
  pull), `BOSS_CHARGE_LEAD` frames before the attack's first shots. Those
  come on the attack's first frame unless the row's `fire_at` says later;
  Mika's rows set it, because the rings he puts down first are no threat.
- `def.final == false` makes a midboss.
- A final boss is named by its card (`name_card`) before its first attack:
  the cut-in's band put to a name. A cut opens into a band, the boss's
  `title` comes in along it, its name slams in over that in gilt with the
  declaration's gong, and when the card is let go the name flies up to its
  plate on the rail (`hud_step` shows it there from then; `boss_named`). It
  is drawn from the boss's `card_t` and `card_out`. With nothing to say the
  boss gets the card during its declaration (`BOSS_DECLARE_TIME`), with
  itself drawn in front of the band.
- A boss with `def.talk` (a function returning its lines) and
  `def.portrait` arrives talking: see Conversations.
- `def.music` is a boss's theme, which takes over from the stage's when it
  spawns, or at its name card if it arrives talking.
- Phase tables are built by functions (`ziggy_phases()` and so on), never
  shared, because phase structs are mutable.

**Conversations** (`talk_functions`). `wave_boss` starts one as a boss with
`def.talk` arrives (`talk_begin`), in a stage and in a practised whole
fight alike; a practised attack puts the boss straight on the attack, so it
has none. The boss holds its
station until it ends (`boss.talking`), its rail stays stowed until it is
named (`boss_announced`), and its theme is held back until then
(`music_keep`).

- A script is a list of `talk_say(who, text, face?)` lines and one
  `talk_card()`, the beat on which the name card plays. A script without one
  still ends in the card, from the boss's own declaration.
- Lines are set in `fnt_talk`, a sprite font of ASCII 32 to 126, wrapped to
  the plate, at most `TALK_ROWS` rows. `test_talk` reads every script on the
  rack for both.
- Z shows the rest of a line and then turns to the next (held, it hurries);
  X skips to the name card and out. Z does nothing until it has been let go
  once, because the player arrives holding it. The player gets no input
  while it is had (`talk_busy`).
- On screen: the field veiled; a standing portrait each side, the speaker
  lit, rimmed in their colour and forward, the listener dimmed and back; a
  blade of the speaker's colour behind each, at the cut-in's tilt; the words
  typed onto a plate of the cut-in's glass, with the speaker's name on a tab
  standing on their end of it (`? ? ?` for a boss not yet named).
- A portrait is pairs of frames, as drawn then eyes shut (the blink), its
  origin midway between the eyes; `talk_say`'s `face` picks the pair.
  `talk_art` gives its eyes and the colour its owner is lit in.
- The script asset is `talk_functions` because a run keeps its conversation
  in a variable called `talk`: a script asset of the same name shadows the
  variable, and the read throws.

**Stages.** A stage def is `{id, name, subtitle, needs, make_bg, build,
bosses, music?}`.

- `build` returns a timeline of `ev(at, fn)` and `ev_gate(at)` entries. A gate
  freezes stage time until no fodder is on the field, after a short grace so
  a gate placed just after a spawn doesn't release at once.
- Stage time doesn't advance while a boss is up.
- By default a group of waves is graded as the window during which fodder is
  on the field (`stage_encounter_step`). A timeline that marks its waves
  with `ev_wave(at, survival)` (stage three) is graded wave by wave instead:
  a wave opens at its marker and closes when the gate after it releases,
  which in such a timeline also waits for rings; closing dispels its
  leftover bullets, so the medal never hangs over live fire. A `survival`
  wave (rings only) meets its threshold by being got through.
  `stage_count_encounters` counts either kind.
- A timeline plays its title card with `ev(at, wave_title_card())`; the
  card's art is the def's `card` frame (`tools/make_titles.py`), and a def
  without one shows none.
- `bosses` lists `{name, spawn, phases, turned?}` for practice and counting;
  `turned` starts practice in the stage's second-half background.
- A def whose `id` is empty can never write a clear: `progress_record` refuses
  it. Practice, the drafting table, the review card and the old stage three
  all rely on that.

**Grading** (`rank_functions`). A boss attack's score threshold is its clear
award plus the speed award it would pay if broken exactly at its par. Par is
its share of the boss's health at full fire (every shot landing), times
`RANK_PAR_SLACK`, capped at the clock. So breaking it by par meets the
threshold with no grazing, and each second past par has to be made up with
`RANK_GRAZE_RATE` grazes. A timeout can't meet it unless the row has
`survival: true`, and the medal card then shows TIME OUT. A row's `par` or
`score` overrides the default. A group of waves' threshold is
`RANK_WAVE_SHARE` of what its fodder is worth (each one killed, and its gold
collected). All three constants are unplayed first guesses.

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
placeholders from `tools/make_sfx.py`.

Music works the same way: `music(snd)` only asks, and `music_step` (run by
`sfx_step`) plays the frame's last request, crossfading over `MUSIC_FADE`.
Leaving the room fades it out, and `music_hold` pauses it with the pause
menu. Only stage three has music: two placeholder tracks from OpenTracks,
made by `tools/make_music.py`. OpenTracks' licence forbids redistributing
the audio and the repository is public, so the downloads and OGGs are
git-ignored; on a fresh clone the build needs them fetched again (the
script names each track's page).

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
- **Room** (stage three, `bg_sanctum`): real 3D with a perspective matrix
  and the depth buffer, drawn into its own surface. Bays are frozen vertex
  buffers (position, normal, colour, texcoord).
  - `sh_hall` lights every surface per pixel: the night through the open roof
    (the hall is a trench, so what a direction sees of the sky is worked out
    exactly from the two wall tops), a moon off to one side that the walls
    shadow, and the fires and orbs. The lights repeat with the bays, so the
    shader places them itself from one bay's positions (`hall_shader`); the
    positions come from the same GML functions as the geometry
    (`hall_torch_x`, `hall_orb_x`).
  - A buffer's surface is set by `hall_mat` before its submit. The hall's
    carved and paved textures carry a gloss map in their alpha; drawn with a
    material whose gloss-map flag is off, that alpha reads as coverage and the
    surface goes see-through.
  - The flicker and the waking curve exist twice, in `sh_hall` and in GML
    (`hall_flicker`, `hall_ignite`), so a flame card matches its light. Change
    both together.
  - Fires are cards rebuilt every frame (`hall_draw_flames`), and the polished
    floor mirrors them (`hall_draw_reflections`, drawn between the pavement
    and everything standing on it). Then the hall is bloomed and graded
    (`hall_post`, `sh_hall_post`) before it goes on screen.
  - The opening (`intro`, `HALL_INTRO_TIME`) is half a minute of the hall
    waking: black, a moonbeam on the pavement, the torches catching in a front
    that runs away down the hall, the camera tilting forward and gathering
    speed. The parapet braziers catch on the reveal instead. Stage three's
    timeline is pushed back by `SANCTUM_OPENING` so the first wave arrives
    after the dark.
  - The hall's lit textures are in the `Hall` texture group, which is
    mipmapped. The draw turns mipmapping on with `mip_markedonly`; `mip_on`
    mips every texture drawn, every frame, and ran the game at one frame a
    second.
  - The hall holds buffers and surfaces the garbage collector can't reach;
    `bg_free` (from each owner's Clean Up) frees them.
  - `vertex_submit` takes one texture, so a buffer may only hold geometry
    UV-mapped from the sprite frame it is submitted with.
    `check_hall_frame_textures` and `check_hall_buffer_textures` enforce this.
    A wrong pairing looks fine until the atlas repacks, then shows garbage
    intermittently.
  - Restore every GPU state you change (culling, shader, depth, mipmapping).
    A leak breaks the HUD.

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
| `medal_art.py` | Imported by `make_ui.py` (run alone, it only writes a preview): the rank medals, rendered in their own colours from height fields shaded as metal, enamel, cut stones and granite. The card's medal with its reverse and edge (for the coin spin, `medal_draw`) and a spell's star; the console's medals and sockets. |
| `make_enemies.py`, `make_player.py`, `make_boss.py` | Fodder (stages one and two, tinted); Szuix from his sheet; Ziggy, whose art is a placeholder. `make_boss.py` states what a painted replacement must keep. |
| `cel_art.py` | Imported by the two below: 2D sprite illustration in code (cel-shaded parts with line work, lit from the upper left) |
| `make_sanctum_foes.py` | Stage three's foes in their own colours (armillary sphere, spellbook, soul-flame), the sand golem's body, glow and fist, and pieces for deaths (pages, gilt, grit, the summoning glyph) |
| `make_titles.py` | The stages' title cards, one frame per stage. Its `CARDS` table must match the stage defs' names and subtitles (`check_title_cards_agree`). |
| `make_mika.py`, `make_rings.py` | Mika from the owner's sheet (a skinned rig; `MIKA_RIG_DEBUG=1` draws its regions over the art), his cut-in portrait and `scripts/cutin_table`; Mika's ring |
| `make_portraits.py` | The conversation's standing portraits and `scripts/talk_table`: Szuix cut from the owner's drawing (`tools/source/szuix_ref.png`, its painted wall keyed out by colour), Mika from his sheet. Placeholders: one drawing each, with the eyes painted shut for a second frame |
| `make_bg.py`, `make_grove.py`, `make_sanctum.py` | Stage one's layers; stage two's scenery and `scripts/grove_table`; stage three's materials, fire and statue, and `scripts/sanctum_table` |
| `sanctum_glyphs.py`, `sanctum_relief.py` | Imported by `make_sanctum.py`: a set of hieroglyphs and the column layout that sets them in squares; and the material work (inlay, sunk and raised relief, grooves, worn gilding, marble, basalt) with the larger ornament (the winged sun, cartouche, lotus frieze, scarab) |
| `make_sfx.py` | All sound effects |
| `make_music.py` | The placeholder music, from downloads in `tools/source/music/`: normalised, looped, streamed |

- Most art is luminance and gets tinted at draw time, so one set of fodder
  serves stages one and two. Mika's ring, the rank medals, stage three's
  foes and golem, and characters taken from reference sheets keep their own
  colours.
- A cut-in portrait (`spr_cutin_*`) is two frames, eyes shut then open,
  transparent round the head, its origin where the band's centre line
  crosses it. It is drawn as textured primitives cut to the band
  (`draw_sprite_poly`, which allows for the page's cropping). Mika's is cut
  from his sheet with the eyes painted shut; a commissioned pair can replace
  it frame for frame, with its eyes re-measured into `cutin_table`.
- Stage three's foes and golem are 2D illustration drawn in code
  (`cel_art`): each part cel-shaded (a shade band on the edges away from the
  light, a lit rim toward it) with its own line work. The golem's sand is
  ribbons laid along swirling currents over a dark, fire-lit hollow, sliding
  along them frame to frame; its body and glow are animated in step.
- A bullet is a bright core in a saturated body with a hard dark contour
  (`cut_finish` in `art_common`). The dark contour is what additive scenery
  can never produce. Each shape is one sprite with one frame per colour; get
  the index from `bullet_frame`. Oriented shapes point right at angle 0.
- Some numbers exist both in a generator and in `constants`.
  `check_project.py` compares the font metrics, the near layer's keep-out,
  the rotunda's scale and the medals' sizes. Nothing compares `UI_CORNER_DEPTH` or `BOSS_INK_ABOVE`,
  so re-measure those by hand when their art changes.
- `check_sprites_not_blank` refuses a sprite with an empty frame, which is how
  IDE damage shows up. `BLANK_FRAMES_OK` lists the few sprites whose empty
  frames are intentional.
- Szuix is scaled up by NEAREST to 6x, blurred, then LANCZOS down, all with
  premultiplied alpha: the sheet's transparent pixels are white.
- The Bastet's outline follows the owner's reference statue, written down as
  points in `make_sanctum.py` (`BASTET_REF`). Her card is a relief of
  separate parts (`BASTET_PARTS`), so her legs, haunch and ears each read.
  The far ear showing behind the near one is intended (the owner's), for a
  sense of depth. Her eyes are Ashiah's red. In the hall she is swept into a
  solid part by part (`BASTET_SOLIDS`, written to `scripts/sanctum_table`),
  each part round its own axis at her near or far side, so from above her
  legs are separate forms. The solid samples texels just outside her
  outline, so her sprite carries its colour out past it and the hall draws
  her ignoring alpha (`HALL_MAT_STATUE`); an alpha-tested statue shows holes
  and cracks. Her plinth is sized from her sprite, so it follows if she
  changes.
- Fonts are sprite fonts built from bundled OFL faces. Don't bake in the
  system's Microsoft fonts. There is no kerning, which shows on Cinzel's `Q`.
  Re-running `make_fonts.py` rewrites every font's PNGs with different bytes
  and the same pixels; restore the ones that weren't meant to change.

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
- A primitive's edge isn't anti-aliased, and on a slant it shows as steps.
  The cut-in, the name card and a conversation fill every bar, rule and
  plate through `draw_poly_shaded` (`draw_poly` and `draw_poly_ramp` call
  it), which draws the fill half a pixel in and fades a fringe out across the
  outline. Two such shapes that share an edge show a faint seam, so a line
  with a varying alpha is one polygon, not segments (`talk_blade_line`).
- A primitive textured with `sprite_get_texture` reads UVs in the sprite's
  own 0–1 space, not the texture page's.
- The `Default` texture group crops transparent borders, so a sprite's UVs on
  the page may cover only part of it (`sprite_get_uvs` entries 4–7 say how
  much). Mapping across them as if they were the whole sprite made the hall's
  flame strip slide off its flames. The hall's sprites are in the uncropped
  `Hall` group (`test_hall_uncropped`), and `hall_uv` allows for cropping.
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
- **A wave of stage three**: a function `(events, t)` in `sanctum_waves` that
  pushes `ev_foe` spawns (each a kind, a start, health, a route of legs from
  `enemy_routes`, and a fire function) at `t` plus local frames and returns
  its length, and a row in `sanctum_wave_table()`. A foe only fires while
  inside the field. Photograph it alone with `python tools/shot.py
  sanctum_w3` (seven seconds in; `--burst` offsets count from there).
- **A ring attack**: `ring_new`, then `ring_attach`, `ring_charge` and
  `ring_link`. Where possible, give the ring its whole behaviour as an `act`
  when it is created.
- **A stage**: a def in `stage_list()`, a script with its timeline and
  bosses, and a background: a palette in `make_bg.py` for parallax, or a
  `bg_*` function returning a corridor or room struct. Put `wave_bg_omen()`
  in the timeline if its second half changes.
- **A bullet shape**: an entry in `SHAPES` in `make_bullets.py` returning a
  `Cut`. Re-run it and `bullet_table` follows.
- **A conversation**: a function returning its lines (`talk_say`, and one
  `talk_card`), named as the boss def's `talk`, and a portrait sprite as its
  `portrait` (`make_portraits.py`). Play it without the stage by practising
  the boss's whole fight (X on the rack). Photograph Mika's with `python
  tools/shot.py talk --burst ...` (Z is pressed every `SHOT_TALK_BEAT`
  frames) and its name card with `talk_card`; `declare` is a card with no
  conversation.
- **A screenshot scene**: add it to `shot_scene_list()` and to `SCENES` in
  `tools/shot.py`.

## Current state

What's playable:

- The rack.
- Stage one: Ziggy, and the Warden as midboss.
- Stage two: Velka, and the Husk as midboss. The wood turns to blood halfway
  through.
- Stage three: in the 3D hall (lit per pixel by torches, orbs and the open
  sky, with a half-minute opening in which the hall wakes), ten waves each
  graded on its own, the title card after the first, the sand golem after
  the fifth, and Mika after the tenth, who talks with Szuix before the fight
  (placeholder lines). Waves five and ten are Mika's rings
  roaming the hall, to be outlasted (`sanctum_ring_waves`). The waves and
  the golem's three non-spells are placeholders in the intended shape, each
  to be replaced in turn; each wave has a shot scene (`sanctum_w1` ...
  `sanctum_w10`), as do the golem's attacks (`golem_n1` ... `golem_n3`) and
  the card (`title_card`).
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
| S1 | Written, in playtesting: `Storm Cage`. Three rings strung with lightning ride round the player; a sandstorm floods the field; rings stop grains; on a bolt amber sand bursts into slow falling glass and ember grit burns away. |
| S2 | Written, in playtesting: `Chakram Blitz` (inspired by Murasa's anchors in Touhou 12). Two rings rest at his sides and are thrown at the player in turn; while one waits it loops once round him in 2.5D, larger in front and smaller, dimmer and harmless behind him, timed to be back at rest as its wind-up starts. Each winds up aimed at the player, locks its aim with a brief flash of its lane, charges, is thrown fast with a sharp acceleration and a smooth braking stop, lays a braided double-helix rope that holds still and then comes apart, comes to rest short of the wall with its spin still building like a yo-yo's, sprays a brief pinwheel of bullets, and is pulled back. One ring is out at a time, and the gap between throws shrinks over the attack. |
| S3, S8 | Old placeholders: `Three Open Gates`, `Grand Orrery` |
| S4–S7 | Stubs (`Unwritten Spell 4` to `7`) |

Known gaps:

- Nothing has been balanced against a human; every tuning number is a first
  guess.
- These are placeholders: all attacks except the Hex, Mika's non-spells,
  `Storm Cage` and `Chakram Blitz` (Ziggy's, Velka's first five, the
  midbosses', stage three's ten waves, every draft), Ziggy's art, every
  boss's cut-in portrait (all show Mika's, shut eyes painted over his
  sheet), the grove's tree art, every sound, and both music tracks. Only
  stage three has music. So are the conversation's two portraits (one
  drawing each, so no expressions) and every line of it.
- Only Mika has a conversation. Ziggy and Velka get the name card alone.
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
  because it draws hundreds of billboards from GML every frame. Stage one
  takes about 6 ms, and the hall about 5 ms with an empty field (the hall's
  flames, reflections and sand build their vertices without allocating, so
  the garbage collector stays quiet).
