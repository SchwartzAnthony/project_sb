
function paintProbs(){
  const tag=$("#probtag"), list=$("#problist");
  if(!PROBS.length){ tag.className="tag ok"; tag.textContent="all clear"; }
  else { tag.className="tag err"; tag.textContent=PROBS.length+(PROBS.length===1?" problem":" problems"); }
  list.innerHTML="";
  list.hidden=!OPEN; $("#probchev").textContent=OPEN?"▾":"▸";
  if(!OPEN) return;
  if(SAMPLE && PROBS.length){
    const s=document.createElement("div"); s.className="prob";
    s.innerHTML='<span class="tag ok">sample</span><div><span>Most of these are the example set\'s own fault.</span>'+
      '<span class="fix">It is only the first four rows of each of your real files, so plenty of ids point at rows that were trimmed off. '+
      'Press <b>Load CSVs</b> and choose everything in your <b>data</b> folder — then this list is about your game.</span></div>';
    list.appendChild(s);
  }
  if(!PROBS.length){
    const d=document.createElement("div"); d.className="prob";
    d.innerHTML='<span style="color:var(--dim)">Every id is unique, every reference resolves, every counter that is read is written somewhere, '+
      'every card sits on its proper rung, every trait has something that fires it, and every breakpoint does something the game knows how to do.</span>';
    list.appendChild(d); return;
  }
  PROBS.slice(0,160).forEach(p=>{
    const d=document.createElement("div"); d.className="prob";
    const b=document.createElement("b"); b.textContent=`${p.file.replace(/\.csv$/,"")} ${p.row+2}`;
    const body=document.createElement("div");
    body.innerHTML=`<span></span><span class="fix">${p.fix||""}</span>`;
    body.children[0].textContent=p.msg;
    const j=document.createElement("button"); j.className="jump"; j.textContent="show";
    j.onclick=()=>{
      CUR=p.file; paintRail(); paintTable();
      const el=document.getElementById(`c_${norm(p.file)}_${p.row}_${DATA[p.file].headers.indexOf(p.col)}`);
      if(el){ el.scrollIntoView({block:"center",behavior:"smooth"}); el.focus(); }
    };
    d.appendChild(b); d.appendChild(body); d.appendChild(j);
    list.appendChild(d);
  });
  if(PROBS.length>160){
    const d=document.createElement("div"); d.className="prob";
    d.innerHTML=`<span style="color:var(--dim)">…and ${PROBS.length-160} more. Fix a few and press Check again.</span>`;
    list.appendChild(d);
  }
}

/* ---------- loading ---------- */
function ingest(name, text){
  const rows=parseCSV(text);
  if(rows.length<2) return false;
  const headers=rows[0].map(h=>h.trim());
  const body=rows.slice(1).map(r=>{const o=[];for(let i=0;i<headers.length;i++)o.push(r[i]??"");return o;});
  DATA[name]={headers,rows:body};
  return true;
}
function loadFiles(list){
  let n=0, left=list.length;
  if(!left) return;
  [...list].forEach(f=>{
    if(!/\.csv$/i.test(f.name)){ if(--left===0) done(); return; }
    const rd=new FileReader();
    rd.onload=()=>{ if(ingest(f.name, rd.result)) n++; if(--left===0) done(); };
    rd.onerror=()=>{ if(--left===0) done(); };
    rd.readAsText(f);
  });
  function done(){
    if(n){ SAMPLE=false; CUR=(CUR&&(DATA[CUR]||VIEWS[CUR]))?CUR:Object.keys(DATA)[0]; save(); paintRail(); paintTable(); check(); }
    closeVeil();
    if(!n) alert("Nothing loaded — pick .csv files.");
  }
}

/* ---------- panels ---------- */
function veil(inner){
  const v=document.createElement("div"); v.id="veil";
  v.innerHTML=`<div class="panel">${inner}</div>`;
  v.onclick=e=>{ if(e.target===v) closeVeil(); };
  document.body.appendChild(v);
  return v;
}
function closeVeil(){ const v=$("#veil"); if(v) v.remove(); }

/* A plain readable panel with a Copy button. The Keywords page uses it for
   "everything still to build"; anything else that wants to hand you a block
   of text you can paste into a message may use it too. */
function showText(title, text){
  const safe = String(text||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  const v=veil(`<header><h3>${title}</h3></header>
    <div class="in"><textarea class="csv" id="txtout" spellcheck="false">${safe}</textarea>
    <p class="note"><b>Copy</b> puts this on your clipboard. Paste it straight into a message and it is a finished request &mdash; every word in it came out of your own CSVs.</p></div>
    <footer><button class="btn key" id="bTxtCopy">Copy</button>
      <span id="txtsaid" style="color:var(--pitch);font-size:13px"></span>
      <div class="grow"></div><button class="btn" id="bTxtClose">Close</button></footer>`);
  const out=v.querySelector("#txtout");
  v.querySelector("#bTxtClose").onclick=closeVeil;
  v.querySelector("#bTxtCopy").onclick=async()=>{
    try{ await navigator.clipboard.writeText(out.value); }
    catch(e){ out.select(); document.execCommand("copy"); }
    v.querySelector("#txtsaid").textContent="Copied.";
    setTimeout(()=>{const s=v.querySelector("#txtsaid"); if(s) s.textContent="";},2600);
  };
}

function showLoad(){
  const v=veil(`<header><h3>Load your CSVs</h3></header>
    <div class="in">
      <div class="drop" id="drop"><b>Drop .csv files here</b><br>or use the button below. Pick them all at once — the workbench needs to see them together to check that they line up.</div>
      <p class="note">Your project's files live in <span class="kbd">project_sb/data/</span>. Take the tutorial folder too if you want it checked. Nothing is uploaded anywhere; this all happens in your browser, and your work is kept between visits.</p>
    </div>
    <footer><button class="btn key" id="bPickGo">Choose files</button>
      <button class="btn" id="bSeed">Start from the example set</button>
      <div class="grow"></div><button class="btn" id="bClose">Close</button></footer>`);
  v.querySelector("#bPickGo").onclick=()=>$("#pick").click();
  v.querySelector("#bClose").onclick=closeVeil;
  v.querySelector("#bSeed").onclick=()=>{
    if(!confirm("Replace everything currently loaded with the example set?")) return;
    DATA=JSON.parse(JSON.stringify(unseed())); CUR=Object.keys(DATA)[0]; SAMPLE=true;
    save(); paintRail(); paintTable(); check(); closeVeil();
  };
  const d=v.querySelector("#drop");
  ["dragenter","dragover"].forEach(e=>d.addEventListener(e,ev=>{ev.preventDefault();d.classList.add("hot");}));
  ["dragleave","drop"].forEach(e=>d.addEventListener(e,ev=>{ev.preventDefault();d.classList.remove("hot");}));
  d.addEventListener("drop",ev=>loadFiles(ev.dataTransfer.files));
}

function showExport(only){
  const names = only?[only]:Object.keys(DATA).sort();
  const v=veil(`<header><h3>${only?only:"Export everything"}</h3></header>
    <div class="in">
      <select id="which" style="width:100%;padding:8px;background:var(--paper);border:1px solid var(--line);border-radius:3px;margin-bottom:10px"></select>
      <textarea class="csv" id="out" spellcheck="false"></textarea>
      <p class="note"><b>Copy</b> puts the file on your clipboard — paste it into the real <span class="kbd">.csv</span> and save.
      <b>Download</b> writes the file directly. <b>Download all</b> gives you every file one after another, which your browser may ask about once.
      <br>A file you have just created also needs a <span class="kbd">.csv.import</span> beside it — see <b>Where things go</b>.</p>
    </div>
    <footer><button class="btn key" id="bCopy">Copy</button>
      <button class="btn" id="bDown">Download</button>
      <button class="btn" id="bAll">Download all</button>
      <span id="said" style="color:var(--pitch);font-size:13px"></span>
      <div class="grow"></div><button class="btn" id="bClose2">Close</button></footer>`);
  const sel=v.querySelector("#which"), out=v.querySelector("#out");
  names.forEach(n=>{
    const o=document.createElement("option"); o.value=n; o.textContent=n; sel.appendChild(o);
  });
  const show=()=>{ out.value=toCSV(sel.value); };
  sel.onchange=show; show();
  v.querySelector("#bClose2").onclick=closeVeil;
  v.querySelector("#bCopy").onclick=async()=>{
    try{ await navigator.clipboard.writeText(out.value); }
    catch(e){ out.select(); document.execCommand("copy"); }
    v.querySelector("#said").textContent=`${sel.value} copied.`;
    setTimeout(()=>{const s=v.querySelector("#said"); if(s) s.textContent="";},2600);
  };
  const drop=(name,text)=>{
    const blob=new Blob([text],{type:"text/csv"});
    const a=document.createElement("a");
    a.href=URL.createObjectURL(blob); a.download=name;
    document.body.appendChild(a); a.click(); a.remove();
  };
  v.querySelector("#bDown").onclick=()=>{
    drop(sel.value, out.value);
    v.querySelector("#said").textContent="If nothing happened, use Copy instead.";
  };
  v.querySelector("#bAll").onclick=()=>{
    const all=Object.keys(DATA).sort();
    all.forEach((n,i)=>setTimeout(()=>drop(n,toCSV(n)), i*180));
    v.querySelector("#said").textContent=`${all.length} files on their way.`;
  };
}

/* ---------- wiring ---------- */
$("#bLoad").onclick=showLoad;
// THE NEW CLASS WIZARD. Emblem -> Ultimate -> Star -> nine units, three
// times, then four files. See part7_wizard.js.
$("#bNewClass").onclick = wizStart;
$("#bExport").onclick=()=>showExport(null);
$("#bCheck").onclick=()=>{ OPEN=true; check(); $("#problist").scrollIntoView({behavior:"smooth"}); };
$("#probhead").onclick=()=>{ OPEN=!OPEN; paintProbs(); };
$("#pick").onchange=e=>loadFiles(e.target.files);
$("#bTheme").onclick=()=>{
  const now=document.documentElement.getAttribute("data-theme");
  const next = now==="dark" ? "light" : now==="light" ? "dark"
    : (matchMedia("(prefers-color-scheme: dark)").matches ? "light" : "dark");
  document.documentElement.setAttribute("data-theme",next);
  try{ localStorage.setItem("sturmball.theme",next); }catch(e){}
};
try{ const t=localStorage.getItem("sturmball.theme"); if(t) document.documentElement.setAttribute("data-theme",t); }catch(e){}
["dragenter","dragover","drop"].forEach(e=>document.addEventListener(e,ev=>ev.preventDefault()));
document.addEventListener("drop",ev=>{ if(ev.dataTransfer&&ev.dataTransfer.files.length) loadFiles(ev.dataTransfer.files); });
document.addEventListener("keydown",e=>{ if(e.key==="Escape") closeVeil(); });

boot();
</script>
