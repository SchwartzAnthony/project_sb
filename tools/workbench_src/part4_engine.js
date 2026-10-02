
/* ============================================================ */
let DATA = {}, CUR = null, PROBS = [], OPEN = true, SAMPLE = false, HAVE = {};
const $ = s => document.querySelector(s);
const norm = s => String(s||"").trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const VIEWS = {"@assets":"Where things go", "@art":"Art & sizes", "@book":"Handbook", "@cheat":"Reference", "@words":"Keywords"};

function boot(){
  let saved = null;
  try{ saved = JSON.parse(localStorage.getItem("sturmball.v2")||"null"); }catch(e){}
  if(!saved){ try{ saved = JSON.parse(localStorage.getItem("sturmball.v1")||"null"); }catch(e){} }
  try{ HAVE = JSON.parse(localStorage.getItem("sturmball.have")||"{}"); }catch(e){ HAVE={}; }
  SAMPLE = !(saved && Object.keys(saved).length);
  DATA = SAMPLE ? JSON.parse(JSON.stringify(unseed())) : saved;
  CUR = Object.keys(DATA)[0] || null;
  paintRail(); paintTable(); check();
}
function unseed(){
  const out = {};
  for(const [f,v] of Object.entries(SEED)) out[f] = {headers:v.h.slice(), rows:v.r.map(r=>r.slice())};
  return out;
}
function save(){
  try{ localStorage.setItem("sturmball.v2", JSON.stringify(DATA)); }catch(e){}
}
function saveHave(){ try{ localStorage.setItem("sturmball.have", JSON.stringify(HAVE)); }catch(e){} }

/* ---------- CSV ---------- */
function parseCSV(text){
  const rows=[]; let row=[], cell="", q=false;
  text = text.replace(/\r\n?/g,"\n");
  for(let i=0;i<text.length;i++){
    const c=text[i];
    if(q){
      if(c==='"'){ if(text[i+1]==='"'){cell+='"';i++;} else q=false; }
      else cell+=c;
    } else if(c==='"') q=true;
    else if(c===","){ row.push(cell); cell=""; }
    else if(c==="\n"){ row.push(cell); rows.push(row); row=[]; cell=""; }
    else cell+=c;
  }
  if(cell!==""||row.length){ row.push(cell); rows.push(row); }
  return rows.filter(r=>r.length && r.some(c=>c.trim()!==""));
}
function toCSV(f){
  const d=DATA[f]; const esc=v=>{v=String(v??"");return /[",\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;};
  return [d.headers.map(esc).join(",")].concat(d.rows.map(r=>{
    const out=[]; for(let i=0;i<d.headers.length;i++) out.push(esc(r[i]??""));
    return out.join(",");
  })).join("\n")+"\n";
}

/* ---------- little readers ---------- */
const at  = (f,c)=>DATA[f]?DATA[f].headers.indexOf(c):-1;
const col = (f,c)=>{const i=at(f,c);return i<0?[]:DATA[f].rows.map(r=>(r[i]||"").trim());};
const ids = (f,c)=>new Set(col(f,c).filter(Boolean).map(norm));
/* Every unit file: anything with a Unit Type column and a power column. */
function unitFiles(){
  return Object.keys(DATA).filter(f => at(f,"Unit Type")>=0 && at(f,"Base Power Left")>=0);
}

/* ---------- rail ---------- */
function paintRail(){
  const sp=$("#special"); sp.innerHTML="";
  for(const [k,label] of Object.entries(VIEWS)){
    const b=document.createElement("button");
    b.className="fitem special"+(k===CUR?" on":"");
    // A PAGE WITHOUT A COUNT SHOWS NOTHING, rather than a question mark.
    // Reference and Handbook are read, not worked through; a number beside
    // them was never anything but noise.
    let n = "";
    if(k==="@assets") n = String(assetWants().length);
    if(k==="@art") n = artDone()+"/"+artRowCount();
    if(k==="@words") n = String(keywordCount());
    b.innerHTML=`<span class="fn"></span>`+(n?`<span class="fc">${n}</span>`:"");
    b.querySelector(".fn").textContent=label;
    b.onclick=()=>{CUR=k;paintRail();paintTable();};
    sp.appendChild(b);
  }
  const host=$("#files"); host.innerHTML="";
  for(const f of Object.keys(DATA).sort()){
    const b=document.createElement("button");
    b.className="fitem"+(f===CUR?" on":"");
    const bad=PROBS.some(p=>p.file===f);
    b.innerHTML=`<span class="fn"></span><span class="fc">${DATA[f].rows.length}</span>`+(bad?'<span class="dot"></span>':'');
    b.querySelector(".fn").textContent=f.replace(/\.csv$/i,"");
    b.onclick=()=>{CUR=f;paintRail();paintTable();};
    host.appendChild(b);
  }
}

/* ---------- table ---------- */
function paintTable(){
  const wrap=$("#wrap");
  $("#tools").innerHTML="";
  if(CUR==="@assets"){ return paintBoard(); }
  if(CUR==="@art"){ return paintArt(); }
  if(CUR==="@book"){ return paintBook(); }
  if(CUR==="@cheat"){ return paintCheat(); }
  if(CUR==="@words"){ return paintWords(); }
  if(!CUR||!DATA[CUR]){
    $("#title").textContent="Nothing loaded";
    $("#what").textContent="";
    $("#help").hidden=true;
    wrap.innerHTML=`<div class="empty"><h3>Load your data folder</h3>
      <p>Drop your <span class="kbd">.csv</span> files in, or press <b>Load CSVs</b> and pick everything in your project's <span class="kbd">data</span> folder at once.</p></div>`;
    return;
  }
  const d=DATA[CUR], scheme=sch(CUR);
  $("#title").textContent=CUR.replace(/\.csv$/i,"");
  $("#what").textContent=scheme.what||"A file the workbench does not have notes for. It still edits fine, and the checker still watches its ids.";
  $("#help").hidden=!scheme.help; if(scheme.help) $("#help").innerHTML=scheme.help;

  const mk=(t,fn,cls)=>{const b=document.createElement("button");b.className="btn sm "+(cls||"");b.textContent=t;b.onclick=fn;$("#tools").appendChild(b);return b;};
  mk("+ New row",()=>{
    const r=d.headers.map(h=>(NEW[CUR]||{})[h]||"");
    d.rows.push(r); save(); paintTable(); check(); paintRail();
    const inputs=wrap.querySelectorAll("tbody tr:last-child input,tbody tr:last-child select");
    if(inputs[0]) inputs[0].focus();
  },"key");
  mk("+ Column",()=>{
    const n=prompt("New column name (write it the way a person would — \"Max Stamina\"):");
    if(!n) return; d.headers.push(n); d.rows.forEach(r=>r.push("")); save(); paintTable();
  });
  mk("Copy this file",()=>showExport(CUR));
  mk("Sort by first column",()=>{d.rows.sort((a,b)=>String(a[0]).localeCompare(String(b[0])));save();paintTable();});

  const tbl=document.createElement("table");
  const thead=document.createElement("thead"), hr=document.createElement("tr");
  hr.innerHTML='<th style="width:1px"></th><th style="width:1px">#</th>';
  d.headers.forEach(h=>{
    const th=document.createElement("th");
    th.textContent=h;
    if(/^(requires|effects|action|do|reward|on win|on loss)$/i.test(h)) th.className="req";
    hr.appendChild(th);
  });
  thead.appendChild(hr); tbl.appendChild(thead);

  const tb=document.createElement("tbody");
  d.rows.forEach((row,ri)=>{
    const tr=document.createElement("tr");
    const tools=document.createElement("td"); tools.className="rowtools";
    tools.innerHTML='<button class="ico" title="Duplicate">⧉</button><button class="ico del" title="Delete">✕</button>';
    tools.children[0].onclick=()=>{d.rows.splice(ri+1,0,row.slice());save();paintTable();check();paintRail();};
    tools.children[1].onclick=()=>{if(confirm("Delete this row?")){d.rows.splice(ri,1);save();paintTable();check();paintRail();}};
    tr.appendChild(tools);
    const n=document.createElement("td"); n.className="rn"; n.textContent=ri+2; tr.appendChild(n);

    d.headers.forEach((h,ci)=>{
      const td=document.createElement("td");
      td.appendChild(cell(CUR,h,row,ci,ri));
      if(PROBS.some(p=>p.file===CUR&&p.row===ri&&p.col===h)) td.className="bad";
      tr.appendChild(td);
    });
    tb.appendChild(tr);
  });
  tbl.appendChild(tb);
  wrap.innerHTML=""; wrap.appendChild(tbl);
}

function cell(file,head,row,ci,ri){
  const scheme=sch(file), val=row[ci]??"";
  const set=v=>{row[ci]=v;save();};
  let opts=(scheme.enums||{})[head];
  const ref=(REFS[file]||{})[head];

  /* A unit file is recognised by its columns, so its enums are too — that
     way a set you add tomorrow gets the same dropdowns as the ones here. */
  if(!opts && at(file,"Unit Type")>=0 && at(file,"Base Power Left")>=0){
    if(head==="Tier") opts=TIERS;
    if(head==="Player Type") opts=["Normal","Star"];
  }

  if(opts||ref){
    const sel=document.createElement("select");
    let list=opts?opts.slice():[""];
    if(ref){
      const [rf,rc]=ref, src=DATA[rf];
      if(src){
        const at2=src.headers.indexOf(rc);
        if(at2>=0){ const seen=new Set();
          src.rows.forEach(r=>{const v=(r[at2]||"").trim(); if(v&&!seen.has(v)){seen.add(v);list.push(v);} }); }
      }
      if(val&&!list.includes(val)) list.push(val);
    }
    if(val&&!list.includes(val)) list.push(val);
    list.forEach(o=>{const e=document.createElement("option");e.value=o;e.textContent=o===""?"—":o;sel.appendChild(e);});
    sel.value=val; sel.onchange=()=>{set(sel.value);check();paintRail();};
    sel.id=`c_${norm(file)}_${ri}_${ci}`;
    return sel;
  }
  if((scheme.colour||[]).includes(head)){
    const box=document.createElement("div"); box.style.display="flex"; box.style.alignItems="center";
    const sw=document.createElement("input"); sw.type="color"; sw.value=/^#[0-9a-f]{6}$/i.test(val)?val:"#213a26";
    sw.style.cssText="width:26px;min-width:26px;height:24px;border:1px solid var(--line);padding:0;margin:5px 0 5px 7px;cursor:pointer;background:none";
    const tx=document.createElement("input"); tx.value=val;
    sw.oninput=()=>{tx.value=sw.value;set(sw.value);};
    tx.oninput=()=>{set(tx.value); if(/^#[0-9a-f]{6}$/i.test(tx.value)) sw.value=tx.value;};
    tx.id=`c_${norm(file)}_${ri}_${ci}`;
    box.appendChild(sw); box.appendChild(tx); return box;
  }
  if(LONG.includes(head)&&String(val).length>34){
    const ta=document.createElement("textarea"); ta.value=val; ta.rows=1;
    ta.oninput=()=>{set(ta.value);}; ta.onblur=()=>{check();paintRail();};
    ta.id=`c_${norm(file)}_${ri}_${ci}`; return ta;
  }
  const inp=document.createElement("input"); inp.value=val;
  inp.oninput=()=>set(inp.value);
  inp.onblur=()=>{check();paintRail();};
  inp.id=`c_${norm(file)}_${ri}_${ci}`;
  return inp;
}

/* ============================================================
   WHERE THINGS GO — the folder board and the shopping list.
   ============================================================ */

/* Every file name the spreadsheets ask for, grouped by folder. */
function assetWants(){
  const out=[], seen=new Set();
  for(const [key,folder] of Object.entries(ASSET_COLUMNS)){
    const [file,c]=key.split("|");
    /* A unit file is recognised by its columns, so Artwork is collected from
       EVERY unit file, not only the one named in the map. */
    const files = (c==="Artwork" && at(file,"Unit Type")>=0) ? unitFiles() : [file];
    for(const f of files){
      const i=at(f,c); if(i<0) continue;
      const nameAt=at(f,"Name")>=0?at(f,"Name"):(at(f,"ID")>=0?at(f,"ID"):0);
      DATA[f].rows.forEach((r,ri)=>{
        let v=(r[i]||"").trim();
        if(!v) return;
        if(v.startsWith("res://")) return;      /* already a real path */
        const k=folder.dir+"|"+v.toLowerCase();
        if(seen.has(k)) return; seen.add(k);
        out.push({name:v, folder, file:f, row:ri, col:c, who:(r[nameAt]||"").trim()});
      });
    }
  }
  return out;
}

function paintBoard(){
  $("#title").textContent="Where things go";
  $("#what").textContent="Every folder the game looks in, what belongs in each, and the live list of files your spreadsheets are asking for.";
  $("#help").hidden=false;
  $("#help").innerHTML="Nothing here is checked against your disk — the workbench is a web page and cannot see your project folder. <b>It is a list of what the spreadsheets have asked for</b>, and the ticks are yours to keep, saved in this browser.";

  const mk=(t,fn,cls)=>{const b=document.createElement("button");b.className="btn sm "+(cls||"");b.textContent=t;b.onclick=fn;$("#tools").appendChild(b);return b;};
  mk("Copy the whole list",()=>{
    const lines=[];
    FOLDERS.forEach(f=>{
      const mine=assetWants().filter(w=>w.folder===f);
      if(!mine.length) return;
      lines.push("res://"+f.dir);
      mine.forEach(w=>lines.push("    "+(HAVE[f.dir+w.name]?"[x] ":"[ ] ")+w.name+"   — "+(w.who||w.file)));
      lines.push("");
    });
    const text=lines.join("\n");
    navigator.clipboard.writeText(text).then(()=>alert("The list is on your clipboard."),
      ()=>alert(text));
  },"key");
  mk("Untick everything",()=>{ if(confirm("Clear every tick on this page?")){ Object.keys(HAVE).forEach(k=>{ if(k.indexOf("art:")!==0) delete HAVE[k]; }); saveHave(); paintTable(); paintRail(); } });

  const wants=assetWants();
  const wrap=$("#wrap"); wrap.innerHTML="";
  const board=document.createElement("div"); board.className="board";

  const note=document.createElement("div"); note.className="hint";
  note.innerHTML="<b>The rule for all of them:</b> a column holds the file NAME, without the folder and usually without the extension — a column reading <code>mill</code> finds <code>assets/icons/mill.png</code>. A column starting <code>res://</code> is used exactly as written, wherever it points. Nothing breaks while a file is missing: an icon draws as a coloured pip, a sound is silent, a card falls back to a plain disc. <b>Every folder below is tried in the order shown</b>, so the first one is the tidy home and the rest are fallbacks.";
  board.appendChild(note);

  FOLDERS.forEach(f=>{
    const mine=wants.filter(w=>w.folder===f);
    const done=mine.filter(w=>HAVE[f.dir+w.name]).length;
    const box=document.createElement("div"); box.className="folder";
    const h=document.createElement("h4");
    h.innerHTML=`<span>res://${f.dir}</span><span class="cnt">${mine.length?`${done} of ${mine.length} ticked`:"nothing asks for anything here yet"}</span>`;
    box.appendChild(h);

    const bl=document.createElement("div"); bl.className="blurb";
    bl.innerHTML=`${f.what}<br><b>Format:</b> ${f.formats}<br><span style="color:var(--faint)">${f.also}</span>`;
    box.appendChild(bl);

    mine.sort((a,b)=>a.name.localeCompare(b.name)).forEach(w=>{
      const row=document.createElement("div");
      const key=f.dir+w.name;
      row.className="want"+(HAVE[key]?" done":"");
      const cb=document.createElement("input"); cb.type="checkbox"; cb.checked=!!HAVE[key];
      cb.onchange=()=>{ if(cb.checked) HAVE[key]=true; else delete HAVE[key];
        saveHave(); row.className="want"+(cb.checked?" done":"");
        h.querySelector(".cnt").textContent=`${wants.filter(x=>x.folder===f&&HAVE[f.dir+x.name]).length} of ${mine.length} ticked`;
        paintRail(); };
      const body=document.createElement("div");
      body.innerHTML=`<span class="nm"></span><span class="why"></span>`;
      body.querySelector(".nm").textContent=w.name;
      body.querySelector(".why").textContent=(w.who?w.who+" — ":"")+w.col;
      const src=document.createElement("span"); src.className="src";
      src.textContent=w.file.replace(/\.csv$/i,"")+" "+(w.row+2);
      src.style.cursor="pointer";
      src.onclick=()=>{ CUR=w.file; paintRail(); paintTable();
        const el=document.getElementById(`c_${norm(w.file)}_${w.row}_${at(w.file,w.col)}`);
        if(el){ el.scrollIntoView({block:"center",behavior:"smooth"}); el.focus(); } };
      row.appendChild(cb); row.appendChild(body); row.appendChild(src);
      box.appendChild(row);
    });
    board.appendChild(box);
  });

  const last=document.createElement("div"); last.className="hint";
  last.innerHTML="<b>Two folders that are not on this list.</b> <code>res://data/</code> is where every spreadsheet lives — and <b>each .csv needs a .csv.import file beside it</b> containing <code>[remap]</code>, a blank line, then <code>importer=\"keep\"</code>. Without it Godot decides your spreadsheet is a translation table and litters the folder with .translation files. Copy an existing one and rename it. <code>res://src/</code> is the code and you never need to open it.";
  board.appendChild(last);

  wrap.appendChild(board);
}

/* ============================================================
   THE REFERENCE SHEET — the words the spreadsheets speak.
   ============================================================ */

/* ============================================================
   KEYWORDS — every word the game understands, in one place.

   Two files feed it: Keywords.csv (effects, targets, scopes,
   conditions, Adventure effects, item tags) and
   AbilityTriggers.csv (triggers, which the game reads as a list
   of its own). Both are ordinary editable files in the rail;
   this view is the readable version of the two together.
   ============================================================ */
function keywordRows(){
  const out = [];
  const kw = DATA["Keywords.csv"];
  if(kw){
    const k=at("Keywords.csv","Keyword"), f=at("Keywords.csv","Family"),
          st=at("Keywords.csv","Status"), w=at("Keywords.csv","What It Does"),
          ex=at("Keywords.csv","Example"), nt=at("Keywords.csv","Notes");
    kw.rows.forEach((r,ri)=>{
      if(k<0 || !(r[k]||"").trim()) return;
      out.push({file:"Keywords.csv", row:ri, word:r[k], family:(f>=0?r[f]:"")||"other",
        status:((st>=0?r[st]:"")||"live").toLowerCase(),
        what:(w>=0?r[w]:"")||"", example:(ex>=0?r[ex]:"")||"", notes:(nt>=0?r[nt]:"")||""});
    });
  }
  const tg = DATA["AbilityTriggers.csv"];
  if(tg){
    const k=at("AbilityTriggers.csv","ID"), st=at("AbilityTriggers.csv","Status"),
          w=at("AbilityTriggers.csv","Fires When"), nt=at("AbilityTriggers.csv","Notes");
    tg.rows.forEach((r,ri)=>{
      if(k<0 || !(r[k]||"").trim()) return;
      out.push({file:"AbilityTriggers.csv", row:ri, word:r[k], family:"ability trigger",
        status:((st>=0?r[st]:"")||"live").toLowerCase(),
        what:(w>=0?r[w]:"")||"", example:"", notes:(nt>=0?r[nt]:"")||""});
    });
  }
  return out;
}
function keywordCount(){ return keywordRows().filter(r=>r.status==="live").length; }

function paintWords(){
  const wrap=$("#wrap");
  $("#title").textContent="Keywords";
  $("#what").textContent="Every word the game understands, and what it does. Live means it is built; planned means it is designed and waiting.";
  $("#help").hidden=false;
  $("#help").innerHTML="<b>To ask for a new keyword</b>, press the button below or add a row to <b>Keywords.csv</b> in the rail: pick the family, leave Status on <code>planned</code>, and write <b>What It Does</b> as one clear sentence. That sentence is the specification \u2014 whoever builds it works from your words.<br><b>A card written against a planned word still loads.</b> It is not an error and it is not a typo; it simply does nothing until the word exists, and the game says so once in the Output panel.";

  $("#tools").innerHTML="";
  const mk=(t,fn,cls)=>{const b=document.createElement("button");b.className="btn sm "+(cls||"");b.textContent=t;b.onclick=fn;$("#tools").appendChild(b);return b;};
  mk("+ Ask for a keyword",()=>{
    if(!DATA["Keywords.csv"]){ alert("Load your data folder first — Keywords.csv is the file this writes to."); return; }
    const word=prompt("The word itself, as you would write it in a spreadsheet cell:");
    if(!word) return;
    const what=prompt("What should it do? One clear sentence — this is the specification.");
    const d=DATA["Keywords.csv"];
    const r=d.headers.map(h=>{
      if(h==="Keyword") return word;
      if(h==="Family") return "ability effect";
      if(h==="Status") return "planned";
      if(h==="What It Does") return what||"";
      return "";
    });
    d.rows.push(r); save(); paintWords(); paintRail(); check();
  },"key");
  mk("Copy the planned list",()=>{
    const want=keywordRows().filter(r=>r.status!=="live");
    const text=want.length
      ? want.map(r=>`${r.word}  [${r.family}]  ${r.what}`).join("\n")
      : "Nothing is planned — everything you have written is already built.";
    showText("Keywords still to build", text);
  });

  const board=document.createElement("div"); board.className="board";
  const rows=keywordRows();
  if(!rows.length){
    wrap.innerHTML='<div class="empty"><h3>No keyword files loaded</h3><p>Load your <span class="kbd">data</span> folder. Keywords.csv and AbilityTriggers.csv are what this page reads.</p></div>';
    return;
  }
  const families=[...new Set(rows.map(r=>r.family))];
  for(const family of families){
    const mine=rows.filter(r=>r.family===family);
    const c=document.createElement("div"); c.className="cheat";
    const live=mine.filter(r=>r.status==="live").length;
    c.innerHTML=`<h4>${family} &mdash; ${live} built, ${mine.length-live} planned</h4><div class="in"></div>`;
    const body=c.querySelector(".in");
    const tbl=document.createElement("table");
    for(const r of mine){
      const tr=document.createElement("tr");
      const a=document.createElement("td");
      a.innerHTML=`<code>${r.word}</code>`+(r.status==="live"?"":' <span style="color:var(--accent)">planned</span>');
      const b=document.createElement("td");
      b.textContent=r.what || "—";
      if(r.example) b.innerHTML += `<div style="color:var(--dim);font-size:12px">e.g. ${r.example}</div>`;
      tr.appendChild(a); tr.appendChild(b);
      tbl.appendChild(tr);
    }
    body.appendChild(tbl);
    board.appendChild(c);
  }
  wrap.innerHTML=""; wrap.appendChild(board);
}

function paintCheat(){
  $("#title").textContent="Reference";
  $("#what").textContent="The small languages that turn up in a dozen different columns, and the lists the game checks against.";
  $("#help").hidden=true;
  const wrap=$("#wrap"); wrap.innerHTML="";
  const board=document.createElement("div"); board.className="board";

  const card=(title,html)=>{
    const c=document.createElement("div"); c.className="cheat";
    c.innerHTML=`<h4>${title}</h4><div class="in">${html}</div>`;
    return c;
  };
  const rows=list=>"<table>"+list.map(([a,b])=>`<tr><td>${a}</td><td>${b}</td></tr>`).join("")+"</table>";

  board.appendChild(card("Asking a question — the Requires column", rows([
    ["flag:brave","the flag is set"],
    ["!flag:brave","the flag is NOT set"],
    ["unlocked:Lorelei","you have unlocked it"],
    ["count:gold&gt;=10","a number comparison. <code>&gt;= &gt; &lt;= &lt; = !=</code> all work"],
    ["count:gold","shorthand for \"more than zero\""],
    ["is:winter","a state check"],
    ["a;b","<b>both</b> must be true. The separator is a semicolon — <code>and</code> is not a word this understands"],
  ])));

  board.appendChild(card("Making something happen — Effects, Do, Action, On Win, Reward", rows([
    ["unlock:Water Brew","unlock something by name"],
    ["flag:beat_the_keeper","set a flag. An achievement is a flag and nothing else"],
    ["flag:brave=false","clear a flag"],
    ["count:gold+10","add to a number"],
    ["count:gold-25","take some away. A shop price is one cell"],
    ["count:gold=0","set it outright"],
    ["count:tune_press_speed+12","<b>edit a row of Tuning.csv.</b> Any row. This is how talents work"],
    ["sign:Müller","a card joins your squad (read once <code>squad_ownership</code> is on)"],
    ["count:tune_foul_card_bonus_enemy+1","a talent leaning on the referee - every opponent easier to book"],
    ["recruit:I0","<b>a new plain player</b>, Tier I Power 0, with a unique name from Names.csv. <code>recruit:I0=Johannes</code> asks for a name"],
    ["release:Johannes","he leaves the base for good, and his name is free again"],
    ["story:prologue","play a dialogue scene"],
    ["announce:First win!","put a banner on the screen"],
  ])));

  board.appendChild(card("The tier ladder", `
    <p style="margin:0 0 9px">Every tier holds <b>one card of each power in its span</b> — never two the same.
    Tier I is 0 to 2, so it holds one 0, one 1 and one 2.</p>
    ${rows([["Tier I","0 · 1 · 2"],["Tier II","1 · 2 · 3"],["Tier III","2 · 3 · 4"],["Tier IV","3 · 4 · 5"]])}
    <p style="margin:9px 0 0;color:var(--dim)">Three consequences. A card's power is its <b>slot</b>, not a stat.
    Every legal team has the same total power — teams differ by what their players <i>do</i>.
    And <b>a bonus is never added to a card</b>: combos, difficulty, talents and trait breakpoints
    all go on the SHOT, because anything that moved a card would put two cards on one rung.</p>`));

  board.appendChild(card("Adventure — the pile", `
    <p style="margin:0 0 9px">Every player you draft drops their <b>icons</b> on a pile.
    The pile does <b>not</b> empty each round — it empties at the end of the round in which the
    <b>cycle</b> comes round, meaning every tier has fielded everybody it has.</p>
    ${rows([
      ["attack","Value is added to the SHOT. Target: —"],
      ["strike","Value damage into enemies. Target: <code>all</code> / <code>focus</code>"],
      ["heal","Value stamina back. Target: <code>lowest</code> / <code>all</code> / <code>last</code>"],
      ["stamina","the same thing under a friendlier name"],
      ["revive","Value players get up. Target: how much stamina each"],
      ["shield","Value off every hit against you. Target: —"],
      ["spawn","Value stand-ins walk on. Target: a row of AdventureSpawns.csv"],
    ])}
    <p style="margin:9px 0 0;color:var(--dim)"><b>held</b> applies for as long as you hold that many, and only the
    HIGHEST breakpoint in a trait counts. <b>once</b> fires the moment you reach it and not again until the pile empties.</p>
    <p style="margin:9px 0 0;color:var(--dim)"><b>A run carries eight icons</b> — <code>adventure_trait_slots</code>.
    Write as many as you like in AdventureTraits.csv; an icon outside the eight has no bar, drops nothing on
    the pile and never reaches a breakpoint. A <code>Requires</code> on an icon is what keeps it off the shelf
    until the player has earned it.</p>`));

  board.appendChild(card("Juice — the fourteen moments", rows(
    MOMENTS.map(m=>[m, ({
      ball_received:"a player takes the ball",
      ball_kicked:"a player strikes it",
      enemy_hit:"your shot lands on an enemy",
      enemy_died:"an enemy goes down",
      player_hurt:"one of yours takes a hit",
      player_exhausted:"one of yours runs out of stamina",
      player_healed:"an item or a combo mends somebody",
      combo_fired:"a breakpoint goes off",
      shot_struck:"the final shot of an Adventure move",
      enemy_windup:"an enemy gains its buff",
      goal_scored:"a goal in a league match",
      play_maker:"PLAY MAKER fires",
      star_switch:"STAR PLAYER SWITCH",
      coin_exact:"somebody named the clash coin exactly",
    })[m]||""])
  )+`<p style="margin:9px 0 0;color:var(--dim)">A moment nobody wrote a row for simply does nothing.
    Two rows may share one moment and both fire — one shaking the enemy, one shaking the screen.</p>`));

  board.appendChild(card("The match — the three switches on the opening minute", `
    <p style="margin:0 0 9px">All three live in <b>Tuning.csv</b> and all three can be turned off,
    which puts the match back exactly as it was.</p>
    ${rows([
      ["kickoff_countdown","the camera pushes in on two players over the ball in the centre circle, <b>3 · 2 · 1 · START</b>, and then the ball is <b>loose</b> and both sides run at it. <code>kickoff_count_seconds</code> and <code>kickoff_go_seconds</code> are the pace. FALSE and your Star simply starts holding it"],
      ["use_coin_clash","PLAY MAKER asks for <b>a number from one to ten</b> instead of rock-paper-scissors. A coin lands on one; whoever called closer chooses attack or defend. <code>coin_faces</code> is how many numbers, <code>coin_spin_seconds</code> is the spin. Their call is always drawn from the numbers you did <i>not</i> pick, so there is never a draw"],
      ["coin_exact_words","<b>naming the number exactly</b> gets its own words and its own animation — the coin swells and turns gold. <code>coin_exact_seconds</code> is how long it is held, and <code>coin_exact</code> is a Juice moment, so a row there hangs the sound on it"],
      ["game_speed_buttons","<b>1x is always there; 2x, 4x and 8x are shown GREYED until this passes</b>, and pressing a locked one says so rather than doing nothing. <code>game_speed_buttons_needs</code> takes a Requires condition, so the speed control is something the player earns, and <code>game_speed_locked_words</code> is what a locked one says. Holding the mouse or the spacebar through a duel hurries it along either way — that is separate and always on"],
      ["pass_skips_tiers","which tiers are <b>never passed to</b> in ordinary play. <code>IV</code> out of the box, because a Tier IV taking the ball on the edge of the box and knocking it sideways raises the obvious question of why they did not shoot. <code>none</code> lets the ball go to anybody"],
      ["goal_pause_seconds / save_pause_seconds","the hold at a restart. The break is ended the moment the ball is dead and <b>every outfield player walks home while the keeper is left alone on the ball</b> — nobody stands over the keeper, and the ball is kicked into a pitch that has a shape. Two seconds out of the box; <code>restart_walk_boost</code> is how briskly they walk"],
    ])}
    <p style="margin:9px 0 0;color:var(--dim)">The labels over a player's head and the
    <b>Tier · Power</b> window at their feet are the same in a league match and in Adventure, and are
    tuned with the <code>plate_</code> rows. Adventure adds a stamina bar under them; a league
    match has nothing to draw one from, so it does not.</p>`));

  board.appendChild(card("The Inventory — three tabs", `
    <p style="margin:0 0 9px">One window, opened from the base, the Bounty Board, an Adventure fight
    and the match draft. Which page a row of <b>Items.csv</b> lands on is its <code>Tab</code> column,
    and if you leave that blank it is worked out from <code>Kind</code>.</p>
    ${rows([
      ["items","things you <b>use</b> — brews, bandages, smelling salts. <b>Only this tab is ever clickable</b>"],
      ["resources","things you <b>spend</b> — reed, bog iron, coins"],
      ["keys","things you <b>hold</b> and never spend — a key, a token, a letter"],
      ["blank","worked out: <code>key/token/quest</code> → keys · <code>material/currency</code> → resources · anything with a <code>Use</code> → items · anything else → resources"],
    ])}
    <p style="margin:12px 0 6px"><b>The <code>Tags</code> column says WHERE a thing may be used.</b>
    A semicolon list. A <code>Use</code> says what it does; a tag says where you are allowed to do it.</p>
    ${rows([
      ["adventure_consume","during an Adventure fight"],
      ["match_consume","on a player during the match draft"],
      ["no tag","<b>the normal case.</b> Taken at the bar before the team sets off. Not broken, just not something you pull out mid-wave"],
      ["anything else","yours. The game ignores it; test it with a Requires"],
    ])}
    <p style="margin:9px 0 0;color:var(--dim)"><b>A brew is an ordinary item.</b> It is MADE at a
    building — the Brewery's <code>Action</code> is <code>count:reed-6;count:brew_fire+1</code> — bottled,
    and carried. The bottle is what you use, and using it spends the bottle. Nothing is conjured out of
    the inventory; the inventory carries what a building made.<br>
    An item whose <code>Use</code> is <code>brew:fire</code> lays that row of Brews.csv over one player
    for the match. It is always a one-match brew, so the final whistle takes it off again.</p>`));

  board.appendChild(card("Abilities — when one goes off", `
    <p style="margin:0 0 9px">An ability is five answers: <b>Trigger</b> (when), <b>Target</b> (who),
    <b>Effect</b> (what), <b>Value</b> (how much) and <b>Scope</b> (how long). Only a new
    <b>Effect</b> needs code; everything else is a word.</p>
    <p style="margin:0 0 9px"><b>The triggers live in AbilityTriggers.csv</b>, with a
    <code>Status</code> of <code>live</code> or <code>planned</code> — so the file is both the list the
    game reads and the plan for the ones still to build. A card written against a planned trigger loads
    and waits.</p>
    ${rows([
      ["on_duel_start","either way, when its duel begins"],
      ["on_attack / on_defend","which side of the duel it is on"],
      ["on_win_duel / on_lose_duel","after the duel is decided. <b>Both have been in the engine since the beginning</b>"],
      ["flip","the two cards turn face up. Fires <i>before</i> on_duel_start, so it can change what the duel starts with"],
      ["passive","once at the start of every round. No condition at all"],
    ])}
    <p style="margin:9px 0 0;color:var(--dim)">Everything else in that file is marked
    <code>planned</code>: reveal, contemplation, rejuvenation, fused, last_player, marked, counters,
    cards_left, odd_even, copy, swap, currency, last_side.</p>`));

  board.appendChild(card("Things that will bite you", `
    ${rows([
      ["a .csv with no .csv.import","Godot turns your spreadsheet into a translation table and litters the folder. See <b>Where things go</b>"],
      ["renaming a card","a card is identified by its <b>Name</b> everywhere, including in saved games. Renaming one breaks them"],
      ["two cards on one rung","the ladder says one card per power per tier. The checker below catches it"],
      ["<code>and</code> in a Requires","use a semicolon. The checker catches this too"],
      ["a counter nothing writes","a condition that can never be true. Also caught below"],
      ["an icon that is not there","harmless — it draws as a coloured pip. The game never stops for missing art"],
    ])}`));

  wrap.appendChild(board);
}

/* ============================================================
   THE CHECKER — the same questions the game asks at startup.
   ============================================================ */
function check(){
  PROBS=[];
  const add=(file,row,col,msg,fix)=>PROBS.push({file,row,col,msg,fix});

  /* 1. duplicate keys */
  for(const f of Object.keys(DATA)){
    const k=sch(f).key; if(!k) continue;
    const i=at(f,k); if(i<0) continue;
    // SOME FILES HAVE A TWO-PART KEY. Theme.csv is keyed by Element AND
    // State — `button` appears five times on purpose, once per state — so
    // checking the first column alone reported five duplicates that were
    // the whole design. `key2` in the schema names the second half.
    const k2=sch(f).key2;
    const i2=k2?at(f,k2):-1;
    const seen={};
    // An exclamation mark is kept here on purpose: "flag:brave" and
    // "!flag:brave" are two different words, and norm() would flatten them
    // into one and then complain that you wrote the same id twice.
    const idKey = s => String(s||"").trim().toLowerCase().replace(/[^a-z0-9!]/g,"");
    DATA[f].rows.forEach((r,ri)=>{
      let v=idKey(r[i]); if(!v) return;
      if(i2>=0) v += "|" + idKey(r[i2]);
      if(seen[v]!==undefined) add(f,ri,k,`Two rows share the id "${(r[i]||'').trim()}"${i2>=0?` in state "${(r[i2]||'').trim()}"`:""}.`,`Row ${seen[v]+2} has it too. Ids must be unique inside a file.`);
      else seen[v]=ri;
    });
  }
  /* 2. references */
  for(const [f,map] of Object.entries(REFS)){
    if(!DATA[f]) continue;
    for(const [c,[rf,rc]] of Object.entries(map)){
      const i=at(f,c); if(i<0||!DATA[rf]) continue;
      const pool=ids(rf,rc);
      if(!pool.size) continue;
      DATA[f].rows.forEach((r,ri)=>{
        const v=(r[i]||"").trim(); if(!v) return;
        if(!pool.has(norm(v))) add(f,ri,c,`"${v}" is not in ${rf}.`,`Add a row there with that id, or pick one from the list.`);
      });
    }
  }
  /* 2b. ONE NAME, ONE PLAYER (round X). A card is identified by its Name -
     saves, brews and turned players all hang off it - so two cards sharing
     one is a save bug waiting to happen. And "Unit Name" is a placeholder. */
  {
    const named={};
    for(const f of Object.keys(DATA)){
      const ni=at(f,"Name"), ti=at(f,"Tier");
      if(ni<0||ti<0||at(f,"Unit Type")<0) continue;
      DATA[f].rows.forEach((r,ri)=>{
        const v=(r[ni]||"").trim(); if(!v) return;
        if(/^unit name$/i.test(v)){ add(f,ri,"Name",`"Unit Name" is a placeholder, not a name.`,`Give him a name from Names.csv. A card is identified by its Name, so a placeholder shared by many cards is many cards that save as one.`); return; }
        const k=norm(v);
        if(named[k]) add(f,ri,"Name",`"${v}" is also the name of a card in ${named[k]}.`,`Every player needs a name of his own - saves, brews and turned players are all stored against it.`);
        else named[k]=f;
      });
    }
  }
  /* 2c. ABILITY CELLS ON CARDS (round Y). A card's Attack / Defend Ability
     cell may name SEVERAL rows, separated by semicolons, from Abilities.csv
     OR CardAbilities.csv. Each one has to exist. */
  {
    const known=new Set([...ids("Abilities.csv","Ability ID"), ...ids("CardAbilities.csv","Ability ID")]);
    if(known.size) for(const f of Object.keys(DATA)){
      if(at(f,"Unit Type")<0 && f!=="Star Players.csv") continue;
      for(const c of ["Attack Ability","Defend Ability"]){
        const i=at(f,c); if(i<0) continue;
        DATA[f].rows.forEach((r,ri)=>{
          for(const one of (r[i]||"").split(";")){
            const v=one.trim(); if(!v) continue;
            if(!known.has(norm(v))) add(f,ri,c,`"${v}" is not a row of Abilities.csv or CardAbilities.csv.`,`Write the row, or re-run <code>python3 tools/ability_rows.py</code> if it is one of the C_ rows made from the card text.`);
          }
        });
      }
    }
  }
  /* 3. `and` where a semicolon belongs */
  const CONDS=["Requires","Effects","Action","Do","Reward","On Win","On Loss","Use","Rewards","Rewards On Win"];
  for(const f of Object.keys(DATA)) for(const c of CONDS){
    const i=at(f,c); if(i<0) continue;
    DATA[f].rows.forEach((r,ri)=>{
      const v=r[i]||"";
      if(/\s+and\s+/i.test(v)) add(f,ri,c,`"and" is not a word this understands.`,`Terms are joined with a semicolon: <code>unlocked:Brewery;count:coins>=50</code>`);
    });
  }
  /* 4. counters read but never written */
  const written=new Set(), read=new Map();
  col("Stats.csv","Counter").forEach(v=>v&&written.add(norm(v)));
  col("Items.csv","ID").forEach(v=>v&&written.add(norm(v)));
  ["seasonwins","seasondraws","seasonlosses","seasongoalsfor","seasongoalsagainst",
   "seasonpoints","seasonmatch","seasonnumber","talentpoints","matcheswon","matchesplayed",
   "friendlywins"].forEach(v=>written.add(v));
  for(const f of Object.keys(DATA)) for(const c of CONDS){
    const i=at(f,c); if(i<0) continue;
    DATA[f].rows.forEach((r,ri)=>{
      const v=r[i]||"";
      for(const m of v.matchAll(/count:\s*([A-Za-z0-9_ ]+?)\s*[+\-=]/g)) written.add(norm(m[1]));
      if(/^requires$/i.test(c)) for(const m of v.matchAll(/count:\s*([A-Za-z0-9_ ]+?)\s*[><=!]/g))
        if(!read.has(norm(m[1]))) read.set(norm(m[1]),{f,ri,c,raw:m[1].trim()});
    });
  }
  for(const [k,w] of read) if(!written.has(k)&&!k.startsWith("cleared")&&!k.startsWith("tune"))
    add(w.f,w.ri,w.c,`Nothing ever adds to "${w.raw}".`,`This condition can never be true. Add a Stats.csv row that counts it, or an Action/Effects that gives it.`);
  /* 5. unlocks required but never granted */
  const grant=new Set(), want=new Map();
  col("Talents.csv","ID").forEach(v=>v&&grant.add(norm(v)));
  /* ACHIEVEMENTS ARE THE ROOT: everything is unlocked there first, and its
     Unlocks column is a bare list of names rather than "unlock:x" terms. It
     grants more than every other file in the project put together, so
     without this line the workbench reports every room in the base as
     unreachable. Semicolons for more than one. */
  col("Achievements.csv","Unlocks").forEach(v=>{
    (v||"").split(";").forEach(one=>{ const t=one.trim(); if(t) grant.add(norm(t)); });
  });
  /* A Brewery section is opened by an achievement and nothing else, so its
     own Needs column is a want, not a grant - it is picked up below with
     every other "unlocked:" in the project. */

  /* ============ WHAT THE CLASS TREE HANDS OUT ============
     The Star Hall is the one granter in the game that is NOT a spreadsheet
     cell: putting a Star into a node unlocks "<Class> <Set Name>", choosing
     an emblem unlocks "<Class> <Emblem> Emblem", and forging the Team Spirit
     unlocks "Team Spirit <Class>" - which is exactly what the Brews.csv row
     asks for. Without these three lines the workbench reports every one of
     them as unreachable, which is a tool crying wolf. */
  for(const f of Object.keys(DATA)){
    const ut=at(f,"Unit Type"), sn=at(f,"Set Name");
    if(ut>=0 && sn>=0) DATA[f].rows.forEach(r=>{
      const a=(r[ut]||"").trim(), b=(r[sn]||"").trim();
      if(a&&b) grant.add(norm(a+" "+b));
    });
    /* "<Class> Emblems.csv": Name is the emblem. */
    const nm=at(f,"Name"), bs=at(f,"Basic Side");
    if(ut>=0 && nm>=0 && bs>=0) DATA[f].rows.forEach(r=>{
      const a=(r[ut]||"").trim(), b=(r[nm]||"").trim();
      if(a&&b){ grant.add(norm(a+" "+b+" Emblem")); grant.add(norm(a+" "+b+" Ultimate")); }
    });
  }
  /* The Traveling Brewer's cart hands things out too: a Sells column of
     unlock:X grants X, exactly as a talent's Effects would. */
  {
    const i=at("Shop.csv","Sells");
    if(i>=0) (DATA["Shop.csv"]||{rows:[]}).rows.forEach(r=>{
      for(const m of (r[i]||"").matchAll(/unlock:\s*([^;]+)/g)) grant.add(norm(m[1]));
    });
  }
  col("ClassTree.csv","Class").forEach(v=>{
    const c=(v||"").trim();
    if(c && c!=="*") grant.add(norm("Team Spirit "+c));
  });
  for(const f of Object.keys(DATA)) for(const c of CONDS){
    const i=at(f,c); if(i<0) continue;
    DATA[f].rows.forEach((r,ri)=>{
      for(const m of (r[i]||"").matchAll(/unlock:\s*([^;]+)/g)) grant.add(norm(m[1]));
    });
  }
  for(const f of Object.keys(DATA)) for(const c of ["Requires","Needs"]){
    const i=at(f,c); if(i<0) continue;
    DATA[f].rows.forEach((r,ri)=>{
      for(const m of (r[i]||"").matchAll(/unlocked:\s*([^;]+)/g))
        if(!want.has(norm(m[1]))) want.set(norm(m[1]),{f,ri,c,raw:m[1].trim()});
    });
  }
  for(const [k,w] of want) if(!grant.has(k))
    add(w.f,w.ri,w.c||"Requires",`Nothing ever unlocks "${w.raw}".`,`Give it to somebody: <code>unlock:${w.raw}</code> in a Season reward, a Bounty reward, a Building action or a Progression row.`);
  /* 5b. a talent pointing at a Tuning row that does not exist */
  if(DATA["Tuning.csv"]){
    const keys=ids("Tuning.csv","Key");
    for(const f of Object.keys(DATA)) for(const c of CONDS){
      const i=at(f,c); if(i<0) continue;
      DATA[f].rows.forEach((r,ri)=>{
        for(const m of (r[i]||"").matchAll(/count:\s*tune_([A-Za-z0-9_]+)/g))
          if(!keys.has(norm(m[1])))
            add(f,ri,c,`There is no Tuning row called "${m[1]}".`,`count:tune_ has to name a real Key in Tuning.csv, or the talent changes nothing at all.`);
      });
    }
  }
  /* 5c. more icons free from the start than there are slots to carry them.
     A run carries adventure_trait_slots icons and no more. Every icon with a
     blank Requires is available from the very first run, so if there are more
     of those than there are slots, some of them can never be chosen — and
     nothing anywhere says which, because it depends on the order they load. */
  if(DATA["AdventureTraits.csv"]){
    let slots=8;
    if(DATA["Tuning.csv"]){
      const k=at("Tuning.csv","Key"), v=at("Tuning.csv","Value");
      if(k>=0&&v>=0) for(const r of DATA["Tuning.csv"].rows)
        if(norm(r[k])==="adventuretraitslots"){ const n=parseInt(r[v]); if(!isNaN(n)) slots=n; }
    }
    const req=at("AdventureTraits.csv","Requires");
    const free=[];
    DATA["AdventureTraits.csv"].rows.forEach((r,ri)=>{
      if(req<0||!(r[req]||"").trim()) free.push(ri);
    });
    if(free.length>slots) add("AdventureTraits.csv",free[slots],"Requires",
      `${free.length} icons are free from the first run, but only ${slots} are carried.`,
      `adventure_trait_slots is ${slots}. Either raise it, or put a <code>Requires</code> on the extra icons — <code>unlocked:Something</code> — so the player earns them instead of having ${free.length-slots} of them silently do nothing.`);
  }
  /* 5d. an item filed under Items that cannot be used.
     The Items tab is the only clickable one. A row that lands there with a
     blank Use is a tile the player can point at, can click, and which does
     nothing — which reads as a broken game rather than as a material. */
  if(DATA["Items.csv"]){
    const tabAt=at("Items.csv","Tab"), kindAt=at("Items.csv","Kind"), useAt=at("Items.csv","Use");
    if(useAt>=0) DATA["Items.csv"].rows.forEach((r,ri)=>{
      const said=(tabAt>=0?(r[tabAt]||""):"").trim().toLowerCase();
      const kind=(kindAt>=0?(r[kindAt]||""):"").trim().toLowerCase();
      const use=(r[useAt]||"").trim();
      let tab=said;
      if(!["items","resources","keys"].includes(tab)){
        if(["key","token","quest"].includes(kind)) tab="keys";
        else if(["material","currency"].includes(kind)) tab="resources";
        else tab=use?"items":"resources";
      }
      if(tab==="items" && !use)
        add("Items.csv",ri,"Use",`"${r[0]}" is on the Items tab but has nothing to use.`,
          `The Items tab is the only clickable one, so this is a tile that does nothing when pressed. Either give it a <code>Use</code>, or move it with the <code>Tab</code> column \u2014 <code>resources</code> for something you spend, <code>keys</code> for something you hold.`);
      if(tab==="keys" && use)
        add("Items.csv",ri,"Tab",`"${r[0]}" is on the Keys tab but has a Use.`,
          `Nothing on the Keys tab is clickable, so its <code>Use</code> can never happen. Move it to <code>items</code> if it is meant to be used.`);
    });
  }
  /* 5e. items and where they may be used.
     Three ways a row can be quietly dead, and each of them looks like a bug
     in the game rather than a blank cell in a spreadsheet. */
  if(DATA["Items.csv"]){
    const useAt=at("Items.csv","Use"), tagAt=at("Items.csv","Tags");
    const brewIds = DATA["Brews.csv"] ? ids("Brews.csv","ID") : null;
    DATA["Items.csv"].rows.forEach((r,ri)=>{
      const use=(useAt>=0?(r[useAt]||""):"").trim();
      const tags=(tagAt>=0?(r[tagAt]||""):"").trim().toLowerCase();
      const tagged=/adventure_consume|match_consume/.test(tags);

      if(tagged && !use)
        add("Items.csv",ri,"Use",`"${r[0]}" is tagged as usable but has no Use.`,
          `A tag says WHERE it may be used; <code>Use</code> says WHAT it does. Without one it is a tile that can be clicked and does nothing.`);

      if(/^brew:/i.test(use)){
        const want=use.slice(5).trim();
        if(brewIds && !brewIds.has(norm(want)))
          add("Items.csv",ri,"Use",`"${r[0]}" pours a brew called "${want}", which is not in Brews.csv.`,
            `<code>Use: brew:fire</code> names a row of Brews.csv by its <b>ID</b>. Add that row, or point it at one that exists.`);
        if(!/match_consume/.test(tags))
          add("Items.csv",ri,"Tags",`"${r[0]}" pours a brew but is not tagged match_consume.`,
            `A brew is used on a player during the match draft, so it needs <code>match_consume</code> in Tags or the flask on a card will never offer it.`);
      }
    });
  }
  /* 5f. an ability whose Trigger is not a trigger.
     The list is AbilityTriggers.csv, and a `planned` one is fine — it is a
     word nobody has heard of that is the problem, because the card silently
     never fires and nothing says why. */
  if(DATA["Abilities.csv"] && DATA["AbilityTriggers.csv"]){
    const known=ids("AbilityTriggers.csv","ID");
    const tAt=at("Abilities.csv","Trigger");
    if(tAt>=0) DATA["Abilities.csv"].rows.forEach((r,ri)=>{
      const t=(r[tAt]||"").trim();
      if(!t) return;
      if(!known.has(norm(t)))
        add("Abilities.csv",ri,"Trigger",`"${t}" is not a trigger.`,
          `Triggers are the ID column of <b>AbilityTriggers.csv</b>. Add a row there \u2014 marked <code>planned</code> if it is not built yet \u2014 or pick one that exists.`);
    });
  }
  /* 6. the tier ladder */
  const rungs={};
  if(DATA["TierPowers.csv"]){
    const t=at("TierPowers.csv","Tier"), lo=at("TierPowers.csv","Min Attack"), hi=at("TierPowers.csv","Max Attack");
    if(t>=0&&lo>=0&&hi>=0) DATA["TierPowers.csv"].rows.forEach((r,ri)=>{
      const a=parseInt(r[lo]),b=parseInt(r[hi]);
      if(isNaN(a)||isNaN(b))return;
      const list=[]; for(let p=a;p<=b;p++) list.push(p);
      rungs[norm(r[t])]=list;
      if(list.length!==3) add("TierPowers.csv",ri,"Max Attack",`Tier ${r[t]} holds ${list.length} cards, not three.`,`The pitch has three slots per tier. Keep Min to Max three wide.`);
    });
  }
  for(const f of unitFiles()){
    const p=at(f,"Base Power Left"), t=at(f,"Tier"), n=at(f,"Name");
    DATA[f].rows.forEach((r,ri)=>{
      const tier=norm(r[t]), pw=parseInt(r[p]);
      if(!rungs[tier]||isNaN(pw)) return;
      if(!rungs[tier].includes(pw))
        add(f,ri,"Base Power Left",`${r[n]||"This card"} is Tier ${r[t]} with ${pw} power.`,`Tier ${r[t]} holds ${rungs[tier].join(", ")}. Change the power or the tier.`);
    });
  }
  /* 6b. two cards of the same class on the same rung */
  for(const f of unitFiles()){
    const p=at(f,"Base Power Left"), t=at(f,"Tier"), n=at(f,"Name"), u=at(f,"Unit Type");
    const seen={};
    DATA[f].rows.forEach((r,ri)=>{
      const k=norm(r[u])+"|"+norm(r[t])+"|"+String(r[p]).trim();
      if(!norm(r[t])||String(r[p]).trim()==="") return;
      if(seen[k]!==undefined)
        add(f,ri,"Base Power Left",`${r[n]||"This card"} and ${DATA[f].rows[seen[k]][n]||"another card"} are both Tier ${r[t]} at ${r[p]} power.`,
          `A tier holds ONE card of each power. One of them has to move to a different rung.`);
      else seen[k]=ri;
    });
  }
  /* 7. enemy layers */
  if(DATA["AdventureEnemies.csv"]){
    const L=at("AdventureEnemies.csv","Layers"), A=at("AdventureEnemies.csv","Attack"), N=at("AdventureEnemies.csv","Name");
    DATA["AdventureEnemies.csv"].rows.forEach((r,ri)=>{
      if(A>=0&&!(parseInt(r[A])>0)) add("AdventureEnemies.csv",ri,"Attack",`${r[N]||"This enemy"} has no Attack.`,`It could never hurt anybody. Give it at least 1.`);
      if(L<0) return;
      (r[L]||"").split("|").forEach(pc=>{
        const b=pc.trim().split(":"); if(b.length<3) return;
        const soak=parseInt(b[2]);
        if(soak>=5) add("AdventureEnemies.csv",ri,"Layers",`The "${b[0]}" layer soaks ${soak}.`,`The biggest power gap possible is 5, so almost nothing would get through. 0 to 3 is the useful range.`);
      });
    });
  }
  /* 8. brew costs name real items */
  if(DATA["Brews.csv"]&&DATA["Items.csv"]){
    const C=at("Brews.csv","Cost"), pool=ids("Items.csv","ID");
    if(C>=0) DATA["Brews.csv"].rows.forEach((r,ri)=>{
      (r[C]||"").split("|").forEach(pc=>{
        const nm=pc.split(":")[0].trim(); if(!nm) return;
        if(!pool.has(norm(nm))) add("Brews.csv",ri,"Cost",`"${nm}" is not in Items.csv.`,`A cost has to name a real item.`);
      });
    });
  }

  /* ---------- 9. THE ADVENTURE PILE ---------- */
  if(DATA["AdventureCombos.csv"]){
    const F="AdventureCombos.csv";
    const E=at(F,"Effect"), T=at(F,"Target"), V=at(F,"Value"), A=at(F,"At"),
          L=at(F,"Lasts"), TR=at(F,"Trait"), NM=at(F,"Name");
    const spawns=ids("AdventureSpawns.csv","ID");
    DATA[F].rows.forEach((r,ri)=>{
      const eff=norm(r[E]), tgt=(r[T]||"").trim(), nm=(r[NM]||"a row");
      if(eff && !EFFECTS.includes(eff))
        add(F,ri,"Effect",`"${(r[E]||"").trim()}" is not an effect the game knows.`,
          `It must be one of: ${EFFECTS.join(", ")}. A row it cannot read is skipped, so this breakpoint would do nothing.`);
      if(A>=0 && !(parseInt(r[A])>0))
        add(F,ri,"At",`${nm} has no At.`,`At is how many of that icon it takes. 2 means two on the pile.`);
      if(eff==="spawn"){
        if(!tgt) add(F,ri,"Target",`${nm} spawns something, but does not say what.`,`Target names a row of AdventureSpawns.csv.`);
        else if(spawns.size && !spawns.has(norm(tgt)))
          add(F,ri,"Target",`"${tgt}" is not in AdventureSpawns.csv.`,`Add a row there, or point at one that exists.`);
      }
      if(eff==="strike" && tgt && !["all","focus"].includes(norm(tgt)))
        add(F,ri,"Target",`A strike goes at "all" or "focus", not "${tgt}".`,`Blank counts as all.`);
      if((eff==="heal"||eff==="stamina") && tgt && !["all","lowest","last"].includes(norm(tgt)))
        add(F,ri,"Target",`A heal goes to "lowest", "all" or "last", not "${tgt}".`,`Blank counts as lowest.`);
      if(eff==="revive" && tgt && isNaN(parseInt(tgt)))
        add(F,ri,"Target",`For a revive, Target is HOW MUCH STAMINA they get up with.`,`Put a number there, or leave it blank to use adventure_revive_stamina from Tuning.csv.`);
      if(V>=0 && eff && !(parseInt(r[V])>0))
        add(F,ri,"Value",`${nm} is worth nothing.`,`Value is the number the effect uses — the damage, the stamina, how many to bring on.`);
      /* held/once sanity */
      const lasts=norm(r[L]);
      if(lasts==="held" && ["revive","spawn","strike","heal","stamina"].includes(eff))
        add(F,ri,"Lasts",`A ${eff} marked "held" would try to happen continuously.`,
          `These are one-off things. Use <code>once</code>, or leave Lasts blank and the game picks it for you.`);
      if(lasts==="once" && ["attack","shield"].includes(eff))
        add(F,ri,"Lasts",`An ${eff} marked "once" does nothing at all.`,
          `It is a standing bonus — it applies while you hold the icons. Use <code>held</code>, or leave Lasts blank.`);
    });
    /* two breakpoints at the same At on one trait */
    const seen={};
    DATA[F].rows.forEach((r,ri)=>{
      const k=norm(r[TR])+"|"+String(r[A]).trim();
      if(!norm(r[TR])) return;
      if(seen[k]!==undefined) add(F,ri,"At",`Two breakpoints on ${(r[TR]||"").trim()} both fire at ${r[A]}.`,
        `Only the higher one would ever be the "best" — give them different numbers.`);
      else seen[k]=ri;
    });
  }
  if(DATA["AdventureTraits.csv"]){
    const F="AdventureTraits.csv";
    const ID=at(F,"ID"), FR=at(F,"From"), VA=at(F,"Value"), NM=at(F,"Name"), MX=at(F,"Max");
    /* every element and class the cards actually have */
    const elements=new Set(), classes=new Set();
    unitFiles().forEach(f=>{
      col(f,"Element").forEach(v=>v&&elements.add(norm(v)));
      col(f,"Unit Type").forEach(v=>v&&classes.add(norm(v)));
    });
    col("Brews.csv","Element").forEach(v=>v&&elements.add(norm(v)));
    col("Brews.csv","Becomes").forEach(v=>v&&classes.add(norm(v)));
    col("AdventureEnemies.csv","Element").forEach(v=>v&&elements.add(norm(v)));
    col("AdventureEnemies.csv","Pool").forEach(v=>v&&classes.add(norm(v)));
    col("AdventureSpawns.csv","Element").forEach(v=>v&&elements.add(norm(v)));
    col("AdventureSpawns.csv","Class").forEach(v=>v&&classes.add(norm(v)));

    const used=new Set(col("AdventureCombos.csv","Trait").map(norm));
    DATA[F].rows.forEach((r,ri)=>{
      const from=norm(r[FR]), val=norm(r[VA]), nm=(r[NM]||r[ID]||"this icon");
      if(from!=="star" && !val)
        add(F,ri,"Value",`${nm} has no Value.`,`Value is which Element or Unit Type counts as this icon. Only a "star" row may leave it blank.`);
      if(from==="element" && val && elements.size && !elements.has(val))
        add(F,ri,"Value",`No card, brew, enemy or spawn has the element "${(r[VA]||"").trim()}".`,
          `Nothing would ever put this icon on the pile. Check the spelling, or give a card that Element.`);
      if(from==="class" && val && classes.size && !classes.has(val))
        add(F,ri,"Value",`No card, brew, enemy or spawn has the class "${(r[VA]||"").trim()}".`,
          `Nothing would ever put this icon on the pile. Check the spelling against ClassInfo.csv and AdventureEnemies' Pool column.`);
      if(!used.has(norm(r[ID])) && DATA["AdventureCombos.csv"])
        add(F,ri,"ID",`Nothing happens when you collect ${nm}.`,
          `The bar will show it filling up and it will never do anything. Add a row to AdventureCombos.csv with Trait = ${(r[ID]||"").trim()}.`);
      if(MX>=0 && !(parseInt(r[MX])>0))
        add(F,ri,"Max",`${nm} has no Max.`,`Max is how far the bar counts. Usually your biggest breakpoint.`);
    });
  }
  if(DATA["AdventureSpawns.csv"]){
    const F="AdventureSpawns.csv";
    const P=at(F,"Power"), T=at(F,"Tier"), N=at(F,"Name");
    DATA[F].rows.forEach((r,ri)=>{
      const tier=norm(r[T]), pw=parseInt(r[P]);
      if(tier && rungs[tier] && !isNaN(pw) && !rungs[tier].includes(pw))
        add(F,ri,"Power",`${r[N]||"This stand-in"} is Tier ${r[T]} with ${pw} power.`,
          `The game will clamp it into ${rungs[tier].join(", ")} when it walks on, so it will not arrive as the number you wrote here.`);
    });
  }
  /* 10. Juice */
  if(DATA["Juice.csv"]){
    const F="Juice.csv";
    const W=at(F,"When"), WHO=at(F,"Who"), SD=at(F,"Sound"), SL=at(F,"Slowmo"), ID=at(F,"ID");
    const cues=ids("Audio.csv","ID");
    const dips={};
    DATA[F].rows.forEach((r,ri)=>{
      const when=norm(r[W]);
      if(when && !MOMENTS.map(norm).includes(when))
        add(F,ri,"When",`"${(r[W]||"").trim()}" is not a moment the game ever announces.`,
          `It must be one of: ${MOMENTS.join(", ")}. A row nobody fires does nothing.`);
      const who=norm(r[WHO]);
      if(who && !["player","enemy","screen","ball"].includes(who))
        add(F,ri,"Who",`"${(r[WHO]||"").trim()}" is not something the game can shake.`,`player, enemy, screen or ball.`);
      const snd=(r[SD]||"").trim();
      if(snd && cues.size && !cues.has(norm(snd)))
        add(F,ri,"Sound",`"${snd}" is not a row of Audio.csv.`,
          `It will be looked for as a FILE in assets/audio/ instead, which works — but a row gives it volume, a bus and the Sound slider.`);
      const dip=parseFloat(r[SL]);
      if(dip>0.4) add(F,ri,"Slowmo",`${dip} seconds is a long dip.`,
        `Slow-motion reads best under about a third of a second. Longer and it stops being a punch and starts being a wait.`);
      if(dip>0 && when){ dips[when]=(dips[when]||0)+1; }
    });
    for(const [w,n] of Object.entries(dips)) if(n>1){
      DATA[F].rows.forEach((r,ri)=>{
        if(norm(r[W])===w && parseFloat(r[SL])>0 && !PROBS.some(p=>p.file===F&&p.row===ri&&p.col==="Slowmo"))
          add(F,ri,"Slowmo",`${n} rows of "${(r[W]||"").trim()}" ask for slow-motion.`,
            `Harmless — the game takes the LONGEST and makes one dip out of it. But only one of them is doing anything, so you may as well zero the others.`);
      });
    }
  }
  /* 11. Seasons shelf */
  if(DATA["Seasons.csv"]){
    const F="Seasons.csv", R=at(F,"Row"), C=at(F,"Column"), N=at(F,"Name");
    const seen={};
    DATA[F].rows.forEach((r,ri)=>{
      const k=String(r[R]).trim()+"|"+String(r[C]).trim();
      if(!String(r[R]).trim()) return;
      if(seen[k]!==undefined) add(F,ri,"Column",`${r[N]||"This season"} sits on top of ${DATA[F].rows[seen[k]][N]||"another one"}.`,
        `Two tiles at Row ${r[R]}, Column ${r[C]} are drawn in the same place. Move one.`);
      else seen[k]=ri;
    });
  }
  /* 12. soft notes — things that are legal but usually not what you meant */
  {
    /* a class that has Stars, and so will appear on the class-select screen,
       but no ClassInfo row to describe it. Perfectly legal; it just turns up
       with no blurb and no banner. */
    const described=ids("ClassInfo.csv","Class");
    if(described.size){
      const starred=new Set(), where={};
      unitFiles().forEach(f=>{
        const u=at(f,"Unit Type"), pt=at(f,"Player Type");
        DATA[f].rows.forEach((r,ri)=>{
          if(pt>=0 && norm(r[pt])!=="star") return;
          const k=norm(r[u]); if(!k) return;
          if(!starred.has(k)){ starred.add(k); where[k]={f,ri,raw:(r[u]||"").trim()}; }
        });
      });
      for(const k of starred) if(!described.has(k)){
        const w=where[k];
        add(w.f,w.ri,"Unit Type",`"${w.raw}" has Star players but no row in ClassInfo.csv.`,
          `It will still be offered on the class-select screen — it just turns up with no description and no banner. Add a row to ClassInfo.csv to give it both.`);
      }
    }
    /* Music and Background columns naming something Audio/asset-wise unknown
       is not an error: the game looks for a FILE of that name. Say so once
       rather than flagging every row. */
    const cues=ids("Audio.csv","ID");
    const M=at("Biomes.csv","Music");
    if(M>=0 && cues.size) DATA["Biomes.csv"].rows.forEach((r,ri)=>{
      const v=(r[M]||"").trim(); if(!v) return;
      if(!cues.has(norm(v)))
        add("Biomes.csv",ri,"Music",`"${v}" has no row in Audio.csv.`,
          `The game will look for a file called that in assets/music/ instead, which works. A row would give it a volume, a fade and the Music slider.`);
    });
  }
  paintProbs();
}
