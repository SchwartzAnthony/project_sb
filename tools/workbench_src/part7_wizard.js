/* ============================================================
   v4 — THE NEW CLASS WIZARD

   "When I want to create a new Class I could click New Class -> establish
    the Emblem ability -> establish the Ultimate -> establish the Star
    Player -> establish the 9 player units that have synergy with that Star
    -> Finish Class"

   That is the order, and it is the right order, because it is the order the
   DEPENDENCIES run in: the Emblem names the token, the token is what the
   nine units make and spend, and the Star carries the Emblem on. Do it the
   other way round and the nine units have nothing to be about.

   A class is 30 cards. THREE TIMES nine units, plus three Stars:

       3 Star Players          one whole tier between them
       3 sets of nine          the other three tiers, three cards each
       3 Emblems               one per Star, one per set

   So the wizard runs the Emblem-to-nine loop three times and then writes
   four files at once.
   ============================================================ */

(function(){
  const css=document.createElement("style");
  css.textContent=`
#wiz{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:90;display:flex;
  align-items:flex-start;justify-content:center;overflow:auto;padding:26px 16px}
#wiz .sheet{background:var(--paper);border:1px solid var(--line);border-radius:5px;
  width:min(1100px,100%);box-shadow:0 18px 60px rgba(0,0,0,.4)}
#wiz header{display:flex;align-items:center;gap:12px;padding:14px 18px;border-bottom:1px solid var(--line)}
#wiz header h3{margin:0;font-family:var(--disp);text-transform:uppercase;letter-spacing:.07em;
  font-size:17px;color:var(--accent)}
#wiz .in{padding:16px 18px}
#wiz footer{display:flex;align-items:center;gap:10px;padding:12px 18px;border-top:1px solid var(--line)}
.steps{display:flex;gap:0;margin:0 0 16px;flex-wrap:wrap}
.steps div{font-size:11.5px;font-family:var(--sans);letter-spacing:.05em;text-transform:uppercase;
  padding:6px 13px 6px 20px;background:var(--card);color:var(--faint);position:relative;
  border:1px solid var(--line);border-right:0}
.steps div:first-child{padding-left:13px;border-radius:3px 0 0 3px}
.steps div:last-child{border-right:1px solid var(--line);border-radius:0 3px 3px 0}
.steps div.on{background:var(--accent-soft);color:var(--accent);font-weight:600}
.steps div.did{color:var(--pitch)}
.fld{margin:0 0 13px}
.fld label{display:block;font-size:11.5px;letter-spacing:.05em;text-transform:uppercase;
  color:var(--faint);font-weight:600;margin:0 0 4px}
.fld input,.fld select,.fld textarea{width:100%;padding:8px 9px;background:var(--card);
  border:1px solid var(--line);border-radius:3px;color:var(--ink);font-family:var(--sans);font-size:13.5px}
.fld textarea{min-height:74px;resize:vertical;line-height:1.45}
.fld .why{font-size:12.3px;color:var(--dim);margin:4px 0 0}
.two{display:grid;grid-template-columns:1fr 1fr;gap:0 14px}
.three{display:grid;grid-template-columns:1fr 1fr 1fr;gap:0 14px}
.rolled{width:100%;border-collapse:collapse;font-size:12.6px;margin:8px 0 0}
.rolled th{text-align:left;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;
  color:var(--faint);padding:0 8px 5px 0;border-bottom:1px solid var(--line)}
.rolled td{padding:5px 8px 5px 0;vertical-align:top;border-bottom:1px solid var(--hair)}
.rolled td.t{font-family:var(--mono);font-size:11.5px;color:var(--accent);white-space:nowrap}
.rolled td.p{font-family:var(--mono);font-size:11.5px;white-space:nowrap}
.rolled input{width:100%;padding:3px 5px;background:transparent;border:1px solid transparent;
  border-radius:2px;color:var(--ink);font-family:var(--sans);font-size:12.6px}
.rolled input:focus{background:var(--card);border-color:var(--line);outline:none}
.wizhint{background:var(--accent-soft);border:1px solid var(--line);border-left:3px solid var(--accent);
  border-radius:3px;padding:10px 13px;margin:0 0 14px;font-size:13px;color:var(--ink)}
.wizhint b{color:var(--accent)}
.wizbad{background:rgba(224,122,44,.10);border-left-color:#e07a2c}
.wizbad b{color:#e07a2c}
`;
  document.head.appendChild(css);
})();


/* The whole class, as it is being built. One object, so "Back" is free. */
let WIZ = null;

/* The four tiers, without the blank first entry the dropdowns use. The
   schema file already has a `TIERS` with an empty string at the front for
   "no tier chosen"; this is the ladder itself. */
const WIZ_TIERS = ["I","II","III","IV"];
/* THE LADDER, and the one rule nothing may break: a tier holds one card of
   each power in its span, never two the same. */
const WIZ_POWERS = {I:[0,1,2], II:[1,2,3], III:[2,3,4], IV:[3,4,5]};


function wizStart(){
  WIZ = {
    step: 0,
    cls: "", display: "", element: "WATER", starTier: "II", description: "",
    sets: [0,1,2].map(i => ({
      emblem: "", token: "", basic: "", condition: "", turnsOn: "", counter: "",
      need: 3 + i, ultimate: "", starFront: "", starPower: null, units: null,
    })),
  };
  wizDraw();
}


function wizElements(){
  const out = [];
  if(DATA["Elements.csv"]){
    const i = at("Elements.csv","Element");
    if(i>=0) DATA["Elements.csv"].rows.forEach(r=>{ const v=(r[i]||"").trim(); if(v) out.push(v); });
  }
  return out.length ? out : ["WATER","FIRE","EARTH","AIR"];
}

/* The three tiers a SET of nine covers — every tier except the Stars'. */
function wizSetTiers(){
  return WIZ_TIERS.filter(t => t !== WIZ.starTier);
}

/* Every row of UnitActions.csv that may be rolled for this set. */
function wizPhrases(kind, side, tier){
  const f = "UnitActions.csv";
  if(!DATA[f]) return [];
  const H = c => at(f,c);
  const out = [];
  DATA[f].rows.forEach(r=>{
    const g = c => { const i=H(c); return i<0 ? "*" : String(r[i]||"*").trim() || "*"; };
    if(norm(g("Kind")) !== norm(kind)) return;
    const el = g("Element"), cl = g("Class"), ti = g("Tier"), si = g("Side");
    if(el!=="*" && norm(el)!==norm(WIZ.element)) return;
    if(cl!=="*" && norm(cl)!==norm(WIZ.cls)) return;
    if(ti!=="*" && !ti.split("|").map(x=>x.trim()).includes(tier)) return;
    if(si!=="both" && si!=="*" && norm(si)!==norm(side)) return;
    const w = Math.max(1, parseInt(g("Weight"),10) || 1);
    const text = H("Text")>=0 ? String(r[H("Text")]||"") : "";
    if(!text) return;
    for(let i=0;i<w;i++) out.push(text);
  });
  return out;
}

/* Fill {tier} {element} {token} {n} {class}. */
function wizFill(text, set, tier){
  const others = WIZ_TIERS.filter(t=>t!==tier);
  return String(text)
    .replace(/\{tier\}/g, () => others[Math.floor(Math.random()*others.length)])
    .replace(/\{element\}/g, () => WIZ.element.toLowerCase())
    .replace(/\{class\}/g, () => WIZ.cls)
    .replace(/\{token\}/g, () => set.token || "token")
    .replace(/\{n\}/g, () => String(1 + Math.floor(Math.random()*2)));
}

function wizOne(set, side, tier){
  const trig = wizPhrases("trigger", side, tier);
  const eff  = wizPhrases("effect",  side, tier);
  if(!eff.length) return "";
  const e = wizFill(eff[Math.floor(Math.random()*eff.length)], set, tier);
  if(!trig.length) return e;
  const t = wizFill(trig[Math.floor(Math.random()*trig.length)], set, tier);
  return t + ": " + e;
}

/* A NAME OF HIS OWN (round X). A first name from Names.csv that no card in
   any loaded unit file has, and that this wizard has not already handed out.
   Falls back to "Unit Name" only if Names.csv is not loaded - and the
   checker then flags it. */
const WIZ_NAMES_GIVEN = new Set();
function wizName(){
  const taken = new Set(WIZ_NAMES_GIVEN);
  for(const f of Object.keys(DATA)){
    if(at(f,"Name")<0 || at(f,"Tier")<0) continue;
    col(f,"Name").forEach(v=>v && taken.add(norm(v)));
  }
  const free = col("Names.csv","First Name").filter(v=>v && !taken.has(norm(v)));
  if(!free.length) return "Unit Name";
  const pick = free[Math.floor(Math.random()*free.length)];
  WIZ_NAMES_GIVEN.add(norm(pick));
  return pick;
}

/* ROLL THE NINE. Three per tier, one of each power in that tier's span, so
   the ladder is obeyed by construction rather than checked afterwards. */
function wizRoll(set){
  const out = [];
  wizSetTiers().forEach(tier=>{
    WIZ_POWERS[tier].forEach(power=>{
      out.push({
        tier, power,
        name: wizName(),
        attack: wizOne(set, "attack", tier),
        defend: wizOne(set, "defend", tier),
      });
    });
  });
  return out;
}


/* ------------------------------------------------------------
   DRAWING
   ------------------------------------------------------------ */
function wizDraw(){
  let host = $("#wiz");
  if(!host){ host=document.createElement("div"); host.id="wiz"; document.body.appendChild(host); }

  const labels = ["The class","Emblem 1","Emblem 2","Emblem 3","Finish"];
  const crumbs = labels.map((t,i)=>
    `<div class="${i===WIZ.step?"on":(i<WIZ.step?"did":"")}">${i+1}. ${t}</div>`).join("");

  let body = "", title = "";
  if(WIZ.step===0){ title="New class"; body=wizStepClass(); }
  else if(WIZ.step<=3){ title="Emblem "+WIZ.step+" of 3"; body=wizStepSet(WIZ.step-1); }
  else { title="Finish the class"; body=wizStepFinish(); }

  const back = WIZ.step>0 ? `<button class="btn" id="wBack">Back</button>` : "";
  const next = WIZ.step<4
    ? `<button class="btn key" id="wNext">Next</button>`
    : `<button class="btn key" id="wDone">Write the four files</button>`;

  host.innerHTML = `<div class="sheet">
    <header><h3>${title}</h3><div class="grow" style="flex:1"></div>
      <button class="btn sm" id="wShut">Close</button></header>
    <div class="in"><div class="steps">${crumbs}</div>${body}</div>
    <footer>${back}<div style="flex:1"></div><span id="wSay" style="color:#e07a2c;font-size:12.6px"></span>${next}</footer>
  </div>`;

  $("#wShut").onclick = ()=>{ if(confirm("Close the wizard? Nothing is written until you press the last button.")) host.remove(); };
  if($("#wBack")) $("#wBack").onclick = ()=>{ wizRead(); WIZ.step--; wizDraw(); };
  if($("#wNext")) $("#wNext").onclick = ()=>{
    wizRead();
    const bad = wizComplain();
    if(bad){ $("#wSay").textContent = bad; return; }
    WIZ.step++; wizDraw();
  };
  if($("#wDone")) $("#wDone").onclick = wizWrite;

  // ---- CHANGING THE TOKEN RE-ROLLS THE NINE, on the spot ----
  //
  // Live rather than on Next, because the whole point of the token is that
  // you can see what it does to the nine units while you are choosing it.
  const tok = document.getElementById("sTok");
  if(tok) tok.onchange = ()=>{
    const s2 = WIZ.sets[WIZ.step-1];
    const was = s2.token;
    wizRead();
    if(norm(was) !== norm(s2.token)){ s2.units = wizRoll(s2); wizDraw(); }
  };

  // reroll buttons
  host.querySelectorAll("[data-roll]").forEach(b=>{
    b.onclick = ()=>{ wizRead(); const s=WIZ.sets[+b.dataset.roll]; s.units = wizRoll(s); wizDraw(); };
  });
  host.querySelectorAll("[data-rollone]").forEach(b=>{
    b.onclick = ()=>{
      wizRead();
      const [si,ui] = b.dataset.rollone.split(":").map(Number);
      const s = WIZ.sets[si], u = s.units[ui];
      u.attack = wizOne(s,"attack",u.tier);
      u.defend = wizOne(s,"defend",u.tier);
      wizDraw();
    };
  });
}


function wizStepClass(){
  const els = wizElements().map(e=>
    `<option value="${e}"${e===WIZ.element?" selected":""}>${e}</option>`).join("");
  const tiers = WIZ_TIERS.map(t=>
    `<option value="${t}"${t===WIZ.starTier?" selected":""}>Tier ${t}</option>`).join("");
  return `
  <div class="wizhint"><b>A class is 30 cards.</b> Three Star Players holding one whole tier between them,
  and three sets of nine covering the other three tiers, three cards each. This wizard walks the Emblem
  three times &mdash; Emblem &rarr; Ultimate &rarr; Star &rarr; nine units &mdash; and writes all four files at the end.</div>
  <div class="two">
    <div class="fld"><label>Class</label><input id="wCls" value="${wizEsc(WIZ.cls)}" placeholder="Lorelei">
      <p class="why">The name the CSVs use. It becomes the Unit Type column and the file names.</p></div>
    <div class="fld"><label>Display name</label><input id="wDisp" value="${wizEsc(WIZ.display)}" placeholder="Lorelei">
      <p class="why">What a player sees. Blank uses the class name.</p></div>
  </div>
  <div class="two">
    <div class="fld"><label>Element</label><select id="wEl">${els}</select>
      <p class="why"><b>The element is what this class shares with other classes.</b> An Emblem's Basic side is
      fed by any unit of the same element, whatever its class; only this class can complete the Condition.
      That is the whole reason a second water class is worth writing.</p></div>
    <div class="fld"><label>The Stars' tier</label><select id="wTier">${tiers}</select>
      <p class="why">All three Stars sit in this one tier, filling its three rungs. Each set of nine then
      covers the other three: <b>${wizSetTiers().map(t=>"Tier "+t).join(", ")}</b>.</p></div>
  </div>
  <div class="fld"><label>Description</label><textarea id="wDesc" placeholder="What this class does, in a sentence or two.">${wizEsc(WIZ.description)}</textarea></div>`;
}


function wizStepSet(i){
  const s = WIZ.sets[i];
  // ============ NOTHING IS ROLLED UNTIL THE TOKEN HAS A NAME ============
  //
  // It used to roll on the first draw, which was before you had typed the
  // token — so every {token} came out as the literal word "token" and nine
  // units arrived saying "If this has a token". Naming the token is what the
  // nine units are FOR; rolling before it is set is rolling nothing.
  if(s.token && !s.units) s.units = wizRoll(s);
  const rows = (s.units||[]).map((u,ui)=>`<tr>
      <td class="t">${u.tier}</td><td class="p">${u.power}</td>
      <td><input data-u="${i}:${ui}:name" value="${wizEsc(u.name)}"></td>
      <td><input data-u="${i}:${ui}:attack" value="${wizEsc(u.attack)}"></td>
      <td><input data-u="${i}:${ui}:defend" value="${wizEsc(u.defend)}"></td>
      <td><button class="btn sm" data-rollone="${i}:${ui}">↻</button></td>
    </tr>`).join("");

  return `
  <div class="wizhint"><b>The order matters.</b> The Emblem names the <b>token</b>; the token is what the nine
  units make and spend; the Star carries the Emblem onto the pitch. Written the other way round, the nine
  units have nothing to be about &mdash; which is why the wizard asks in this order and not a tidier one.</div>

  <div class="two">
    <div class="fld"><label>Emblem name</label><input id="sName" value="${wizEsc(s.emblem)}" placeholder="Gremory">
      <p class="why">A Goetia demon, to match the two classes already written. It is also the Star's name.</p></div>
    <div class="fld"><label>Token &mdash; the set's own word</label><input id="sTok" value="${wizEsc(s.token)}" placeholder="Rose Unit">
      <p class="why"><b>The single most important cell on this page.</b> Rose Unit, Swan, Song counter, burn
      counter, Teufel Mask. It is what the nine units make and spend, and it is what makes them read as a set
      that belongs together rather than nine cards that share a class. Every <code>{token}</code> below is filled with it.</p></div>
  </div>

  <div class="fld"><label>Basic side &mdash; what the Emblem does from kick-off</label>
    <textarea id="sBasic" placeholder="When two or more water units enter the exhaust after combat, gain a Rose Unit Token…">${wizEsc(s.basic)}</textarea></div>

  <div class="fld"><label>Condition &mdash; what a player reads</label>
    <textarea id="sCond" placeholder="If all three Tier I Units that were removed to create Rose Token Units were Lorelei: Transform this Emblem.">${wizEsc(s.condition)}</textarea>
    <p class="why">Prose, for the card. The game cannot read it &mdash; that is the next two boxes.</p></div>

  <div class="two">
    <div class="fld"><label>Counter it waits on</label><input id="sCount" value="${wizEsc(s.counter)}" placeholder="lorelei_tier_i_traded">
      <p class="why">A row of Stats.csv. The emblem bar reads the progress out of this.</p></div>
    <div class="fld"><label>How many</label><input id="sNeed" type="number" min="1" max="30" value="${s.need}">
      <p class="why"><b>Keep the three within one or two of each other.</b> Only the first Emblem to complete turns
      over, so one that needs eight when another needs three is an Ultimate no player will ever see.</p></div>
  </div>

  <div class="fld"><label>Ultimate side &mdash; the other face</label>
    <textarea id="sUlt" placeholder="Your Basic side is still active. Instead of only Tier I…">${wizEsc(s.ultimate)}</textarea>
    <p class="why">This goes on <b>both</b> the Emblem and the Star: when the Condition completes, the Emblem turns
    over and the Star turns to its Ultimate Side at the same moment. A player can read it on hover from the first minute.</p></div>

  <div class="two">
    <div class="fld"><label>The Star's one ability</label><textarea id="sFront" placeholder="If you control 4 tokens: Deal +2 damage during combat">${wizEsc(s.starFront)}</textarea>
      <p class="why">A Star has <b>one</b> ability, not an attack and a defend. That is the change.</p></div>
    <div class="fld"><label>The Star's power</label>
      <select id="sPow">${WIZ_POWERS[WIZ.starTier].map(p=>
        `<option value="${p}"${s.starPower===p?" selected":""}>${p}</option>`).join("")}</select>
      <p class="why">Tier ${WIZ.starTier} holds ${WIZ_POWERS[WIZ.starTier].join(", ")}. Give the three Stars one each.</p></div>
  </div>

  <div class="fld"><label>The nine units &mdash; rolled from UnitActions.csv</label>
    <p class="why">Three per tier, one of each power in that tier's span, so the ladder is obeyed by construction.
    Every ability is a <b>trigger and an effect</b> joined by a colon, drawn from the vocabulary in UnitActions.csv and
    filtered to this element and these tiers. <b>Edit any of them &mdash; a roll is a first draft, not a decision.</b>
    <button class="btn sm" data-roll="${i}">Roll all nine again</button></p>
    ${s.token ? `<table class="rolled">
      <thead><tr><th>tier</th><th>pow</th><th>name</th><th>attack</th><th>defend</th><th></th></tr></thead>
      <tbody>${rows}</tbody>
    </table>` : `<div class="wizhint wizbad"><b>Name the token first.</b> The nine units are rolled around it —
      roll them before it has a name and every one of them says "if this has a token".</div>`}
  </div>`;
}


function wizStepFinish(){
  const cls = WIZ.cls;
  const files = [
    ["ClassInfo.csv", "1 row", "the class, its element and its Star tier"],
    ["Star Players.csv", "3 rows", "one per Star: front side, ultimate side, both artworks"],
    [`${cls} Emblems.csv`, "3 rows", "one per Emblem, each naming its Star, its set and its token"],
    [`Unit_Set_${cls.replace(/[^A-Za-z0-9]+/g,"_")}.csv`, "27 rows", "three sets of nine"],
  ];
  const rows = files.map(([f,n,w])=>`<tr><td class="t">${wizEsc(f)}</td><td class="p">${n}</td><td>${w}</td></tr>`).join("");

  const warn = [];
  const needs = WIZ.sets.map(s=>s.need);
  const spread = Math.max(...needs) - Math.min(...needs);
  if(spread >= 3) warn.push(`The three Conditions need ${needs.join(", ")} — a spread of ${spread}.
    Only the first to complete turns over, so the longest will almost never be the one a player sees.
    Bring them within one or two of each other.`);
  const tokens = WIZ.sets.map(s=>norm(s.token));
  if(new Set(tokens).size !== 3) warn.push("Two sets share a token. Each set wants its own word, or the nine units of one are indistinguishable from the nine of another.");

  return `
  <div class="wizhint"><b>${wizEsc(WIZ.display||cls)}</b> — ${wizEsc(WIZ.element)}, Stars in Tier ${WIZ.starTier},
  ${WIZ.sets.map(s=>wizEsc(s.emblem)).join(" · ")}. Thirty cards.</div>
  ${warn.map(w=>`<div class="wizhint wizbad"><b>Worth fixing first.</b> ${w}</div>`).join("")}
  <table class="rolled"><thead><tr><th>file</th><th>what it gets</th><th></th></tr></thead><tbody>${rows}</tbody></table>
  <p class="why" style="margin-top:12px">Rows are <b>added</b> to the files you already have and a file that does
  not exist yet is created. Nothing is overwritten. When this is done, open <b>Export</b> and copy each of the
  four into your <code>data</code> folder &mdash; and remember a new file needs a <code>.csv.import</code>
  beside it, which <b>Where things go</b> explains.</p>`;
}


/* ------------------------------------------------------------
   READING THE FORM BACK
   ------------------------------------------------------------ */
function wizRead(){
  const v = id => { const e=document.getElementById(id); return e ? e.value : undefined; };
  if(WIZ.step===0){
    if(v("wCls")!==undefined) WIZ.cls = v("wCls").trim();
    if(v("wDisp")!==undefined) WIZ.display = v("wDisp").trim();
    if(v("wEl")!==undefined) WIZ.element = v("wEl");
    if(v("wTier")!==undefined && v("wTier")!==WIZ.starTier){
      WIZ.starTier = v("wTier");
      // THE TIERS CHANGED, so nine units rolled for the old ones are wrong.
      WIZ.sets.forEach(s=>{ s.units=null; s.starPower=null; });
    }
    if(v("wDesc")!==undefined) WIZ.description = v("wDesc");
    return;
  }
  if(WIZ.step>=1 && WIZ.step<=3){
    const s = WIZ.sets[WIZ.step-1];
    if(v("sName")!==undefined) s.emblem = v("sName").trim();
    if(v("sTok")!==undefined) s.token = v("sTok").trim();
    if(v("sBasic")!==undefined) s.basic = v("sBasic");
    if(v("sCond")!==undefined) s.condition = v("sCond");
    if(v("sCount")!==undefined) s.counter = v("sCount").trim();
    if(v("sNeed")!==undefined) s.need = Math.max(1, parseInt(v("sNeed"),10)||1);
    if(v("sUlt")!==undefined) s.ultimate = v("sUlt");
    if(v("sFront")!==undefined) s.starFront = v("sFront");
    if(v("sPow")!==undefined) s.starPower = parseInt(v("sPow"),10);
    document.querySelectorAll("[data-u]").forEach(inp=>{
      const [si,ui,field] = inp.dataset.u.split(":");
      const set = WIZ.sets[+si];
      if(set && set.units && set.units[+ui]) set.units[+ui][field] = inp.value;
    });
  }
}

function wizComplain(){
  if(WIZ.step===0){
    if(!WIZ.cls) return "The class needs a name.";
    if(DATA["ClassInfo.csv"] && ids("ClassInfo.csv","Class").has(norm(WIZ.cls)))
      return `There is already a class called ${WIZ.cls}.`;
    return "";
  }
  if(WIZ.step>=1 && WIZ.step<=3){
    const s = WIZ.sets[WIZ.step-1];
    if(!s.emblem) return "The Emblem needs a name.";
    if(!s.token) return "The Emblem needs a token — it is what the nine units are about.";
    if(s.starPower===null || s.starPower===undefined) return "Give the Star a power.";
    if(!s.units || !s.units.length) return "The nine units have not been rolled yet — press \u201cRoll all nine again\u201d.";
    const others = WIZ.sets.filter((x,i)=>i!==WIZ.step-1);
    if(others.some(x=>x.emblem && norm(x.emblem)===norm(s.emblem)))
      return "Two Emblems share that name.";
    if(others.some(x=>x.starPower===s.starPower))
      return `Another Star already has power ${s.starPower}. Tier ${WIZ.starTier} holds ${WIZ_POWERS[WIZ.starTier].join(", ")} — one each.`;
    return "";
  }
  return "";
}


/* ------------------------------------------------------------
   WRITING THE FOUR FILES
   ------------------------------------------------------------ */
function wizAdd(file, headers, rows){
  if(!DATA[file]) DATA[file] = {headers: headers.slice(), rows: []};
  const d = DATA[file];
  headers.forEach(h=>{ if(d.headers.indexOf(h)<0){ d.headers.push(h); d.rows.forEach(r=>r.push("")); } });
  rows.forEach(obj=>{
    const r = d.headers.map(h => obj[h]!==undefined ? String(obj[h]) : "");
    d.rows.push(r);
  });
}

function wizWrite(){
  wizRead();
  const cls = WIZ.cls;
  const file = `Unit_Set_${cls.replace(/[^A-Za-z0-9]+/g,"_")}.csv`;
  const emb = `${cls} Emblems.csv`;

  wizAdd("ClassInfo.csv",
    ["Class","Display Name","Description","Banner Art","Formation Art","Element","Star Tier","Requires","Hidden","Notes"],
    [{ "Class":cls, "Display Name":WIZ.display||cls, "Description":WIZ.description,
       "Element":WIZ.element, "Star Tier":WIZ.starTier, "Hidden":"no",
       "Notes":"Written by the New Class wizard." }]);

  wizAdd(emb,
    ["Name","Unit Type","Emblem","Star","Set","Token","Basic Feeds","Order","Basic Side","Condition","Turns On","Ultimate Side","For AI notes"],
    WIZ.sets.map((s,i)=>({
      "Name":s.emblem, "Unit Type":cls, "Emblem":`${s.emblem}_Emblem.png`,
      "Star":s.emblem, "Set":s.emblem, "Token":s.token,
      "Basic Feeds":"element", "Order":String(i+1),
      "Basic Side":s.basic, "Condition":s.condition,
      "Turns On": s.counter ? `count:${s.counter}>=${s.need}` : "",
      "Ultimate Side":s.ultimate,
      "For AI notes":"",
    })));

  let card = 1;
  wizAdd("Star Players.csv",
    ["Unit Type","Name","Front Side","Ultimate Side","Element","Base Power ","Tier","Card Number","Emblem","Set","Set Name","Artwork","Ultimate Artwork","Player Type","Notes"],
    WIZ.sets.map(s=>({
      "Unit Type":cls, "Name":s.emblem, "Front Side":s.starFront, "Ultimate Side":s.ultimate,
      "Element":WIZ.element, "Base Power ":String(s.starPower), "Tier":WIZ.starTier,
      "Card Number":String(card++), "Emblem":s.emblem, "Set":s.emblem, "Set Name":"Star",
      "Artwork":`Star_${cls}_${s.emblem}.png`, "Ultimate Artwork":`Star_${cls}_${s.emblem}_U.png`,
      "Player Type":"Star", "Notes":"",
    })));

  const units = [];
  WIZ.sets.forEach(s=>{
    (s.units||[]).forEach(u=>{
      units.push({
        "Unit Type":cls, "Name":u.name, "Attack":u.attack, "Defend":u.defend,
        "Element":WIZ.element, "Base Power ":String(u.power), "Tier":u.tier,
        "Card Number":String(card++), "Set Name":s.emblem,
        "Artwork":`${s.emblem}_${cls}.png`, "Player Type":"Normal",
      });
    });
  });
  wizAdd(file,
    ["Unit Type","Name","Attack","Defend","Element","Base Power ","Tier","Card Number","Set Name","Artwork","Player Type"],
    units);

  save(); check(); paintRail(); CUR = emb; paintTable();
  const host=$("#wiz"); if(host) host.remove();
  showText(`${cls} — written`,
    [`${cls} is in the workbench. Four files were touched:`,
     ``,
     `  ClassInfo.csv        + 1 row`,
     `  Star Players.csv     + 3 rows`,
     `  ${emb}${" ".repeat(Math.max(1,20-emb.length))}+ 3 rows`,
     `  ${file}${" ".repeat(Math.max(1,20-file.length))}+ ${units.length} rows`,
     ``,
     `NOTHING IS ON YOUR DISK YET. Open Export, pick each of those four and`,
     `copy or download it into your project's data folder.`,
     ``,
     `A FILE YOU HAVE JUST CREATED ALSO NEEDS A .csv.import BESIDE IT —`,
     `three lines, and "Where things go" has them. Without it Godot reads`,
     `your spreadsheet as a translation table and litters the folder.`,
     ``,
     `STILL TO DO, and none of it is code:`,
     `  · ${WIZ.sets.map(s=>s.counter).filter(Boolean).join(", ") || "(no counters named)"} — add them to Stats.csv`,
     `    and wire the Event column, or the Conditions can never fill.`,
     `  · draw the art: ${WIZ.sets.length} emblems, ${WIZ.sets.length} Star fronts,`,
     `    ${WIZ.sets.length} Star ultimates, ${WIZ.sets.length} set sheets. Sizes are on "Art & sizes".`,
     `  · run tools/emblem_check.gd — it prices the race in duels and will`,
     `    tell you which of your three Ultimates a player will actually see.`,
    ].join("\n"));
}


function wizEsc(s){
  return String(s==null?"":s).replace(/&/g,"&amp;").replace(/</g,"&lt;")
    .replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
