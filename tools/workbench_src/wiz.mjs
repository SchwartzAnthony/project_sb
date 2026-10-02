import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
// RUN FROM ANYWHERE: the page and the data folder are found from this file's
// own place in the project. Override with WB_HTML / WB_DATA if you must.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const p = await b.newPage({ viewport: { width: 1500, height: 1300 } });
const errs = [];
p.on('pageerror', e => errs.push('PAGEERROR: ' + e.message));
await p.goto('file://' + (process.env.WB_HTML || path.join(PROJECT, 'sturmball_workbench.html')), { waitUntil: 'domcontentloaded' });
await p.waitForFunction(() => typeof window.ingest === 'function', null, { timeout: 20000 });
await p.waitForTimeout(400);
const dir = process.env.WB_DATA || path.join(PROJECT, 'data'); const payload={};
for (const f of fs.readdirSync(dir)) if (f.toLowerCase().endsWith('.csv')) payload[f]=fs.readFileSync(dir+'/'+f,'utf8');
const rep = await p.evaluate((files)=>{ for(const [n,t] of Object.entries(files)) ingest(n,t);
  SAMPLE=false; CUR=Object.keys(DATA)[0]; save(); paintRail(); paintTable(); check();
  document.getElementById('probs').style.display='none';
  return {files:Object.keys(DATA).length, probs:PROBS.map(x=>`${x.file} ${x.row+2} [${x.col}] ${x.msg}`)}; }, payload);
console.log('loaded', rep.files, 'files |', rep.probs.length, 'problems');
rep.probs.forEach(s=>console.log('  ',s));

// ---- open the wizard and walk it ----
await p.click('#bNewClass'); await p.waitForTimeout(300);
await p.screenshot({ path: 'wiz_1.png' });
await p.fill('#wCls','Steinwacht'); await p.fill('#wDisp','Steinwacht');
await p.selectOption('#wEl','EARTH'); await p.selectOption('#wTier','III');
await p.fill('#wDesc','Stone wardens. They bury and dig up.');
await p.click('#wNext'); await p.waitForTimeout(300);

const DEMONS=[['Bathin','Cairn','3'],['Furfur','Stone Mark','4'],['Haagenti','Slate','4']];
for (let i=0;i<3;i++){
  const [name,tok,need]=DEMONS[i];
  await p.fill('#sName',name);
  await p.fill('#sTok',tok);
  await p.dispatchEvent('#sTok','change');   // the token is what the nine are rolled around
  await p.waitForTimeout(250);
  await p.fill('#sBasic',`When an earth unit wins, gain a ${tok}.`);
  await p.fill('#sCond',`If four ${tok}s were made by Steinwacht units: Transform this Emblem.`);
  await p.fill('#sCount','steinwacht_'+name.toLowerCase());
  await p.fill('#sNeed',need);
  await p.fill('#sUlt',`Your Basic side is still active. Every ${tok} is worth double.`);
  await p.fill('#sFront',`If you control a ${tok}: Deal +2 damage during combat`);
  await p.selectOption('#sPow', String(2+i));
  if(i===0){ await p.waitForTimeout(200); await p.screenshot({ path:'wiz_2.png' }); }
  await p.click('#wNext'); await p.waitForTimeout(350);
  const say = await p.$eval('#wSay', e=>e.textContent);
  if(say) { console.log('BLOCKED at emblem', i+1, ':', say); break; }
}
await p.screenshot({ path:'wiz_3.png' });
const before = await p.evaluate(()=>Object.keys(DATA).length);
await p.click('#wDone'); await p.waitForTimeout(500);
const after = await p.evaluate(()=>({
  files: Object.keys(DATA).length,
  cls: DATA['ClassInfo.csv'].rows.length,
  stars: DATA['Star Players.csv'].rows.length,
  emb: DATA['Steinwacht Emblems.csv'] ? DATA['Steinwacht Emblems.csv'].rows.length : 0,
  units: DATA['Unit_Set_Steinwacht.csv'] ? DATA['Unit_Set_Steinwacht.csv'].rows.length : 0,
  sample: DATA['Unit_Set_Steinwacht.csv'] ? DATA['Unit_Set_Steinwacht.csv'].rows.slice(0,4).map(r=>r.join(' | ')) : [],
  probs: PROBS.length,
}));
console.log('files before/after:', before, '->', after.files);
console.log('ClassInfo rows', after.cls, '| Stars', after.stars, '| Emblems', after.emb, '| Units', after.units);
console.log('problems after:', after.probs);
after.sample.forEach(s=>console.log('   ', s));
await p.screenshot({ path:'wiz_4.png' });
console.log(errs.length ? errs.join('\n') : 'NO JS ERRORS');
await b.close();
