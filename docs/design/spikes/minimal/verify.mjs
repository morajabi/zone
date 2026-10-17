import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const metadata=JSON.parse(fs.readFileSync(path.join(root,'metadata.json'),'utf8'));
let assertions=0;
for(const item of metadata){
 const html=fs.readFileSync(path.join(root,item.file),'utf8');
 const source=html.match(/<script>([\s\S]*)<\/script>/)[1];
 const elements=new Map();
 class Element{
  innerHTML='';textContent='';style={};open=false;dataset={};
  querySelector(s){return get(s)}querySelectorAll(){return []}
  showModal(){this.open=true}close(){this.open=false}append(){}remove(){}
  setAttribute(){}
 }
 const get=s=>{if(!elements.has(s))elements.set(s,new Element());return elements.get(s)};
 const listeners={};
 const ctx=vm.createContext({document:{querySelector:get,querySelectorAll:()=>[],addEventListener:(k,v)=>listeners[k]=v,createElement:()=>new Element()},setInterval:()=>{},setTimeout:()=>{},Date,FormData:class{constructor(value){this.value=value}get(key){return this.value[key]}}});
 vm.runInContext(source,ctx,{filename:item.file});
 const check=(s,label)=>{if(!vm.runInContext(s,ctx))throw Error(`${item.id}: ${label}`);assertions++};
 check('document.querySelector("#app").innerHTML.includes("Start Focus")','idle start rendered');
 vm.runInContext('begin()',ctx);
 check('session !== null && session.left===1 && session.mode==="flexible"','start creates flexible session');
 const click=action=>listeners.click({target:{closest:s=>s==='[data-action]'?{dataset:{action}}:null}});
 click('pause');check('session.pausedUntil>Date.now() && session.left===0','pause consumes allowance');
 click('pause');check('session.pausedUntil===null && session.left===0','resume preserves used allowance');
 click('end');check('document.querySelector("#dialog").open','end requires confirmation');
 get('form').onsubmit({preventDefault(){},target:{}});check('session===null','end returns idle');
 vm.runInContext('mode="locked"; begin()',ctx);check('session===null && document.querySelector("#dialog").open','locked start confirms');
 get('form').onsubmit({preventDefault(){},target:{}});check('session.mode==="locked" && !document.querySelector("#app").innerHTML.includes("End Session")','locked session hides early end');
 vm.runInContext('session.ends=Date.now()-1; tick()',ctx);check('session===null','expiry releases session');
 vm.runInContext('editRules()',ctx);
 get('form').onsubmit({preventDefault(){},target:{mode:'flexible',allowance:'3',pauseMinutes:'7'}});
 check('mode==="flexible" && allowance===3 && pauseMinutes===7','rules persist');
 vm.runInContext('editList(-1)',ctx);get('form').onsubmit({preventDefault(){},target:{name:'Reading',sites:'example.org\nexample.com',apps:'News'}});
 check('lists.at(-1).name==="Reading" && lists.at(-1).sites.length===2','create list');
 vm.runInContext('editSchedule(-1)',ctx);get('form').onsubmit({preventDefault(){},target:{name:'Saturday',kind:'once',time:'14:00',duration:'45',list:'2'}});
 check('schedules.at(-1).name==="Saturday" && schedules.at(-1).kind==="once"','create one-off schedule');
 vm.runInContext('page="lists";render()',ctx);check('document.querySelector("#app").innerHTML.includes("Reading")','list navigation renders saved list');
 vm.runInContext('page="schedules";render()',ctx);check('document.querySelector("#app").innerHTML.includes("Saturday")','schedule navigation renders saved schedule');
 console.log(`${item.id}: ${item.title} — passed`);
}
console.log(`${assertions} interaction assertions passed across ${metadata.length} spikes.`);
