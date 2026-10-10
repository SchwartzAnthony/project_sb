# Suno prompts: every sound and music track

Round AN, 10 Oct 2026. One prompt per sound in the game, plus the new ones you asked for.

## How to use this

1. Find the sound below. Paste the **Style** line into Suno's *Style of Music* box, the **Exclude** line into *Exclude Styles*, and the **Lyrics** lines into the *Lyrics* box.
2. Download the result as **mp3 or wav** and rename it to the **File** name given (for example `suno_goal_horn.mp3`).
3. Drop it into `assets/audio/`. That's it. The game plays it straight away; no CSV edit needed.

Every row of `data/Audio.csv` now has a Suno slot written into its Sound column: `suno_goal_horn | bav_goal` means "play `suno_goal_horn` if it's there, otherwise the Bavarian one we have now". To go back, delete or rename your file. `| -` at the end means "or nothing yet": that sound is silent until your file arrives.

**Sound effects come out of Suno much longer than the game needs.** Each one below says how long it should be. Use Suno's crop/trim to keep just that part, or drop the long file in and ask me in a thread to trim it.

**Volume.** Suno files are mastered loud. If one is too loud or too quiet, change that row's **Volume** in `data/Audio.csv` (-6 is half as loud).

### The house sound (applies to every effect)

Shared **Exclude** line for all sound effects, unless a sound says otherwise:

```
vocals, singing, lyrics, choir, reverb, echo, hall, synths, electric guitar, EDM, drum machine, long intro, fade in
```

Suno's *Instrumental* switch: **on** for every effect, unless the sound asks for a shout or crowd. Winning sounds are cheeky and happy, losing sounds sad and comic, never harsh.

---

## A. The new sounds you asked for

### Priority check (duel window: ABILITY PRIORITY comes up)
- **File:** `suno_duel_priority_check.mp3` · **Length:** about 0.8 s · Row `duel_priority_check` (new; silent until the file is there)
- **Style:**
```
single Bavarian sound effect, quick snare drum roll into one bright glockenspiel note, a little suspense, short sting, oompah band instruments, dry studio, under one second
```
- **Lyrics:** `[Instrumental] [Snare roll] [Glockenspiel ding] [End]`

### Ability check (the gold box lands on an ability)
- **File:** `suno_duel_ability_check.mp3` · **Length:** about 0.5 s · Row `duel_ability_check` (new)
- **Style:**
```
single Bavarian sound effect, one soft zither pluck and a wooden beer mat tap, curious and expectant, tiny sting, dry studio, half a second
```
- **Lyrics:** `[Instrumental] [Zither pluck] [End]`

### Power check (POWER CHECK and both numbers ringed)
- **File:** `suno_duel_power_check.mp3` · **Length:** about 1 s · Row `duel_power_check` (new)
- **Style:**
```
single Bavarian sound effect, two heavy bass drum hits and a low tuba note held, tense and weighty, like two strongmen squaring up at a beer tent, dry studio, one second
```
- **Lyrics:** `[Instrumental] [Bass drum, bass drum] [Tuba hold] [End]`

### Ability triggers (the ability goes off)
- **File:** `suno_duel_ability_success.mp3` · **Length:** about 0.9 s · Row `duel_ability_success`
- **Style:**
```
single Bavarian sound effect, two beer steins clinking then a fast rising glockenspiel run, joyful Prost moment, sparkly and cheeky, dry studio, under one second
```
- **Lyrics:** `[Instrumental] [Clink] [Glockenspiel run up] [End]`

### Drinking (a player drinks a beer or a keg)
- **File:** `suno_drink_big.mp3` · **Length:** about 1.5 s · Row `drink_big` (the drinking window; the in-match drinking thread can name this row too)
- **Style:**
```
foley sound effect, a man gulping beer from a big stein, three loud happy gulps, then a satisfied "ahh", comic and warm, Oktoberfest, close microphone, dry
```
- **Exclude:** use the shared line but take out `vocals`.
- **Lyrics:** `[Gulp] [Gulp] [Gulp] (Ahh!) [End]`

### Item used (an item mends somebody)
- **File:** `suno_item_use.mp3` · **Length:** about 0.8 s · Row `item_use`
- **Style:**
```
single Bavarian sound effect, a cork popping and a warm two-note zither pluck going up, healing and cosy, dry studio, under one second
```
- **Lyrics:** `[Instrumental] [Pop] [Zither, two notes up] [End]`

### Menu open (a window or the Escape menu opens)
- **File:** `suno_menu_open.mp3` · **Length:** about 0.5 s · Row `menu_open` (new; plays for every window over the base and for the Escape menu)
- **Style:**
```
UI sound effect, a heavy wooden tavern menu board flipped open, short wooden creak and a soft accordion breath, dry, half a second
```
- **Lyrics:** `[Instrumental] [Wood creak] [End]`

### Flag (the blue flag banners on the base)
- **File:** `suno_banner_flutter.mp3` · **Length:** about 0.7 s · Row `banner_flutter`
- **Style:**
```
foley sound effect, a big cloth flag snapping twice in a strong mountain wind, a quick whoosh, crisp and close, no music, dry
```
- **Lyrics:** `[Instrumental] [Flag snap] [End]`

---

## B. Match sounds

### Kick-off
- **File:** `suno_kickoff_whistle.mp3` · **Length:** 0.7 s · Row `kickoff_whistle`
- **Style:** `Bavarian sound effect, one round referee whistle blast with a deep tuba "oom" underneath, a fresh start, dry studio, under one second`
- **Lyrics:** `[Instrumental] [Whistle] [Tuba oom] [End]`

### Play Maker
- **File:** `suno_play_maker_whistle.mp3` · **Length:** 0.8 s · Row `play_maker_whistle`
- **Style:** `Bavarian brass sting, a single trumpet "ta-DAA!" fanfare, bright and confident, oompah band, dry studio, under one second`
- **Lyrics:** `[Instrumental] [Trumpet ta-daa] [End]`

### Star Player switch
- **File:** `suno_hold_up_whistle.mp3` · **Length:** 1.2 s · Row `hold_up_whistle`
- **Style:** `Bavarian sound effect, two quick referee whistle blasts then a glockenspiel run climbing up, a star is coming on, exciting, dry studio`
- **Lyrics:** `[Instrumental] [Two whistles] [Glockenspiel run up] [End]`

### Goal (you score) — fun
- **File:** `suno_goal_horn.mp3` · **Length:** 2 s · Row `goal_horn`
- **Style:** `Bavarian oompah brass band goal fanfare, bass drum boom then "ta-ta-DAAA!" on trumpets and tuba, a cow bell shaking, triumphant and silly, dry studio, two seconds`
- **Lyrics:** `[Instrumental] [Bass drum] [Brass fanfare] [Cow bells] [End]`
- Kept quieter on purpose (you said the goal cheer was too loud). Leave crowd noise out of this one: the roar is its own sound (`crowd_goal`).

### Goal by a Star — extra fun
- **File:** `suno_goal_horn_star.mp3` · **Length:** 2 s · Row `goal_horn_star`
- **Style:** `huge Bavarian brass band chord after one big cannon boom, Oktoberfest salute, glorious and over the top, cymbal crash, dry studio, two seconds`
- **Lyrics:** `[Instrumental] [Boom] [Full brass chord] [End]`

### Crowd roar after a goal
- **File:** `suno_crowd_goal.mp3` · **Length:** 1.6 s · Row `crowd_goal`
- **Style:** `beer tent crowd clapping along in polka time, clap clap clap-clap-clap, cow bells shaking, happy cheering, not too loud, short`
- **Exclude:** `singing, lyrics, choir, reverb, echo, synths, music, instruments`
- **Lyrics:** `[Crowd claps] (Hey!) [End]` with *Instrumental* off.

### Goal against — sad
- **File:** `suno_goal_against.mp3` · **Length:** 1.5 s · Row `goal_against`
- **Style:** `sad comic sound effect, a soft tuba going "wah... wahhh" downhill, a disappointed beer tent sigh, gentle, dry studio`
- **Lyrics:** `[Instrumental] [Tuba wah wah] [Sigh] [End]`

### Shot
- **File:** `suno_shot_kick.mp3` · **Length:** 0.2 s · Row `shot_kick`
- **Style:** `foley sound effect, one hard leather football kick, boot through ball, punchy thump, dry, no music`
- **Lyrics:** `[Instrumental] [Kick] [End]`

### Keeper save
- **File:** `suno_keeper_save.mp3` · **Length:** 0.2 s · Row `keeper_save`
- **Style:** `foley sound effect, goalkeeper leather gloves catching a football, one clean slap, dry, no music`

### Big save (shot of 4 power or more)
- **File:** `suno_keeper_big_save.mp3` · **Length:** 0.6 s · Row `keeper_big_save`
- **Style:** `foley sound effect, a hard glove slap on a football and a timpani thud under it, heroic, dry`

### Ability fizzles — sad
- **File:** `suno_duel_ability_fail.mp3` · **Length:** 0.8 s · Row `duel_ability_fail`
- **Style:** `comic Bavarian sound effect, a dud cork "pfft", beer foam going flat, one low tuba bloop, disappointed, dry studio`

### Power check won — fun
- **File:** `suno_duel_power_victory.mp3` · **Length:** 0.7 s · Row `duel_power_victory`
- **Style:** `cheeky tuba "oom-PAH!" sting with a cymbal tap, winning, playful oompah, dry studio, under one second`

### Power check lost — sad
- **File:** `suno_duel_power_fail.mp3` · **Length:** 0.8 s · Row `duel_power_fail`
- **Style:** `sad tuba drooping down two notes, comic loser sound, gentle, dry studio, under one second`

### Beer poured (a brew drunk)
- **File:** `suno_brew_pour.mp3` · **Length:** 1 s · Row `brew_pour`
- **Style:** `foley sound effect, beer poured from a tap into a glass stein, foamy fizz, close and crisp, no music, dry`

### Card hover (quiet, plays a lot)
- **File:** `suno_card_hover.mp3` · **Length:** 0.1 s · Row `card_hover`
- **Style:** `UI sound effect, the tiniest soft knock on a cardboard beer mat, very short, very quiet, dry`

### Card picked
- **File:** `suno_card_lock.mp3` · **Length:** 0.3 s · Row `card_lock`
- **Style:** `UI sound effect, two knocks on a wooden beer table, tock-tock, decisive, dry`

### Full time: won — fun
- **File:** `suno_full_time_win.mp3` · **Length:** 4 s · Row `full_time_win`
- **Style:** `happy Bavarian polka flourish, tuba oom-pah, horns on top, cow bells, glockenspiel sparkle, final whistle feeling, victorious and silly, big ending chord, dry studio, four seconds`
- **Lyrics:** `[Instrumental] [Polka flourish] [Big ending] [End]`

### Full time: lost — sad
- **File:** `suno_full_time_loss.mp3` · **Length:** 3 s · Row `full_time_loss`
- **Style:** `a lone tuba sinking down four notes, the last one wobbling sadly away, comic sorrow, quiet, dry studio`

### Full time: draw
- **File:** `suno_full_time_draw.mp3` · **Length:** 2.5 s · Row `full_time_draw`
- **Style:** `Bavarian oompah band starts a happy phrase and stops halfway, unresolved "oom-pah... hm?", shrug, comic, dry studio`

### Foul whistle
- **File:** `suno_foul_whistle.mp3` · **Length:** 0.5 s · Row `foul_whistle`
- **Style:** `one short sharp referee whistle blast, sound effect, dry, no music`

### Yellow card
- **File:** `suno_foul_yellow.mp3` · **Length:** 1.2 s · Row `foul_yellow`
- **Style:** `referee whistle, beer tent crowd going "oooh", one low tuba "uh-oh" note, comic warning, short`
- **Lyrics:** `[Whistle] (Oooh!) [Tuba] [End]` with *Instrumental* off.

### Red card
- **File:** `suno_foul_red.mp3` · **Length:** 2 s · Row `foul_red`
- **Style:** `long referee whistle, a dark brass chord, beer tent crowd booing, dramatic sending off, short`
- **Lyrics:** `[Long whistle] [Dark brass] (Booo!) [End]` with *Instrumental* off.

---

## C. Adventure and fight sounds (these play many times a second, keep them tiny)

| Sound | File | Length | Style |
|---|---|---|---|
| Player takes the ball | `suno_ball_tap.mp3` | 0.08 s | `foley, the tiniest scuff of a boot on a leather football, very short, dry` |
| Kick on the run | `suno_ball_kick.mp3` | 0.15 s | `foley, short dry kick of a leather football, dry, no music` |
| Ordinary hit | `suno_hit_soft.mp3` | 0.1 s | `foley, one knock on a wooden beer bench, short and plain, dry` |
| Big hit | `suno_hit_heavy.mp3` | 0.25 s | `foley, a full glass beer stein slammed onto a wooden table, low thud, dry` |
| Enemy finished off | `suno_enemy_down.mp3` | 0.6 s | `comic sound effect, three wooden knocks tumbling down the scale then a thud on floorboards, dry` |
| One of yours hurt | `suno_player_hurt.mp3` | 0.2 s | `foley, a muffled punch and a small wince, dry` |
| One of yours exhausted | `suno_player_drop.mp3` | 0.8 s | `foley, a heavy body flopping on grass, then a tired tuba sigh going down, sad and comic` |
| Combo comes off | `suno_combo_ping.mp3` | 0.3 s | `bright Alpine cow bell and one glockenspiel ding, happy, dry` |
| The big Adventure shot | `suno_shot_heavy.mp3` | 0.5 s | `foley, the hardest kick of a leather football with a timpani boom, powerful, dry` |
| Enemy powering up | `suno_enemy_windup.mp3` | 0.8 s | `a wooden cuckoo clock ticking, tick tock tick tock, ominous but quiet, dry` |

Lyrics box for all of these: `[Instrumental] [End]`.

---

## D. Menus and the base

| Sound | File | Length | Style |
|---|---|---|---|
| Point at a button | `suno_menu_hover.mp3` | 0.1 s | `UI sound, the lightest touch on a zither string, very soft, dry` |
| Press a button | `suno_menu_click.mp3` | 0.15 s | `UI sound, one knock on a wooden plank, dry` |
| START | `suno_menu_start.mp3` | 0.6 s | `Bavarian brass sting, tuba "oom-PAH!" with a trumpet on top, let's go, dry studio` |
| Back / Quit | `suno_menu_back.mp3` | 0.3 s | `UI sound, two wooden knocks falling in pitch, dry` |
| Paying | `suno_coin_register.mp3` | 0.6 s | `foley, coins dropped into a stoneware beer mug and a little shop bell, dry` |
| Böller salute | `suno_explosion_heavy.mp3` | 1.2 s | `one deep black powder cannon boom echoing across an Alpine valley, Böller salute` (leave `echo` out of Exclude for this one) |
| Brewery building | `suno_bld_brewery.mp3` | 0.9 s | `foley, a copper brewing kettle bubbling and hissing, warm, dry` |
| Pub building | `suno_bld_pub.mp3` | 0.8 s | `one squeeze of a Bavarian accordion and a beer stein clink, cosy, dry` |
| Club House | `suno_bld_club_house.mp3` | 1 s | `foley, football boots stomping on wooden floorboards and a coach's short whistle, dry` |
| Dorms | `suno_bld_dorms.mp3` | 2 s | `foley, one big comic snore, a footballer sleeping, warm, dry` (*Instrumental* off, Lyrics `(Snore) [End]`) |
| Training Ground | `suno_bld_training.mp3` | 1.5 s | `foley, a football thumped against a wooden board, a chaffinch singing, a coach's whistle, outdoors` |
| Trophy Room | `suno_bld_trophy.mp3` | 1 s | `one clear ring of a small bell and a sparkle, a trophy set down, proud, dry` |
| Traveling Tavern | `suno_bld_tavern.mp3` | 1.6 s | `foley, a horse clip-clopping, an old wooden wagon creaking, a mug set on a counter` |
| Door opening | `suno_door_open.mp3` | 0.8 s | `foley, an old heavy wooden door creaking open, starts instantly, no silence before it, dry` |
| Brewer visitor | `suno_visitor_brewer.mp3` | 1 s | `a gruff old Bavarian man's "Hm-HO!" and a mug on a bar` (*Instrumental* off, Lyrics `(Hm-HO!) [End]`) |
| Heatwave visitor | `suno_visitor_heatwave.mp3` | 1 s | `a cocky young man's "HAH!" and a crackle of fire` (*Instrumental* off, Lyrics `(HAH!) [End]`) |
| Tavern hatch | `suno_wagon_creak.mp3` | 1 s | `foley, old timber creaking as a wagon hatch swings open, starts instantly, dry` |
| Woods | `suno_woods_birds.mp3` | 2 s | `a single songbird singing in a Bavarian forest, calm, natural` |
| Cow on the Alm | `suno_farm_moo.mp3` | 1.5 s | `one Alpine cow mooing, cow bell clonk, outdoors, funny` |
| Burp after a drink | `suno_drink_burp.mp3` | 1.2 s | `one long proud rumbling comic burp, warm not gross, dry` (*Instrumental* off, Lyrics `(Burp) [End]`) |

### Brewing mini-games
| Sound | File | Length | Style |
|---|---|---|---|
| Hit in the gold | `suno_brew_game_hit.mp3` | 0.2 s | `UI sound, a wooden mallet tapping a beer barrel, satisfying knock, dry` |
| Batch made — fun | `suno_brew_game_won.mp3` | 1 s | `two steins clinking and a short happy accordion run up, success, dry studio` |
| Batch spoiled — sad | `suno_brew_game_lost.mp3` | 0.8 s | `comic sound, foam fizzling out and one sad tuba bloop, dry studio` |

---

## E. Music (seven new tracks)

All music: *Instrumental* switch **off** so Suno reads the section tags, unless noted. These sit next to your menu song (Sturm Ball, 128 BPM, B-flat), the dialogue Schlager (Leiser Oom-Pah, 100 BPM), the base (Sonniger Nachmittag) and the match (Fussball im Bierzelt), so they keep the same band: tuba, brass, accordion, glockenspiel, zither, dry close sound.

Shared **Exclude** line for all music:
```
reverb, echo, hall, crowd noise, lead vocals, singing, choir, synths, electric guitar, EDM, trap, dubstep
```

After you make one, send it to me in a thread and I'll cut a clean loop with `tools/make_loop.py` like the other Suno songs. It also works straight away dropped in as is.

### 1. Goal attempt (the shooter against the keeper cut-away)
- **File:** `suno_goal_attempt_music.mp3` · Row `goal_attempt_music` · plays from the cut-away opening until it closes, then the match music comes back.
- **Style:**
```
tense Bavarian oompah suspense loop, fast pulsing tuba on every beat, snare drum roll building, staccato trumpets, accordion tremolo, 140 BPM, D minor, a penalty shootout at Oktoberfest, nervous and exciting, dry close studio sound, no reverb, instrumental, seamless loop, no ending
```
- **Lyrics:**
```
[Instrumental]
[Intro: snare roll]
[Tense tuba pulse]
[Trumpet stabs, building]
[Loop]
```

### 2. Play Maker (picking your players)
- **File:** `suno_play_maker_music.mp3` · Row `play_maker_music` · plays while you pick at every PLAY MAKER, then the match music comes back.
- **Style:**
```
thinking-time Bavarian music, sly plucked tuba bass, pizzicato strings and zither, playful clarinet, ticking woodblock like a clock, 110 BPM, G major, a coach planning tactics on a beer mat, curious and mischievous, quiet enough to think over, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Sly tuba and zither] [Clarinet melody] [Woodblock ticking] [Loop]`

### 3. Brewery background
- **File:** `suno_brewery_music.mp3` · Rows `brewery_music` and `brewery_music_full` · plays while the Brewery is open, the base music comes back when you close it.
- **Style:**
```
warm Bavarian craft music, gentle accordion waltz, soft tuba, hammered dulcimer and zither, 3/4 time, 92 BPM, F major, a cosy old monastery brewery with copper kettles bubbling, hardworking and content, background music, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Accordion waltz] [Dulcimer melody] [Loop]`

### 4. Dorms / beds background
- **File:** `suno_dorms_music.mp3` · Rows `dorms_music` and `dorms_music_full`
- **Style:**
```
sleepy Bavarian lullaby, slow music box and soft zither, very gentle tuba on the downbeat, quiet accordion breathing, 70 BPM, E-flat major, 1980s football club dormitory at night, players snoring, dreamy and funny, very quiet background music, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Music box lullaby] [Soft zither] [Loop]`

### 5. Adventure menu (the board)
- **File:** `suno_adventure_menu_music.mp3` · Row `bounty_theme`
- **Style:**
```
mysterious Bavarian folk adventure theme, alphorn call, low zither, slow tuba, hand drum, distant cow bells, 96 BPM, A minor, a hidden beer cellar where football contracts hang on a wooden board, mischievous mountain folklore, Bergmännlein mystery, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Intro: alphorn call] [Zither and tuba] [Mysterious melody] [Loop]`

### 6. Team picking and building
- **File:** `suno_team_music.mp3` · Rows `teamselect_theme`, `builder_theme`, `team_build_theme` (one track for all three, so it carries on as you move between them)
- **Style:**
```
upbeat Bavarian oompah locker room music, bouncy tuba, accordion riffs, clapping on the off-beat, light trumpet melody, 120 BPM, C major, picking a football team at the Stammtisch, confident and cheerful, not too busy, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Bouncy oompah] [Accordion riff] [Off-beat claps] [Loop]`

### 7. Adventure: the Marshlands
- **File:** `suno_marsh_music.mp3` · Row `marsh_music` · plays during an Adventure in the Marshlands.
- **Style:**
```
eerie Bavarian marsh adventure music, low bass clarinet and tuba creeping, frogs croaking rhythm on woodblock, misty zither tremolo, hurdy-gurdy drone, 104 BPM, E minor, a foggy reed swamp with something moving in it, folklore danger but still a bit funny, dry studio, instrumental, seamless loop
```
- **Lyrics:** `[Instrumental] [Misty zither] [Creeping tuba] [Hurdy-gurdy drone] [Loop]`

---

## Every file name in one list

Sound effects: `suno_` + the row's ID in `data/Audio.csv`. For example row `door_open` → `suno_door_open.mp3`. `.mp3`, `.wav` and `.ogg` all work.

Music: `suno_goal_attempt_music`, `suno_play_maker_music`, `suno_brewery_music`, `suno_dorms_music`, `suno_adventure_menu_music`, `suno_team_music`, `suno_marsh_music`.
