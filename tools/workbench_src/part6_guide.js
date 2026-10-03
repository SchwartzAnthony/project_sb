/* ============================================================
   v3 — TWO NEW PAGES

   "Art & sizes"  every picture the game will ever ask you for, the box it
                  is drawn into, and the canvas to draw it on. Every number
                  here was read out of the running game, not guessed.

   "Handbook"     the things that are true everywhere and are written down
                  nowhere else: how a CSV is read, what names a thing, where
                  a number lives, what each tool measures, and the order I
                  would build content in.
   ============================================================ */

(function(){
  const css = document.createElement("style");
  css.textContent = `
.spec{width:100%;border-collapse:collapse;font-size:13px;table-layout:auto}
/* The Reference sheet styles .cheat td:first-child as a narrow monospace key
   column. These tables live inside the same card and are NOT that shape, so
   the inherited rule is undone here - without it the note rows refuse to wrap
   and push the last two columns off the right of the screen.
   NOTE TO SELF: this whole block is inside a JS template literal, so a
   backtick anywhere in it ends the string and breaks the page. */
.cheat .spec td:first-child{font-family:var(--sans);font-size:13px;color:inherit;
  white-space:normal;width:auto}
.cheat .spec td.tick{width:1%;white-space:nowrap}
.cheat .spec td.note{white-space:normal;font-family:var(--sans)}
.spec th{text-align:left;font-family:var(--sans);font-size:11px;letter-spacing:.07em;
  text-transform:uppercase;color:var(--faint);font-weight:600;padding:0 8px 6px 0;border-bottom:1px solid var(--line)}
.spec td{padding:7px 8px 7px 0;vertical-align:top;border-bottom:1px solid var(--hair)}
.spec tr:last-child td{border-bottom:0}
.spec .what{min-width:150px}
.spec .what b{color:var(--ink)}
.spec .what span{display:block;color:var(--dim);font-size:12.3px;margin-top:2px}
.spec .px{font-family:var(--mono);font-size:12.5px;white-space:nowrap;color:var(--accent)}
.spec .mk{font-family:var(--mono);font-size:12.5px;white-space:nowrap;color:var(--pitch)}
.spec .fit{font-size:12.3px;color:var(--dim);min-width:110px}
.spec .tick{width:1%;padding-right:10px}
.spec .tick input{width:15px;height:15px;margin:2px 0 0;accent-color:var(--pitch)}
.spec tr.done .what b{text-decoration:line-through;color:var(--faint)}
.warnbox{background:rgba(224,122,44,.10);border:1px solid var(--line);border-left:3px solid #e07a2c;
  border-radius:3px;padding:9px 12px;margin:10px 0 0;font-size:12.8px;color:var(--ink)}
.warnbox b{color:#e07a2c}
.stepcol{counter-reset:stp;margin:0;padding:0;list-style:none}
.stepcol li{position:relative;padding:0 0 9px 30px;font-size:13.2px}
.stepcol li:before{counter-increment:stp;content:counter(stp);position:absolute;left:0;top:1px;
  width:20px;height:20px;border-radius:50%;background:var(--raise);color:var(--accent);
  font-family:var(--mono);font-size:11px;display:flex;align-items:center;justify-content:center}
.kv{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;font-size:13px;align-items:baseline}
.kv .k{font-family:var(--mono);font-size:12.5px;color:var(--accent);white-space:nowrap}
`;
  document.head.appendChild(css);
})();


/* ------------------------------------------------------------
   THE ART SPEC

   drawn : the box the game gives it, in screen pixels
   make  : the canvas I would draw on
   fit   : how the picture is fitted into that box
   ------------------------------------------------------------ */
const ART_GROUPS = [

{title:"The rules that apply to every picture", intro:true, html:`
  <div class="kv">
    <span class="k">the cell</span><span>holds the FILE NAME — no folder, usually no extension. A cell reading <code>mill</code> finds <code>assets/icons/mill.png</code>.</span>
    <span class="k">res://…</span><span>a cell that starts with <code>res://</code> is used exactly as written, wherever it points.</span>
    <span class="k">extensions</span><span>tried in this order: <code>.png</code> <code>.webp</code> <code>.jpg</code> <code>.svg</code></span>
    <span class="k">missing</span><span><b>never an error.</b> An icon draws as a coloured pip, a card as a tinted block, a building as a plain plaque, a sound is silent. You can build the whole game before drawing anything.</span>
    <span class="k">filtering</span><span><b>NEAREST, everywhere.</b> Nothing is smoothed. Draw at the size it will be shown, or an exact multiple of it — 2× and 4× stay crisp, 1.7× does not.</span>
    <span class="k">centered</span><span>the picture is fitted <i>inside</i> the box and letterboxed. Nothing is ever cropped.</span>
    <span class="k">covered</span><span>the picture <i>fills</i> the box and the overflow is <b>cropped</b>. Keep the subject in the middle.</span>
    <span class="k">stretched</span><span>squashed to exactly that size whatever you drew. Only the stadium layers do this, on purpose.</span>
    <span class="k">.png / .jpg</span><span>PNG for anything with a cut-out or soft edge. JPG only for a full rectangle — a background.</span>
  </div>`},

{title:"Players — one spritesheet does everything", dir:"assets/players/", rows:[
  {id:"sheet", what:"A card's spritesheet", why:"Every animation, the portrait on every screen, and the figure on the pitch all come out of this one file.",
   drawn:"cell 128 × 64", make:"1536 × 2496", fit:"grid 12 × 39",
   from:"any unit CSV · Artwork",
   note:"The grid is <b>12 columns × 39 rows</b> out of the box, which is why 1536 × 2496 gives a clean 128 × 64 cell. A different grid is fine — write a row in <b>Animations.csv</b> with your Sheet Columns and Sheet Rows, or the card is sliced into slivers. Any multiple works: 3072 × 4992 is the same sheet at 2×."},
  {id:"pitchbody", what:"The figure inside one cell", why:"What a player actually looks like during a match.",
   drawn:"128 × 64", make:"—", fit:"1 : 1, never scaled",
   from:"the same sheet",
   note:"On the pitch a frame is drawn at <b>exactly its own size</b> on a 2560 × 1440 field. In today's sheets the standing body fills about <b>46 of the 64 pixels</b> and the rest is air. Feet near the bottom of the cell, head near the top, and the same baseline in every frame or the player bobs."},
  {id:"portrait", what:"The portrait", why:"Shown on eight different screens and drawn nowhere — it is cut out of the sheet.",
   drawn:"150 · 140 · 134 · 126 · 84 · 52", make:"nothing extra", fit:"centered",
   from:"frame 0 of the `idle` row",
   note:"The <b>first frame of the <code>idle</code> row</b> of Animations.csv is the face the whole game uses. If one frame of a sheet should be the portrait, make it that one. Boxes, biggest first: team sheet 150, card popup 140, class select 134×130, pub 126×96, bounty board 84, Adventure build-up 52."},
  {id:"keeper", what:"A keeper's sheet", why:"Same idea, its own file.",
   drawn:"cell 128 × 64", make:"1536 × 2496", fit:"grid 12 × 39",
   from:"Goalies.csv · Artwork", note:""},
  {id:"shootout", what:"The first-person keeper", why:"The shootout, seen down the pitch from behind the ball.",
   drawn:"fills the view", make:"2048 × 2048", fit:"grid 4 × 4",
   from:"Goalies.csv · Shootout Artwork",
   note:"A <b>4 × 4</b> sheet, not 12 × 39 — the <code>keeper_ready</code> and <code>keeper_dive</code> rows of Animations.csv say so. Row 0 is waiting, row 1 is the dive."},
]},

{title:"The pitch and the stadium", dir:"assets/field/", rows:[
  {id:"pitch", what:"The playing surface", why:"The grass, the white lines, the surround.",
   drawn:"2560 × 1440", make:"2560 × 1440", fit:"stretched to exactly that",
   from:"Stadium.csv · pitch row",
   note:"<b>It has to be 16:9.</b> The camera's widest shot COVERS the pitch rather than fitting inside it, so anything taller is cropped top and bottom. <b>The white lines do not go to the edge</b> — a real pitch is 1.54:1 and a window is 1.78:1. The margin is <code>pitch_inset_x</code> (6%) and <code>pitch_inset_y</code> (10%) in Tuning.csv, so the lines occupy the middle <b>2253 × 1152</b>, centred, and everything in the match is measured against that inner rectangle. The file is stretched to exactly Width × Height whatever you draw, so 5120 × 2880 works too."},
  {id:"back", what:"The stadium behind", why:"Stands and sky. It drifts at a quarter of the camera's speed, which is what reads as distance.",
   drawn:"3840 × 2160", make:"3840 × 2160", fit:"stretched",
   from:"Stadium.csv · background row",
   note:"Half again bigger than the pitch so there is something to see when the camera moves. <b>Only the edges are ever visible</b>, so put the stands and the sky in the top and bottom thirds and do not waste work on the middle."},
  {id:"crowd", what:"A crowd layer", why:"Drawn between the stadium and the grass. For a stand that fills up as you win.",
   drawn:"3840 × 2160", make:"3840 × 2160", fit:"stretched",
   from:"Stadium.csv · crowd row", note:"Opens with <code>unlocked:Full House</code>. Transparent PNG."},
  {id:"lights", what:"A floodlight overlay", why:"Drawn over everything, multiplied by the Tint column.",
   drawn:"3840 × 2160", make:"3840 × 2160", fit:"stretched",
   from:"Stadium.csv · lights row",
   note:"Tint is <b>multiplied</b> over the layer, so a warm colour is floodlights and a cold one is a night game. Opens with <code>unlocked:Floodlights</code>."},
], warn:"<b>The pitch in the project today is wrong.</b> <code>soccerfield.jpg</code> is <b>1000 × 667</b> — that is 1.50:1 stretched into a 1.78:1 box and blown up 2.56×. It is the single biggest visual win available: redraw it at 2560 × 1440 and the match stops looking soft."},

{title:"The base", dir:"assets/base/", rows:[
  {id:"building", what:"A building", why:"The nine doors on the yard.",
   drawn:"190 × 78", make:"512 × 512", fit:"centered",
   from:"Buildings.csv · Art",
   note:"The whole plaque is <b>190 × 132</b>; the picture takes the top <b>78 pixels</b> and the name sits under it. A square drawing is letterboxed to 78 × 78 in the middle, so if you want the building to fill the plaque draw it about <b>2.4 : 1</b>. Four buildings have no art yet: Achievements, Talent Tree, Dorms, The Traveling Brewer."},
  {id:"basebg", what:"The yard itself", why:"What the buildings stand on.",
   drawn:"1920 × 1080", make:"1920 × 1080", fit:"covered",
   from:"a file literally called <code>background</code>",
   note:"No CSV names it. Put <code>background.png</code> or <code>.jpg</code> in assets/base/ and it is the backdrop."},
  {id:"visitor", what:"A visitor", why:"People who come by the base. They stand in whatever space the buildings leave.",
   drawn:"120 × 105", make:"512 × 512", fit:"centered",
   from:"Visitors.csv · Portrait",
   note:"The card is <b>120 × 150</b> and the name takes the bottom. Found in assets/portraits/ first, then assets/players/."},
]},

{title:"The Brewery", dir:"assets/brewery/", rows:[
  {id:"section", what:"A Brewery section", why:"The six tiles on the map — Malthouse, Mill, Lautering, Boiling, Cooling, Bottling.",
   drawn:"230 × 56", make:"920 × 224", fit:"centered",
   from:"BrewerySections.csv · Art",
   note:"The tile is <b>250 × 172</b>; the picture is a <b>band</b> under the heading, so draw wide and short — about <b>4 : 1</b>. A section with no art is a tile with its name on it and works perfectly."},
  {id:"resource", what:"A resource", why:"Wheat, water, hops, malt, wort — the strip along the top of the Brewery.",
   drawn:"34 × 34", make:"128 × 128", fit:"centered",
   from:"BreweryResources.csv · Icon",
   note:"Small. Read at 34 pixels it is a silhouette, not a drawing — one shape, one strong colour, no detail."},
]},

{title:"Icons — the busiest folder", dir:"assets/icons/", rows:[
  {id:"item", what:"An item", why:"Everything in the bag: brews, bandages, keys, materials.",
   drawn:"96 × 89", make:"256 × 256", fit:"centered",
   from:"Items.csv · Art",
   note:"The tile is <code>icon_tile_size</code> in Tuning.csv — <b>120</b> today — and the drawing gets what is left after <code>icon_tile_padding</code> (10%) and the count along the bottom. Both are rows you can change and look at. Square, subject centred, transparent."},
  {id:"trait", what:"An Adventure icon", why:"The things a drafted player drops on the pile.",
   drawn:"28 · 38 · 164", make:"256 × 256", fit:"centered",
   from:"AdventureTraits.csv · Icon",
   note:"Three sizes from one file: <b>28 × 28</b> on the COMBAT bar, <b>38 × 38</b> on the loadout screen, and a tile <code>adventure_trait_tile_width</code> (<b>164</b>) wide on the icon shelf. <b>28 pixels is the one that matters</b> — if it does not read at 28 it does not read."},
  {id:"talent", what:"A talent", why:"The squares down the left of every talent row.",
   drawn:"44 × 44", make:"128 × 128", fit:"centered",
   from:"Talents.csv · Art", note:"Without art the row draws a lettered placeholder, so the tree lines up whether or not the art exists."},
  {id:"ach", what:"An achievement", why:"",
   drawn:"44 × 44", make:"128 × 128", fit:"centered",
   from:"Achievements.csv · Art", note:""},
  {id:"currency", what:"A currency", why:"Coins, Marsh Marks, Cup Silver.",
   drawn:"34 × 34", make:"128 × 128", fit:"centered",
   from:"Currencies.csv · Icon", note:""},
  {id:"spawn", what:"An Adventure stand-in", why:"What a <code>spawn</code> breakpoint walks onto the grass.",
   drawn:"88 tall", make:"256 × 256", fit:"centered",
   from:"AdventureSpawns.csv · Art", note:""},
]},

{title:"The Traveling Brewer, and the Pub", dir:"assets/shop/", rows:[
  {id:"shoprow", what:"A row on the cart", why:"Drawn to the left of the name and the price.",
   drawn:"64 × 64", make:"256 × 256", fit:"centered",
   from:"Shop.csv · Art", note:"Also searched: assets/icons/, then assets/. A row with no art reads perfectly without it."},
]},

{title:"Teams and classes", dir:"assets/team/", rows:[
  {id:"banner", what:"A class banner", why:"The wide strip across the top of a class on the select screen.",
   drawn:"panel width × 150", make:"2048 × 512", fit:"COVERED — it crops",
   from:"ClassInfo.csv · Banner Art",
   note:"<b>The only picture in the game that is cropped rather than letterboxed.</b> It fills the strip and the overflow is cut off top and bottom, so keep everything you care about in the middle band. Roughly <b>4 : 1</b> of what you draw survives."},
  {id:"formation", what:"A formation diagram", why:"How that class lines up.",
   drawn:"220 tall", make:"1296 × 928", fit:"centered",
   from:"ClassInfo.csv · Formation Art",
   note:"Optional. With no art the game draws the 3 × 3 tier shape itself, which is accurate and never goes stale — only draw one if you want it to look hand-made."},
  {id:"crest", what:"A team badge", why:"On the team sheet, the season screen and the duel cut-away.",
   drawn:"72 · 230", make:"512 × 512", fit:"centered",
   from:"ClassInfo.csv · Banner Art / Teams.csv",
   note:"Shown at <b>230 × 230</b> in the duel cut-away — the biggest any badge gets, so that is the size to judge it at. Without one the game draws a built-in emblem shape."},
]},

{title:"Dialogue and scenery", dir:"assets/portraits/ · assets/backgrounds/", rows:[
  {id:"speaker", what:"A speaker", why:"Whoever is talking. Three standing spots: left, centre, right.",
   drawn:"614 × 691", make:"1024 × 1152", fit:"centered",
   from:"Dialogue.csv · Portrait",
   note:"The slot is <b>32 % of the window wide and 64 % tall</b>, so at 1920 × 1080 that is 614 × 691. Transparent PNG, figure standing, <b>feet at the bottom edge</b> — the slot's bottom is where the text box begins."},
  {id:"scene", what:"A dialogue background", why:"The place a scene happens in.",
   drawn:"1920 × 1080", make:"1920 × 1080", fit:"covered",
   from:"Dialogue.csv · Background",
   note:"The text box covers the bottom third, so nothing important down there."},
  {id:"biome", what:"An Adventure biome", why:"What you walk through.",
   drawn:"1920 × 1080", make:"1920 × 1080", fit:"tiles and scrolls",
   from:"Biomes.csv · Background",
   note:"<b>It repeats sideways forever.</b> The left and right edges must match seamlessly or you will see the join every few seconds. The grass band is drawn on top to <code>adventure_lane_height</code> (600) and the art behind it is not — which is what makes the band read as a much larger place."},
]},

{title:"Menus and seasons", dir:"assets/menu/", rows:[
  {id:"menubtn", what:"A title-screen button", why:"Start, Settings, Tutorial, Quit.",
   drawn:"260 × 68", make:"520 × 136", fit:"centered",
   from:"MenuConfig.csv · Art Path",
   note:"<b>The size is in the CSV</b> — the Width and Height columns of that row — so 260 × 68 is only what it ships with. This column wants a <b>full <code>res://</code> path</b>, not a bare name."},
  {id:"season", what:"A competition", why:"The picture on a season's card on the fixture screen.",
   drawn:"118 tall", make:"1024 × 512", fit:"centered",
   from:"Seasons.csv · Art", note:""},
  {id:"bounty", what:"A bounty", why:"",
   drawn:"84 × 84", make:"256 × 256", fit:"centered",
   from:"Bounties.csv · Art", note:""},
  {id:"menubg", what:"The title screen behind them", why:"",
   drawn:"1920 × 1080", make:"1920 × 1080", fit:"covered",
   from:"assets/menu/background", note:"The one in the project is 583 × 335 — a placeholder."},
]},

{title:"The skin — every box the game draws", dir:"assets/ui/", intro2:`
  <p style="margin:0 0 10px">These nine files are the <b>whole look of the game</b>. Every panel, every button, every window, every bar goes through <b>Theme.csv</b>, and Theme.csv points at these. Change them and every screen changes at once.</p>
  <p style="margin:0 0 10px"><b>They are nine-slice.</b> The four corners are kept at their drawn size, the four edges are stretched along their run, and the middle is stretched to fill. That is how one 96 × 96 file draws a button 60 pixels wide and a panel 1400 wide without either looking wrong. The <b>Slice</b> column of Theme.csv is how many pixels in from each edge the corner ends.</p>
  <p style="margin:0 0 4px"><b>Slice must be less than half the image</b>, or the corners overlap and the box comes out mangled. 28 on a 96-pixel file leaves a 40-pixel middle, which is comfortable.</p>`, rows:[
  {id:"panel", what:"panel", why:"THE MOST IMPORTANT FILE. Card faces, tiles, the strip above the card row, the keeper's number, the celebration window — every box in the game that is not one of the others below.",
   drawn:"any size", make:"96 × 96", fit:"nine-slice, border 28",
   from:"Theme.csv · panel", note:""},
  {id:"window", what:"window", why:"Dialogs, and the window that opens over the base when you click a building.",
   drawn:"any size", make:"96 × 96", fit:"nine-slice, border 28",
   from:"Theme.csv · window",
   note:"Tint is <code>no</code> on this row — it is drawn finished and tinting it would only muddy it. The corner studs live <b>inside</b> the 28-pixel border so they stay put at any size."},
  {id:"button", what:"button, hover, pressed", why:"Three files, one shape. The same plaque lit from above, and pushed in.",
   drawn:"any size", make:"96 × 96 each", fit:"nine-slice, border 26",
   from:"Theme.csv · button",
   note:"<b>disabled</b> and <b>focus</b> have no image on purpose — a disabled button should not look like a thing you can press, and the focus box is drawn <i>over</i> whatever the button already is."},
  {id:"slot", what:"slot", why:"An item tile, a save slot. A beer mat: cream card, dark text — the one place in the game where the text is dark.",
   drawn:"any size", make:"96 × 96", fit:"nine-slice, border 28",
   from:"Theme.csv · slot", note:""},
  {id:"bar", what:"bar_back, bar_fill", why:"The empty glass and the beer in it. Loading bars, keeper stamina, a talent's progress.",
   drawn:"any size", make:"32 × 32 each", fit:"nine-slice, border 10",
   from:"Theme.csv · bar_back / bar_fill", note:""},
], warn:"Three files in that folder are named by <b>no</b> Theme row and are drawn nowhere: <code>panel_soft.png</code>, <code>button_face.png</code>, <code>window_frame.png</code> (48 × 48). Either point a row at them or delete them — <code>tools/theme_check.gd</code> lists them every run."},

{title:"Fonts", dir:"assets/fonts/", rows:[
  {id:"fontdisp", what:"The display face", why:"Headings, the score, the big words in the middle of the pitch.",
   drawn:"34 pt", make:".otf or .ttf", fit:"named in Theme.csv",
   from:"Theme.csv · heading · Font",
   note:"<b>Bonum-Bold</b> today — a Bookman: heavy, wide and warm, which is the shape of a beer label."},
  {id:"fontbody", what:"The reading face", why:"Everything you actually read.",
   drawn:"17 pt body · 13 pt small", make:".otf or .ttf", fit:"named in Theme.csv",
   from:"Theme.csv · body / small · Font",
   note:"<b>Schola-Regular</b> today — a Century Schoolbook. Keep the body a serif you can read at 12 point. A Fraktur here would be unreadable and would look like a costume."},
]},

{title:"Sound", dir:"assets/audio/", rows:[
  {id:"music", what:"Music", why:"A biome's theme, a scene's theme.",
   drawn:"—", make:".ogg", fit:"loops",
   from:"Biomes.csv · Music · Dialogue.csv · Music",
   note:"<b>.ogg, not .wav.</b> It loops properly and it is a tenth of the size."},
  {id:"sfx", what:"An effect", why:"A kick, a save, a whistle, a goal.",
   drawn:"—", make:".wav", fit:"one shot",
   from:"Audio.csv · Sound · Juice.csv · Sound",
   note:"<b>Eleven sounds are named and have no file</b>, so they are silent: goal_horn_big, crowd_groan, glove_catch, glove_catch_big, duel_win_heavy, pour, hit_soft, hit_heavy, enemy_down, player_hurt, enemy_windup. <code>SOUNDS_WANTED.csv</code> describes what each should sound like."},
]},

{title:"Things you never have to draw", intro:true, html:`
  <p style="margin:0 0 9px">All of these are drawn <b>in code</b>, from numbers. They cost nothing, they never go missing, and they change when you change a Tuning row.</p>
  <div class="kv">
    <span class="k">the ball</span><span>a white circle with a seam — on the pitch and in Adventure. <code>ball_ring_radius</code>, <code>adventure_ball_size</code></span>
    <span class="k">confetti</span><span>every piece, in a single draw call. <code>celebration_confetti_pieces</code>, <code>_size</code>, <code>_speed</code></span>
    <span class="k">the Star badge</span><span>a drawn star unless you give it art. <code>star_badge_radius</code></span>
    <span class="k">nameplates</span><span>the name over a head and the Tier · Power window at the feet. <code>plate_</code> rows</span>
    <span class="k">the tier zones</span><span>the quarters of the pitch each tier holds</span>
    <span class="k">the formation diagram</span><span>the fallback when a class has no Formation Art</span>
    <span class="k">team emblems</span><span>disc, shield, lozenge and the rest — the fallback when a team has no crest</span>
    <span class="k">bars and dividers</span><span>any Theme row with no Image draws from Fill, Border and Corner instead</span>
  </div>`},
];


function artRowCount(){
  let n=0; ART_GROUPS.forEach(g=>{ if(g.rows) n+=g.rows.length; }); return n;
}
function artDone(){
  let n=0; ART_GROUPS.forEach(g=>{ if(g.rows) g.rows.forEach(r=>{ if(HAVE["art:"+r.id]) n++; }); }); return n;
}

function paintArt(){
  $("#title").textContent="Art & sizes";
  $("#what").textContent="Every picture the game will ever ask you for, the box it is drawn into, and the canvas I would draw it on.";
  $("#help").hidden=false;
  $("#help").innerHTML="<b>Every number on this page was read out of the running game</b> — out of the code that draws the thing, out of Tuning.csv and out of Stadium.csv — rather than guessed. <b>Drawn at</b> is the box on a 1920 × 1080 screen. <b>Make it</b> is what I would open in the art program: usually 2× or 4× the box, because everything is drawn with nearest-neighbour filtering and an exact multiple stays sharp. The ticks are yours and are kept in this browser.";

  const mk=(t,fn,cls)=>{const b=document.createElement("button");b.className="btn sm "+(cls||"");b.textContent=t;b.onclick=fn;$("#tools").appendChild(b);return b;};
  mk("Copy as a work list",()=>{
    const out=["STURMBALL — ART TO MAKE",""];
    ART_GROUPS.forEach(g=>{
      if(!g.rows) return;
      out.push(g.title.toUpperCase()+(g.dir?"      "+g.dir:""));
      g.rows.forEach(r=>{
        out.push("  "+(HAVE["art:"+r.id]?"[x] ":"[ ] ")+r.what);
        out.push("        drawn at "+r.drawn+"   ·   make it "+r.make+"   ·   "+r.fit);
        out.push("        from "+String(r.from).replace(/<[^>]+>/g,""));
      });
      out.push("");
    });
    const text=out.join("\n");
    navigator.clipboard.writeText(text).then(()=>alert("The work list is on your clipboard."),()=>alert(text));
  },"key");
  mk("Untick everything",()=>{ if(confirm("Clear every art tick?")){
    Object.keys(HAVE).forEach(k=>{ if(k.indexOf("art:")===0) delete HAVE[k]; });
    saveHave(); paintTable(); paintRail(); } });

  const wrap=$("#wrap"); wrap.innerHTML="";
  const board=document.createElement("div"); board.className="board";

  const tally=document.createElement("div"); tally.className="hint";
  tally.innerHTML=`<b>${artDone()} of ${artRowCount()} kinds of art ticked off.</b> Nothing here is checked against your disk — the workbench is a web page and cannot see your project folder. Tick a row when you have drawn it. The <b>Where things go</b> page is the other half of this: it lists the individual <i>file names</i> your spreadsheets are currently asking for.`;
  board.appendChild(tally);

  ART_GROUPS.forEach(g=>{
    const box=document.createElement("div"); box.className="cheat";
    const head=document.createElement("h4");
    head.textContent=g.title;
    if(g.dir){
      const d=document.createElement("span");
      d.style.cssText="margin-left:auto;font-family:var(--mono);font-size:12px;color:var(--faint);text-transform:none;letter-spacing:0";
      d.textContent="res://"+g.dir;
      head.style.display="flex"; head.style.alignItems="center"; head.appendChild(d);
    }
    box.appendChild(head);
    const inner=document.createElement("div"); inner.className="in";

    if(g.html) inner.innerHTML=g.html;
    if(g.intro2) inner.innerHTML=g.intro2;

    if(g.rows){
      const t=document.createElement("table"); t.className="spec";
      t.innerHTML="<thead><tr><th></th><th>What</th><th>Drawn at</th><th>Make it</th><th>Fit</th><th>Named by</th></tr></thead>";
      const body=document.createElement("tbody");
      g.rows.forEach(r=>{
        const tr=document.createElement("tr");
        const key="art:"+r.id;
        if(HAVE[key]) tr.className="done";
        const tick=document.createElement("td"); tick.className="tick";
        const cb=document.createElement("input"); cb.type="checkbox"; cb.checked=!!HAVE[key];
        cb.onchange=()=>{ if(cb.checked) HAVE[key]=true; else delete HAVE[key];
          saveHave(); tr.className=cb.checked?"done":"";
          tally.innerHTML=tally.innerHTML.replace(/<b>\d+ of \d+ kinds/,`<b>${artDone()} of ${artRowCount()} kinds`);
          paintRail(); };
        tick.appendChild(cb); tr.appendChild(tick);

        const what=document.createElement("td"); what.className="what";
        what.innerHTML="<b></b>"+(r.why?"<span>"+r.why+"</span>":"");
        what.querySelector("b").textContent=r.what;
        tr.appendChild(what);

        const a=document.createElement("td"); a.className="px"; a.textContent=r.drawn; tr.appendChild(a);
        const b=document.createElement("td"); b.className="mk"; b.textContent=r.make; tr.appendChild(b);
        const c=document.createElement("td"); c.className="fit"; c.textContent=r.fit; tr.appendChild(c);
        const d=document.createElement("td"); d.className="fit"; d.innerHTML=r.from; tr.appendChild(d);
        body.appendChild(tr);

        if(r.note){
          const nr=document.createElement("tr");
          const nd=document.createElement("td"); nd.colSpan=6;
          nd.className="note";
          nd.style.cssText="padding-top:0;color:var(--dim);font-size:12.5px;padding-left:25px;white-space:normal";
          nd.innerHTML=r.note;
          nr.appendChild(nd); body.appendChild(nr);
        }
      });
      t.appendChild(body); inner.appendChild(t);
    }

    if(g.warn){
      const w=document.createElement("div"); w.className="warnbox"; w.innerHTML=g.warn;
      inner.appendChild(w);
    }
    box.appendChild(inner);
    board.appendChild(box);
  });

  wrap.appendChild(board);
}


/* ------------------------------------------------------------
   THE HANDBOOK
   ------------------------------------------------------------ */
function paintBook(){
  $("#title").textContent="Handbook";
  $("#what").textContent="The things that are true everywhere — how a spreadsheet is read, what names a thing, where a number lives, and what each tool measures.";
  $("#help").hidden=false;
  $("#help").innerHTML="<b>Reference</b> is the small languages — what you may write in a cell. <b>This page is everything else</b>: the rules the whole project obeys, so that a question you have at ten at night has an answer here rather than in a conversation.";

  const wrap=$("#wrap"); wrap.innerHTML="";
  const board=document.createElement("div"); board.className="board";
  const card=(title,html)=>{
    const c=document.createElement("div"); c.className="cheat";
    c.innerHTML=`<h4>${title}</h4><div class="in">${html}</div>`;
    board.appendChild(c); return c;
  };
  const rows=list=>"<table>"+list.map(([a,b])=>`<tr><td>${a}</td><td>${b}</td></tr>`).join("")+"</table>";

  card("The shape of the whole thing", `
    <p style="margin:0 0 10px">Three folders and one rule: <b>nothing in <code>data/</code> knows anything about <code>src/</code></b>. You can change every number in the game without opening a script.</p>
    ${rows([
      ["data/","<b>63 spreadsheets.</b> Everything the game is made of. This is your half of the project"],
      ["assets/","every picture, sound and font. See <b>Art &amp; sizes</b>"],
      ["src/","129 scripts. The machine that reads the spreadsheets"],
      ["tools/","47 measuring instruments. Nothing in the game loads them; they are for you"],
      ["guides/","the Designer Manual, the phase plan, and what a football game needs"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)">A system is built in this order every time: <b>a CSV, a loader that reads it and complains about it, a screen that shows it, and a tool that measures it.</b> If you ever add a system yourself, copy that shape.</p>`);

  card("The rules every spreadsheet obeys", `
    ${rows([
      ["a .csv needs a .csv.import","<b>The one that will bite you.</b> Godot treats a bare .csv as a <i>translation table</i> and litters the folder with .translation files. Every CSV needs a three-line <code>Name.csv.import</code> next to it. <code>tools/csv_import_fix.gd</code> writes the missing ones"],
      ["row 1 is the header","columns are found <b>by name</b>, so the order does not matter and you may add columns of your own. The game ignores what it does not know"],
      ["a missing column","is not an error. It takes its default. That is why you can add a column to one file without touching the other sixty-two"],
      ["a blank row","is skipped. Blank lines between groups are fine"],
      ["ids are flattened","letters and digits only, lowercased. <code>Master Brewer</code>, <code>master_brewer</code> and <code>MASTERBREWER</code> are <b>the same id</b>. Handy, and worth knowing before you name two things almost the same"],
      ["<code>;</code> inside a cell","a list of <b>conditions</b> — all of them must be true. <code>unlocked:Mill;count:coins&gt;=200</code>"],
      ["<code>|</code> inside a cell","a list of <b>values</b> — classes allowed, Tuning rows to bend, resources taken"],
      ["a <code>*</code> row","means <b>everything else</b>. SeasonRules.csv, Pickups.csv and EnemyPlay.csv each have one, so a season or a biome you add tomorrow already works. Do not delete them"],
      ["a cell with a comma","quote it. Every Notes column in the project is full of them and the reader handles it"],
    ])}`);

  card("What names a thing — and what breaks if you rename it", `
    ${rows([
      ["a card","its <b>Name</b> column, everywhere, <b>including inside saved games</b>. Renaming a card breaks every save that had it. Decide names before you play a long session"],
      ["a Star","<b>Name # Card Number</b>. All three Lorelei Stars are called \"Unit Name\", and identifying them by name alone meant unlocking one blocked the other two. If two cards may share a name, the card number is what separates them"],
      ["everything else","its <b>ID</b> column — a dorm, a talent, an item, a building, a season. Names are for players; IDs are for the game"],
      ["an unlock","<b>a word, not an id.</b> <code>unlock:Master Brewer</code> grants it and <code>unlocked:Master Brewer</code> tests it, and the flattening above means the spelling can drift without breaking"],
      ["a counter","a row of <b>Stats.csv</b>. <code>count:goals</code> reads it. A condition that waits on a counter nothing ever writes can never be true — the checker catches that"],
    ])}`);

  card("A class, in one picture", `
    <p style="margin:0 0 10px"><b>A class is 30 cards.</b> Three Star Players holding one whole tier between
    them, and three sets of nine covering the other three tiers, three cards per tier.</p>
    ${rows([
      ["3 Star Players","one tier, one power each. <code>Star Players.csv</code>"],
      ["3 sets of nine","the other three tiers. <code>Unit_Set_&lt;Class&gt;.csv</code>, keyed by <b>Set Name</b>"],
      ["3 Emblems","one per Star, one per set. <code>&lt;Class&gt; Emblems.csv</code>"],
      ["you field twelve","three Stars and nine regulars"],
      ["to play all three Stars","take one tier's worth from EACH of the three sets — that leaves 18 on the bench"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><b>The + New class button walks exactly this.</b> Emblem →
    Ultimate → Star → nine units, three times, then it writes all four files at once.</p>`);

  card("The Emblems — three on the pitch, one may ascend", `
    <p style="margin:0 0 10px"><b>An Emblem arrives with its Star.</b> Field the Star and its Emblem is on the
    bar along the top of the pitch; take the Star out and the Emblem goes with them. It is not bought in the
    talent tree any more.</p>
    ${rows([
      ["it is a race","all three collect all match. The FIRST to meet its Condition turns over and the other two are held on Basic. <code>emblem_race</code>"],
      ["element feeds Basic","a water unit of ANY class counts toward a Lorelei Emblem's Basic side"],
      ["class fulfils the Condition","only a Lorelei can complete it. <b>That is the one rule no column can loosen</b>"],
      ["a goal ends the race","everything back to Basic, every count to zero. <code>emblem_reset_on_goal</code>"],
      ["both faces flip together","the Emblem turns over AND the Star turns to its Ultimate Side"],
      ["a Star has ONE ability","<code>Front Side</code>, not an Attack and a Defend. The second line is spent on the Ultimate"],
      ["hover shows the Ultimate","always, earned or not. An Ultimate you only see once you have it is one you never aimed at"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)">So a mixed-element team gets a broader engine and gives up the
    Ultimate, and a mono-class team gets the Ultimate and a narrower engine. <b>That is the whole reason a
    second class of the same element is worth writing</b>, and it costs no code.</p>
    <p style="margin:9px 0 0;color:var(--dim)"><b>The two columns that do the work.</b>
    <code>Token</code> is the set's own word — Rose Unit, Swan, Song counter — and it is what its nine units
    make and spend; without one the set has no engine and the Condition never fills.
    <code>Set</code> says which nine answer for an Emblem, which is how Gremory can be carried by a Star of
    that name while its units are the Sitri set. <b>That column closed the last red mark in any checker.</b></p>
    <p style="margin:9px 0 0;color:var(--dim)"><b>Price the race in duels:</b>
    <code>tools/emblem_check.gd</code>. Only the first to complete turns over, so an Emblem needing eight
    where another needs three is written, drawn and never seen. Keep the three within one or two.</p>`);

  card("The referee, and his attention", `
    <p style="margin:0 0 10px"><b>A foul is two questions now.</b> Fouls.csv decides whether one HAPPENED;
    Referee.csv decides whether he SAW IT. And if he did not, nothing happens at all.</p>
    ${rows([
      ["the bar fills","every trigger a side sets off adds a little; every foul he MISSES adds a lot"],
      ["while it fills","<code>Caught Per Segment</code> for each lit segment — so an early foul is usually missed"],
      ["full","<code>Caught When Full</code>, 95 or 100. The next foul is a card"],
      ["after a booking","<code>Caught After Yellow</code> replaces all of it. He is watching you"],
      ["red","<code>Red Per Yellow</code> per booking that side already has. With none it adds nothing"],
      ["a repeat offender","<code>Caught Per Own Foul</code> and <code>Card Per Own Foul</code>, per foul THAT MAN has already committed this match — seen or not (round X)"],
      ["leaning on him","an ability with <code>add_card_chance</code>, or a talent with <code>count:tune_foul_card_bonus_enemy+1</code>, makes the other side's seen fouls likelier to be yellows"],
      ["a goal / a card","empties the bar. <code>Empties On</code>"],
      ["league only","an Adventure fight has no referee and never draws the bar"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><b>The number to watch is the MISS RATE</b>, from
    <code>tools/referee_check.gd</code>. Over 80% and the bar is decoration — a player never sees a card and
    never learns the rule. Under 20% and it is the system you had before the bar existed. Around half is the
    shape you want: getting away with one is common, getting away with four is not.</p>`);

  card("Team Build — before the Pub and every match (round Y)", `
    <p style="margin:0 0 10px"><b>The Talent Tree building is Team Build now</b>, with three tabs: <b>Star Hall</b>, <b>Your Teams</b>, <b>Talents</b>.</p>
    ${rows([
      ["the gate","the Pub and every match stay shut until you have a team of <b>12</b> (three Stars + nine) AND that class's three Stars are placed"],
      ["Stars first","the Stars open the set cards a team is made of (<code>class_tree_gates_units</code> is on), so a new game lands on the Star Hall"],
      ["free Stars","the first three cost nothing - <code>team_build_free_stars</code>. Talent points come from matches, and matches now need Stars"],
      ["switch","<code>team_build_gate</code> in Tuning.csv. Adventure is not gated"],
    ])}`);

  card("Counters, Ore, tokens and swans (round Z, phase C2)", `
    <p style="margin:0 0 10px"><b>103 of your 228 class abilities work in a match now</b> (45%, up from 33) - and five Emblems' Basic sides play.</p>
    ${rows([
      ["counters","burn, song, power - on a CARD for the whole match. A <b>-1 power counter</b> makes it 1 weaker in every duel after. Shown on the draft card"],
      ["Ore","one pool per SIDE (ruling R12). <code>gain_ore</code> fills it; a <b>Cost</b> of <code>ore:3</code> spends it before the ability goes off"],
      ["tokens","a <b>Rose Unit</b> takes a card's place (same power, no text); the card waits in the exhaust - where its <i>While in exhaust</i> side works"],
      ["swans","a creature type, not a card: Zepar's Emblem turns a revealed water unit into a Swan, +1 in every combat"],
      ["the tracker","a panel on the pitch: Ore, tokens, victory counters, and every <i>next one</i> still waiting (ruling F3)"],
      ["exile","= the exhaust zone (ruling R14). The card texts say exhaust now"],
    ])}`);

  card("Combat abilities — the plan (round Y)", `
    <p style="margin:0 0 10px"><b>Every ability text is read</b> into engine words in <b>AbilityAudit.csv</b>, and the open questions are in <b>AbilityRulings.csv</b>, once each. guides/COMBAT_PHASES.md has the timing chart and the phases.</p>
    ${rows([
      ["C1 · built","zones (field, combat, exhaust), the new moments, the <code>If</code> column, \u201cthe next one\u201d, one side per duel"],
      ["C2 · built","counters, tokens, Ore, swans, five Emblem Basic sides. <b>103 abilities work</b>"],
      ["C3","the keeper and the referee - +18"],
      ["C4","bending the duel - +33"],
      ["C5","exile and the other zones - +17"],
      ["C6","mines, fusing, the ball, gravestones - +60"],
      ["C7 · C8","the Emblems' Basic Sides, then the Stars' Ultimates"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><b>The three commands:</b> <code>python3 tools/ability_audit.py</code> (read the cards) · <code>python3 tools/ability_rows.py</code> (wire what is built) · <code>ability_coverage.gd</code> (the meter).</p>`);

  card("Names, recruits and three beers (round X)", `
    <p style="margin:0 0 10px"><b>Stars carry Goetia names. Everyone else carries a common German one</b>, and keeps it for as long as he is at your base.</p>
    ${rows([
      ["Names.csv","first names, and surnames for when they run out. A name is never handed out twice"],
      ["<code>recruit:I0</code>","a plain Tier I Power 0 player with a name of his own. <code>recruit:I0=Johannes</code> asks for one"],
      ["<code>release:Johannes</code>","he leaves the base and the name is free again"],
      ["<code>named_recruits</code>","Tuning.csv, <b>false</b>. Recruits are remembered but nobody shows until it is true — turn it on with <code>squad_ownership</code>"],
      ["a TURNING brew","a number in Brews.csv's <b>Drinks</b> column. Three pours on a plain card and he becomes that class at his own tier and power, keeping his name. You choose which card - one per set"],
      ["mixing","a different element starts the count again: water, water, fire = fire 1 of 3"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><b>One gap worth knowing:</b> each class has one tier that belongs to its Stars alone (Lorelei and Unkengeister: Tier II), so a plain player of that tier has nothing to turn into. <code>tools/round_x_check.gd</code> prints the list.</p>`);

  card("Dev mode", `
    <p style="margin:0 0 10px"><code>dev_mode</code> in Tuning.csv is FALSE. True adds a DEV section to the
    pause menu and puts a <b>red strip across the top of every screen</b> for as long as it is on.</p>
    ${rows([
      ["Own EVERY card","signs every card in every unit CSV"],
      ["Own NOTHING","clears the lot — what a new game looks like, without deleting a save"],
      ["What is in the game?","the roster counted by class, to the Output panel"],
      ["the red strip","not decoration. It is what stops a build going out with a free roster in it, because you cannot take a screenshot without seeing it"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)">It writes to the ORDINARY save through the same
    <code>sign:</code> a dialogue row uses, because a developer switch with its own private store tests
    something other than the game. And <code>squad_ownership</code> is FALSE out of the box, so neither
    button changes a match until you turn ownership on.</p>`);

  card("The four actions that need a screen", `
    <p style="margin:0 0 10px">Everything you write in a <b>Do</b>, <b>Effects</b>, <b>Action</b>, <b>On Win</b> or <b>Reward</b> column is written straight into your save. <b>Four cannot be</b>, because they <i>open</i> something and only the screen that asked knows where to open it:</p>
    ${rows([
      ["story:prologue","play a dialogue scene"],
      ["goto:brewery","leave this screen and open that one full-screen"],
      ["announce:First win!","put a banner across the middle"],
      ["window:brewery","open that screen <b>over</b> this one, in a window, with the base still behind it"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><b>This is where a real bug lived.</b> <code>window</code> was missing from that list, so <code>window:brewery</code> was quietly handed to the effects language, which ignores what it does not recognise. Clicking a building showed its description and did nothing else — no error, no warning, nothing anywhere.</p>
    <p style="margin:9px 0 0;color:var(--dim)">It is fixed, and so is the shape of it: <b>a term the game does not recognise is now named out loud in Godot's Output panel every time it runs.</b> Any typo you ever make in one of those columns will complain instead of going quiet. <b>If a button you wrote does nothing, look in the Output panel first.</b></p>`);

  card("Where a number lives", `
    <p style="margin:0 0 10px">When you want to change something, this is the order to look in.</p>
    ${rows([
      ["Tuning.csv","<b>333 rows.</b> Anything that is a feel or a balance number — speeds, radii, sizes, how long a pause is, whether a whole feature is on. If a number is not obviously about one thing, it is here"],
      ["the system's own CSV","anything that is about <i>one</i> thing — this dorm's price, this talent's effect, this biome's waves"],
      ["Theme.csv","anything about how it <b>looks</b>: the nine box styles, the two fonts, and the twelve palette rows every screen draws from"],
      ["Juice.csv","anything about how a moment <b>feels</b> — shake, flash, pop, and the sound hung on it"],
      ["a script","nothing you should need. If you find yourself wanting to, tell me and it becomes a row"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)">A talent can edit Tuning at runtime: <code>count:tune_press_speed+12</code> adds 12 to the <code>press_speed</code> row for as long as the talent is held. <b>Any</b> Tuning row can be driven that way, which is most of what makes the talent tree interesting.</p>`);

  card("Achievements are the root of everything", `
    <p style="margin:0 0 10px">Nine of the game's systems are gated by an achievement and six more by something the Brewery makes. <b>Achievements.csv is where a thing is born</b>; every other spreadsheet tests for it.</p>
    ${rows([
      ["Needs","the condition, in the ordinary language. <code>count:matches_won&gt;=3</code>"],
      ["Unlocks","<b>the word it hands over.</b> Anything in the game may then test <code>unlocked:&lt;that word&gt;</code>"],
      ["Reward","anything else, in the Do language — <code>give:coins+50</code>, <code>flag:x</code>, <code>announce:Text</code>"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)"><code>tools/achievement_check.gd</code> reads the whole board back and answers two questions no spreadsheet can: <b>is anything unlocked that nothing tests</b> (a room waiting for its door — fine while building), and <b>is anything tested that nobody grants</b> (a door with no key — always a mistake).</p>
    <p style="margin:9px 0 0;color:var(--dim)">The shape to keep: <b>the basic foundation is free, and everything that makes it bigger or easier is earned.</b> The first dorm is free. One Brewery vat is free. The rest are achievements.</p>`);

  card("Saving", `
    ${rows([
      ["what is in a save","your flags, your counters, your unlocks, your squad and who is tired. <b>Nothing else</b> — no copy of any spreadsheet"],
      ["what that means","you may change any number in any CSV and load an old save. The game re-reads the spreadsheets every time it starts"],
      ["what breaks a save","<b>renaming a card.</b> That is the only one. See the naming card above"],
      ["slots","three, plus a separate tutorial save that never touches your real one"],
    ])}`);

  card("Words — and a second language", `
    ${rows([
      ["Language.csv","<b>Key, English, Deutsch.</b> Add a column, add a language. Anything the game says that is not content lives here"],
      ["Dialogue.csv","the content — scenes, lines, who is speaking, what is behind them, and what a line <i>does</i>"],
      ["Keys.csv","every control, its default key and its default gamepad button, in groups. A player rebinds them in Settings"],
      ["Keywords.csv","the 49 words in 9 families that the checkers test your cells against — ability effects, targets, conditions, item tags, Juice moments. <b>17 of them are planned and do nothing yet</b>; the Keywords page lists which"],
    ])}`);

  card("The tools, and what each one measures in", `
    <p style="margin:0 0 10px">Run from the project folder. Every one of them prices a system in a unit <i>you</i> can feel, rather than in code.</p>
    ${rows([
      ["scoring_balance","<b>goals per match.</b> The number the whole match is balanced against"],
      ["foul_check","<b>cards per side per match</b>, and the odds at every trigger count"],
      ["shot_odds_check","<b>ten thousand shots</b> rolled against what the table promised"],
      ["brewery_check","<b>bottles per season</b>, and <b>what runs out first.</b> The bottleneck is never the one you expect"],
      ["shop_check","every price on the cart in <b>wins</b>"],
      ["rooms_check","every dorm, trophy and training in <b>seasons</b> — and whether every building's door opens a screen that exists"],
      ["class_tree_check","a whole class tree in <b>talent points</b>"],
      ["season_check","every competition's rules in a sentence, every borrowed Tuning row <b>handed back</b>, and a run's worth in pickups"],
      ["achievement_check","the whole unlock board, both ways round"],
      ["theme_check","every element of Theme.csv and whether its file is there"],
      ["movement_check","<b>reversals per second</b> — the number that tells you a player is vibrating rather than walking"],
      ["lane_check","that nobody is drawn off the grass, standing or lying"],
      ["recovery_check","whether the squad is deep enough to turn the recovery system on"],
      ["match_soak / adventure_soak","<b>a whole match and a hundred fights, with no window.</b> Run these after any change to a number that matters"],
      ["base_shot","opens the base and <b>presses every building</b>, then checks a window appeared"],
      ["ability_coverage","<b>how many of your abilities work in a match</b>, by class. The meter for the combat phases"],
      ["ability_check","stages every wired card's moment and checks the effect landed where its sentence says"],
      ["ability_audit.py / ability_rows.py","read every card text into engine words; then wire the ones the engine can run"],
      ["team_build_shot","presses the Pub and Play buttons on a new game and checks Team Build opens instead"],
      ["round_x_check","<b>names, recruits, three beers, the repeat offender and the ore card</b>, on a scratch save"],
      ["pub_turn_shot","presses the real Pub buttons through three beers and the choice, and photographs it"],
      ["cut_chrome.py","cuts the PixelLab sheets in <code>art_source/pixellab/</code> into the eight chrome files. <code>python3 tools/cut_chrome.py</code>"],
      ["csv_import_fix","writes the missing .csv.import files"],
    ])}
    <p style="margin:10px 0 0;color:var(--dim)">The full list, with the exact command line for each, is section 14 of the Designer Manual. <b>A tool that reaches past the button cannot see a broken button</b> — if you ever write one, press the thing a player presses.</p>`);

  card("The order I would build content in", `
    <ol class="stepcol">
      <li><b>Write the achievement first.</b> Nothing else can be reached until something hands out its name.</li>
      <li><b>Write the row that the achievement opens</b> — the dorm, the section, the talent — with its Requires pointing at that unlock.</li>
      <li><b>Run the checker for that system.</b> It will tell you the price in seasons or wins or points, which is the only honest way to know whether the number is right.</li>
      <li><b>Play it once.</b> Numbers that look right in a table are often wrong in a hand.</li>
      <li><b>Draw the art last.</b> Everything works without it, and art made for a row you then delete is the most expensive kind of work there is.</li>
    </ol>
    <p style="margin:10px 0 0;color:var(--dim)">The same order in one line: <b>unlock → row → measure → play → draw.</b></p>`);

  card("Known gaps, today", `
    <p style="margin:0 0 10px">Carried forward round to round. None of these stops anything; they are the list of what is half-written.</p>
    ${rows([
      ["<s>the Lorelei emblem</s>","<b>FIXED.</b> Nothing was wrong with the data — the code assumed a Star and its set share a name. The <code>Set</code> column says which, and every checker is green"],
      ["three emblems","have no <code>Turns On</code> — they are earned and then do nothing"],
      ["two unlocks","<code>Emblems</code> and <code>Trophy Case</code> are granted and nothing tests them. A room waiting for its door"],
      ["eleven sounds","named in Audio.csv with no file. <code>SOUNDS_WANTED.csv</code> describes each"],
      ["four buildings","Achievements, Talent Tree, Dorms and The Traveling Brewer draw as plain plaques"],
      ["the pitch image","1000 × 667 where the game wants 2560 × 1440. See <b>Art &amp; sizes</b>"],
      ["unit abilities","33 of 228 class abilities work in a match (round Y, phase C1). The rest wait on phases C2-C8 - AbilityAudit.csv says which"],
      ["Ore","there is no Ore counter in a match yet, so <i>Consume 3 Ore</i> is not charged"],
      ["<code>recovery</code>","deliberately <code>false</code> in Tuning.csv. With three players a tier, one fixture puts enough out that you can field neither a match nor a run. Six a tier is the number to aim at"],
      ["17 keywords","written into Keywords.csv and not implemented yet. The Keywords page marks them"],
    ])}`);

  wrap.appendChild(board);
}
