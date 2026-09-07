# Field Scaling & Main Menu Setup

This guide explains how to use the new scalable field system and CSV-driven main menu.

---

## Part 1: Scalable Field System

### Overview

The game now has a **FieldBounds** system that:
- Defines a standard play area size (default 1280×720)
- Automatically scales any field background art to fit that area
- Constrains all players to stay within field boundaries
- Works with any field art size — just drop a PNG in and it scales

### How It Works

1. **Play Area** — A fixed rectangular zone (default 1280×720 pixels)
2. **Field Sprite** — Your background art, which scales to fill the play area
3. **Player Bounds** — All units constrained to stay within the play area + margin

### Setup in Your Project

#### Step 1: Assign the Field Sprite

In `main_scene.tscn` (or your setup code):
- Create or find your field background Sprite2D
- In the editor, drag it into the `field_sprite` export variable on the main_scene node
- Or, in code:
  ```gdscript
  main_scene.field_sprite = your_field_sprite
  ```

#### Step 2: (Optional) Customize Field Dimensions

Edit `Tuning.csv` and set:

```
field_width,1280,Play area width in pixels. Art scales to fit this.
field_height,720,Play area height in pixels. Art scales to fit this.
field_position_x,0,Play area X position in world space
field_position_y,0,Play area Y position in world space
field_margin,16,Player edge margin. Prevents standing exactly on field border.
```

Common sizes:
- **1280×720** — HD, balanced
- **1920×1080** — Full HD
- **960×540** — Compact (half HD)
- **640×360** — Mobile/small

#### Step 3: Add Your Field Art

Place your field background PNG in `res://assets/`:
- Name it something clear: `field_grass.png`, `field_stadium.png`, etc.
- The art will be scaled automatically to fit the play area dimensions you set in Tuning.csv
- **No code changes needed** — the system scales it for you

### How Players Stay In Bounds

Every player unit has a `play_bounds` rectangle assigned at spawn. Each physics frame (`_physics_process`), the unit calls `_clamp_to_bounds()` which constrains its position:

```gdscript
func _clamp_to_bounds() -> void:
    if play_bounds.size.x <= 1.0 or play_bounds.size.y <= 1.0:
        return
    global_position.x = clampf(global_position.x, play_bounds.position.x, play_bounds.end.x)
    global_position.y = clampf(global_position.y, play_bounds.position.y, play_bounds.end.y)
```

The ball also respects these bounds during passes and shots.

### Troubleshooting

**Players still appear outside the field?**
- Check that `field_width` and `field_height` in Tuning.csv match your intended play area
- Verify the field sprite is assigned and has a valid texture
- Ensure `field_margin` in Tuning.csv is not too large

**Field art is stretched or distorted?**
- This is normal if your art's aspect ratio doesn't match field_width:field_height
- To fix: either adjust the dimensions in Tuning.csv to match your art, or create art that matches the dimensions

**Players moving on top of the field edge?**
- Increase `field_margin` in Tuning.csv to push players further from the edge

---

## Part 2: CSV-Driven Main Menu

### Overview

The game now includes a fully customizable main menu loaded from CSV. Everything can be changed without touching code:

- **MenuConfig.csv** — Defines buttons, their positions, and art
- **Menu art folder** — `res://assets/menu/` for button and background PNGs
- **main_menu.gd** — Loads the CSV and creates the menu at runtime
- **main_menu.tscn** — The menu scene (set this as your starting scene)

### How It Works

1. At startup, `main_menu.gd` reads `MenuConfig.csv`
2. For each button row, it creates a button at the specified X/Y position
3. If a PNG exists at the `Art Path`, it displays the image
4. If not, it shows a colored placeholder
5. Clicking a button triggers an `Action` (start_game, quit, etc.)

### Setup in Your Project

#### Step 1: Create Menu Folder Structure

```
res://assets/menu/
├── background.png          (optional background image)
├── button_start.png
├── button_settings.png
└── button_quit.png
```

The folder doesn't need to exist if you don't have art yet. The menu will work with placeholder boxes.

#### Step 2: Customize MenuConfig.csv

Edit `res://data/MenuConfig.csv`:

```csv
Button ID,Label,X,Y,Width,Height,Action,Art Path,Notes
START_GAME,Start Game,640,450,200,80,start_game,res://assets/menu/button_start.png,Begin a new match
SETTINGS,Settings,640,570,200,80,open_settings,res://assets/menu/button_settings.png,Game options
QUIT,Quit,640,690,200,80,quit_game,res://assets/menu/button_quit.png,Exit the game
```

**Column reference:**
- **Button ID** — Internal name, must be unique
- **Label** — Text shown on the button (if no art)
- **X, Y** — Button center position (viewport coordinates)
- **Width, Height** — Button size
- **Action** — What happens when clicked: `start_game`, `open_settings`, `quit_game`, or custom
- **Art Path** — Path to button PNG (leave blank for placeholder)
- **Notes** — For you; ignored by the game

#### Step 3: Add Menu Art

Place PNG files in `res://assets/menu/`. Recommended sizes:

- **Button images** — 200×80 pixels (to match Width/Height in CSV)
- **Background** — At least viewport size (typically 1280×720 or larger)

Don't have art yet? No problem. The menu works with colored rectangles:
- Leave `Art Path` empty or wrong, and a blue button appears
- Customize colors in `main_menu.gd` line ~78: `art_rect.color = Color(0.2, 0.6, 0.9, 0.8)`

#### Step 4: Set Main Menu as Starting Scene

In the Godot editor:
1. Open `main_menu.tscn`
2. Go to **Project → Project Settings → General → Run → Main Scene**
3. Set it to `res://src/ui/main_menu.tscn`

Or run it manually from the terminal:
```bash
godot --path . res://src/ui/main_menu.tscn
```

### Customizing the Menu

#### Add New Buttons

Edit `MenuConfig.csv` and add a row:

```csv
CUSTOM_BTN,My Button,640,300,200,80,my_action,res://assets/menu/button_custom.png,My button
```

Then in `main_menu.gd`, handle the action:

```gdscript
func _on_button_pressed(action: String) -> void:
    match action:
        "start_game":
            _start_game()
        "my_action":
            print("Custom action triggered!")
        # ... etc
```

#### Reposition Buttons

Edit the X and Y columns in MenuConfig.csv. The values are screen coordinates:
- X=640, Y=360 is center screen (on 1280×720)
- X=0, Y=0 is top-left corner
- X increases rightward, Y increases downward

#### Change Button Size

Edit Width and Height in MenuConfig.csv.

#### Add a Background Image

1. Save your background PNG to `res://assets/menu/background.png`
2. In `main_menu.gd`, change line 25:
   ```gdscript
   @export var background_art_path: String = "res://assets/menu/background.png"
   ```
3. The background will automatically scale to fill the screen

#### Customize the Title

In `main_menu.gd`, edit:
```gdscript
@export var title_text: String = "AUTOBATTLER"
@export var title_font_size: int = 80
```

Or change them in the editor inspector when the scene is selected.

### Menu Actions Reference

Built-in actions:
- **`start_game`** — Loads main match scene
- **`open_settings`** — (Not yet implemented; currently prints a message)
- **`quit_game`** — Closes the game

To add custom actions, edit `_on_button_pressed()` in `main_menu.gd`.

---

## Part 3: Freezing Action During Star Selection (HOLD UP!)

### What Changed

Players now **stop animating** when the HOLD UP! star selection UI appears. The on-pitch action is completely paused during this screen, then resumes after you pick.

### Technical Detail

In `main_scene.gd`, when HOLD UP! starts, the code calls:
```gdscript
freeze_play(true)
```

This is a reference-counted freeze that:
- Stops the ball from moving
- Pauses all unit animations and movement
- Stops them from chasing or passing
- Resumes cleanly when `freeze_play(false)` is called

The freeze depth counter allows overlapping freezes (e.g., substitution happening during a zoom-in) without accidentally resuming too early.

---

## Part 4: File Placement

**NEW FILES to add:**

Core system:
- `res://src/core/field_bounds.gd` — Field geometry helper

Menu system:
- `res://src/ui/main_menu.gd` — Menu manager
- `res://src/ui/main_menu.tscn` — Menu scene
- `res://src/ui/menu_button.gd` — Individual button handler
- `res://src/ui/menu_button.tscn` — Button scene

Configuration:
- `res://data/MenuConfig.csv` — Button layout and art paths

Field configuration:
- Add these rows to `res://data/Tuning.csv`:
  ```
  field_width,1280,Play area width in pixels
  field_height,720,Play area height in pixels
  field_position_x,0,Play area X position
  field_position_y,0,Play area Y position
  field_margin,16,Player edge margin
  ```

**UPDATED FILES:**
- `res://data/Tuning.csv` — Added field configuration rows

**NO CHANGES NEEDED to:**
- `main_scene.gd` — The field system and freeze_play already exist!
- `player_unit.gd` — Bounds clamping already in place!
- Unit/goalie scripts — All work as-is

---

## Part 5: Testing

### Test the Field System

1. In the Godot editor, open `main_scene.tscn`
2. Assign your field sprite to the `field_sprite` export variable (or leave it empty for auto-generation)
3. Press Play
4. Watch that players stay within the field boundaries
5. If players are still outside:
   - Check `Tuning.csv` — are the dimensions reasonable for your viewport?
   - Check the field sprite assignment
   - Increase `field_margin` to push players away from edges

### Test the Main Menu

1. Open `main_menu.tscn` and press Play
2. You should see:
   - A background (gradient by default, or your art if `background_art_path` is set)
   - A title at the top
   - Three buttons: Start Game, Settings, Quit
3. Click Start Game → loads the match
4. Click Quit → closes the game
5. Customize MenuConfig.csv and watch buttons reposition/resize in real-time

### Test Animation Freeze During HOLD UP!

1. Run a match
2. Complete one Cycle (3 PLAY MAKERs)
3. When HOLD UP! appears, watch that:
   - Players stop moving
   - Ball doesn't fly around
   - Pick your next star
   - On-pitch action resumes

---

## Quick Customization Checklist

- [ ] Set `field_width` and `field_height` in `Tuning.csv` to match your game
- [ ] Create `res://assets/menu/` folder
- [ ] Add button art PNGs (optional; colored placeholders work fine)
- [ ] Customize `MenuConfig.csv` with your button layout
- [ ] Set `main_menu.tscn` as the starting scene
- [ ] Assign your field sprite in `main_scene.tscn` or in code
- [ ] Run the menu and test clicking buttons
- [ ] Run a match and verify players stay in bounds

That's it! Everything is data-driven now.

