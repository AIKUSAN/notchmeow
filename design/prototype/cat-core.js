/**
 * cat-core.js: NotchMeow's cat contract. Everything pure about Shrimpy, Momo and the other
 * coats: presets, face warp and geometry, state/mouth/emote tables, both motion profiles,
 * personality, the greeting and file-catch timelines, and the zoomies, sleep and search rules.
 *
 * Numbers in, numbers out. No canvas, no DOM, no clock of its own and no Math.random: an engine
 * is given `now()` and `rand()`, and a test gives it a fake clock and a seeded `rng(seed)`.
 * Units are R, the head radius, unless a name says px or ms.
 *
 * One file serves both worlds. A page loads it with <script src>, which sets `CatCore`.
 * Node loads it with require(), which returns the same object. There is no build step.
 *
 * This file is the tie-breaker. If an app and a fixture in tests/fixtures/cat/ disagree,
 * the fixture was generated from here, so the app is wrong. See docs/CAT-CONTRACT.md.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.CatCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';
const api = { VERSION: 1 };

// ── Helpers ──────────────────────────────────────────────────────────────────
const TAU=Math.PI*2;
const EZ={out:t=>1-Math.pow(1-t,3),inOut:t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2,back:t=>1+2.7*Math.pow(t-1,3)+1.7*Math.pow(t-1,2),lin:t=>t,in:t=>t*t*t};
const lerp=(a,b,t)=>a+(b-a)*t,clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),seg=(t,a,b)=>clamp((t-a)/(b-a),0,1);
const hex=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
const wrapA=a=>((a+Math.PI)%TAU+TAU)%TAU-Math.PI;
/** The seeded PRNG: a 32-bit LCG. Same seed, same sequence, on every platform (uint32 wrap-around maths). */
function rng(seed){let s=seed>>>0;return()=>((s=(Math.imul(s,1103515245)+12345)>>>0)/4294967296)}
/** Maps a trait to a multiplier: lo at 0, 1 at 0.5, hi at 1. */
const tm=(v,lo,hi)=>v<.5?lerp(lo,1,v/.5):lerp(1,hi,(v-.5)/.5);
const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);

// ── State tables (colours and tints from upstream engine.ts) ─────────────────
const COL={idle:'#E6E9EE',working:'#3B9EFF',thinking:'#8B5CF6',searching:'#6366F1',approval:'#F5A524',question:'#22D3EE',error:'#F4505E',finished:'#34D399',ratelimit:'#FB923C',sleeping:'#94A3B8',dizzy:'#F472B6'};
const TINT={idle:0,working:.72,thinking:.72,searching:.72,approval:.78,question:.75,error:.78,finished:.35,ratelimit:.72,sleeping:.32,dizzy:.7};
const GLOW={working:'#3B9EFF',thinking:'#A78BFA',searching:'#6366F1',approval:'#F5A524',error:'#F4505E',finished:'#34D399',ratelimit:'#F59E0B'};
const BADGE={working:'dots',thinking:'dots',searching:'dots',approval:'bang',question:'question',error:'dot',finished:'dot',ratelimit:'dot'};
const STATES=Object.keys(COL);

// ── Mouth ────────────────────────────────────────────────────────────────────
// Rest mouth per state: open, smile (-1 frown … 1 smile), tongue, round (D … 'o'), skew, wavy.
const MOUTH={idle:[0,0,0,0,0,0],working:[0,.05,.35,0,0,0],thinking:[0,-.15,0,0,.7,0],searching:[0,0,0,0,0,0],approval:[0,.1,0,.35,0,0],question:[.13,0,0,1,0,0],error:[0,-.8,0,0,0,0],finished:[0,1,0,0,0,0],ratelimit:[.3,0,.85,.2,0,0],sleeping:[0,.1,0,1,0,0],dizzy:[0,0,.45,0,0,1]};
const MKEYS=['mouth','smile','tongue','mround','mskew','wavy'];
// Emote mouths, shared by both motion styles: [pose, duration ms].
const EMOUTH={love:[{smile:.8},1800],surprised:[{mouth:.6,mround:1},1000],proud:[{smile:.75,mskew:.45},1800],wink:[{tongue:.8,smile:.4,mskew:.3},1100],yawn:[{tongue:.35,mround:.15},1100],happy:[{mouth:.5,smile:1},1300],annoyed:[{smile:-.7,mskew:-.6},850]};
/** Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring. */
function mouthFx(st,T){switch(st){
 case 'searching':{const ph=T%2.6;return ph<1.1?Math.sin(Math.PI*ph/1.1)*(.24+.07*Math.sin(T*TAU*9)):0}
 case 'approval':{const ph=(T%1.4)/1.4;return ph<.28?.5*Math.sin(Math.PI*ph/.28):0}
 case 'ratelimit':return .07*Math.sin(T*TAU*2.8);
 case 'sleeping':return .07*Math.max(0,Math.sin(T*1.5));
 default:return 0}}
const BUSY=new Set(['working','thinking','searching']);

Object.assign(api,{TAU,EZ,lerp,clamp,seg,hex,wrapA,rng,tm,own,COL,TINT,GLOW,BADGE,STATES,MOUTH,MKEYS,EMOUTH,mouthFx,BUSY});

// ── Presets (from the approved reference board, units of R) ──────────────────
// Cat IDs are frozen contract values (they are stored in settings), in this order:
// shrimpy, momo, ginger, midnight, latte, patches, blue, snow, oreo, mocha, silver, cloud,
// leo, button, puff, noodle. `voice` is a pitch offset in semitones for sub-project C:
// Shrimpy -1, Momo +1, the extra coats 0, every kitten +3.
const PRESETS={
 momo:{name:'momo',label:'Momo',voice:1,coat:'tuxedo',rx:1.12,ry:.9,n:2.2,fluff:0,ruff:null,
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(24,24,27,.45)',light:'rgba(112,114,122,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  earSpread:.8,ear:{h:.8,bw:.56,rot:.5,tip:.09,tuft:0,cx:.62},
  top:'#3D3D41',bot:'#3D3D41',rimLight:1,white:'#F6F4F1',inner:'#B98288',nose:'#E89AA6',noseLine:'#B86F7C',noseW:.25,noseH:.15,nosePh:-.48,
  iris:['#7E8A45','#D1B85F'],lidTint:'#D9BE62',liner:'#16171A',ink:'#E4D592',mouthLine:'#9A8C88',whisk:'#F6F4F1',padDot:'rgba(150,142,138,.6)',
  whisk2:{rows:3,cols:2,x0:.17,dx:.065,y0:-.01,dy:.06,slope:.02,dot:.014,wcols:[0,1],a0:-.1,da:.2,len:1.32,dl:.1,droop:.1,w:.021,alpha:.95,brow:2},
  eye:{th:.43,ph:-.02,w:.19,h:.17,round:1},pupil0:.235,blushAt:[.5,.32],paw:'#F6F4F1',bean:'#E89AA6',hair:'#56575E',hairDark:'#2E2F33',hairLight:'#9A9BA2'},
 shrimpy:{name:'shrimpy',label:'Shrimpy',voice:-1,coat:'tabby',rx:1.16,ry:.92,n:2.2,fluff:1,
  ruff:{rx:1.3,ry:.97,dy:.2,col:['#B49C7A','#7E6750']},bib:'#F3EEE6',
  furOpts:{n:420,l0:.04,l1:.05,w:.01,dark:'rgba(60,46,36,.28)',light:'rgba(214,190,150,.32)'},
  earSpread:.8,ear:{h:.8,bw:.4,rot:.44,tip:.1,tuft:1},
  top:'#A08A70',bot:'#6E5B49',light:'#D9B68A',chinCol:'#E6D0AD',stripe:'#2E241D',inner:'#DCC39A',nose:'#C07A62',noseLine:'#5E3526',noseW:.19,noseH:.12,nosePh:-.36,
  iris:['#C9D18A','#6F8445'],liner:'#231A14',ink:'#231A14',mouthLine:'#5E3526',whisk:'#F7F3EC',padDot:'#2E241D',
  whisk2:{rows:3,cols:3,x0:.14,dx:.065,y0:-.01,dy:.065,slope:.022,dot:.017,wcols:[1,2],a0:-.14,da:.2,len:1.45,dl:.12,droop:.12,w:.022,alpha:.95,brow:3},
  eye:{th:.42,ph:-.02,w:.21,h:.16,round:0},pupil0:.08,blushAt:[.6,.22],paw:'#B89C78',bean:'#6B3B2C',hair:'#9A8064',hairDark:'#5A4634',hairLight:'#D2B791'}};

/** Shorthair template for the extra coats; each cat only overrides what differs. */
function makeCat(o){const base={voice:0,coat:'solid',rx:1.12,ry:.9,n:2.2,fluff:0,ruff:null,earSpread:.8,ear:{h:.8,bw:.5,rot:.46,tip:.09,tuft:0,cx:.7},noseW:.2,noseH:.13,nosePh:-.42,
 whisk2:{rows:3,cols:2,x0:.16,dx:.065,y0:-.01,dy:.06,slope:.02,dot:.014,wcols:[0,1],a0:-.1,da:.2,len:1.32,dl:.1,droop:.1,w:.021,alpha:.95,brow:2},
 eye:{th:.43,ph:-.02,w:.19,h:.17,round:1},pupil0:.2,blushAt:[.55,.25]};
 const r={...base,...o};r.ear={...base.ear,...(o.ear||{})};r.eye={...base.eye,...(o.eye||{})};r.whisk2={...base.whisk2,...(o.whisk2||{})};return r}
Object.assign(PRESETS,{
 ginger:makeCat({name:'ginger',label:'Ginger',desc:'orange tabby',coat:'tabby',top:'#E39B52',bot:'#C46F2E',light:'#F7DDB8',chinCol:'#FCEFDD',stripe:'#A9541C',inner:'#F2B8A8',
  nose:'#E88E80',noseLine:'#A85A4E',iris:['#E9D27A','#C99A2E'],liner:'#3A2416',ink:'#3A2416',mouthLine:'#A0624A',whisk:'#FFF6EA',padDot:'#B7682F',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#F3C894',bean:'#E88E80',hair:'#D98B45',hairDark:'#9C5524',hairLight:'#F6CF9E'}),
 midnight:makeCat({name:'midnight',label:'Midnight',desc:'black shorthair',top:'#2C2C31',bot:'#1F1F23',rimLight:1,inner:'#6E5A5E',nose:'#56474D',noseLine:'#2A2024',
  iris:['#F7D45C','#D9921C'],liner:'#0E0E10',ink:'#F2D06A',mouthLine:'#77696E',whisk:'#D8D8DD',padDot:'rgba(140,140,150,.5)',eye:{w:.2,h:.18},
  paw:'#2E2E33',bean:'#56474D',hair:'#38383E',hairDark:'#1A1A1D',hairLight:'#6A6A72'}),
 latte:makeCat({name:'latte',label:'Latte',desc:'Siamese seal point',coat:'point',rx:1.04,ry:.92,n:2,top:'#F1E6D4',bot:'#DCCBB2',point:'#4A3528',earCols:['#4A3528','#4A3528'],
  ear:{h:.95,bw:.55,rot:.5,tip:.08},inner:'#7A5A4E',nose:'#3E2C24',noseLine:'#2A1C16',iris:['#B9E3FA','#3F86CF'],liner:'#2A1C16',ink:'#CFE6F5',mouthLine:'#8A7266',
  whisk:'#F5EFE6',padDot:'rgba(30,20,15,.5)',eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#4A3528',bean:'#7A5A50',hair:'#D8C6AC',hairDark:'#8A7058',hairLight:'#F4EADA'}),
 patches:makeCat({name:'patches',label:'Patches',desc:'calico',coat:'calico',top:'#F7F3EE',bot:'#E6DFD6',earCols:['#E3994E','#2C2B2F'],
  patches:[[-.48,-.36,.5,.4,.3,'#E3994E',1],[.52,-.56,.55,.36,-.4,'#2C2B2F',2],[.66,.3,.22,.15,.2,'#E3994E',3],[-.78,.36,.16,.12,-.3,'#2C2B2F',4]],
  inner:'#F2B6B8',nose:'#F0A0AE',noseLine:'#C07884',iris:['#C9DA7A','#6F9A3A'],liner:'#2A2420',ink:'#2A2420',mouthLine:'#B09A94',whisk:'#CFC8C0',padDot:'rgba(170,150,140,.55)',
  paw:'#F7F3EE',bean:'#F0A0AE',hair:'#D9B48C',hairDark:'#8A6A4A',hairLight:'#F4E6D4'}),
 blue:makeCat({name:'blue',label:'Blue',desc:'British shorthair',rx:1.22,ry:.92,n:2.5,top:'#9AA4B2',bot:'#7A8494',muzzle:'#A9B2BF',ear:{h:.62,bw:.5,rot:.55,tip:.12,cx:.8},
  inner:'#B8A0A8',nose:'#6E6C7A',noseLine:'#4C4A56',noseW:.17,nosePh:-.4,iris:['#F6B44A','#D2741E'],liner:'#2E3038',ink:'#2E3038',mouthLine:'#5A5C68',whisk:'#EEF0F4',
  padDot:'rgba(70,76,90,.45)',eye:{w:.21,h:.19},pupil0:.22,paw:'#9AA4B2',bean:'#6E6C7A',hair:'#8E98A6',hairDark:'#5E6878',hairLight:'#C2CAD4'}),
 snow:makeCat({name:'snow',label:'Snow',desc:'white longhair, odd-eyed',fluff:1,ruff:{rx:1.24,ry:.92,dy:.16,col:['#F2EFEA','#D9D3CA']},bib:'#FFFFFF',top:'#F5F3EF',bot:'#E2DED7',
  ear:{h:.82,bw:.48,tuft:1},inner:'#F4B8BE',nose:'#F2A6B0',noseLine:'#C9808C',iris:['#BCE4FA','#4A90D6'],irisR:['#F4DC7A','#D49A2A'],liner:'#3A3433',ink:'#3A3433',
  mouthLine:'#C0B4B0',whisk:'#D8D2CC',padDot:'rgba(180,165,160,.55)',paw:'#F5F3EF',bean:'#F2A6B0',hair:'#EDE8E0',hairDark:'#B8B0A6',hairLight:'#FFFFFF'}),
 oreo:makeCat({name:'oreo',label:'Oreo',desc:'black-and-white tuxedo',coat:'tuxedo',top:'#1C1C1F',bot:'#131315',rimLight:1,white:'#F6F4F1',
  furOpts:{n:700,l0:.025,l1:.03,w:.008,dark:'rgba(0,0,0,.5)',light:'rgba(96,98,108,.42)',wDark:'rgba(196,190,184,.55)',wLight:'rgba(255,255,255,.5)'},
  ear:{h:.86,bw:.54,rot:.46,tip:.08,cx:.66},inner:'#8A646C',nose:'#F2A4B2',noseLine:'#C27886',noseW:.22,noseH:.14,nosePh:-.46,
  iris:['#7FA82A','#DDEB5A'],liner:'#0B0B0D',ink:'#D8EE5E',mouthLine:'#A39A98',whisk:'#FFFFFF',padDot:'rgba(150,142,138,.6)',
  whisk2:{x0:.17,len:1.4},eye:{w:.2,h:.18},pupil0:.22,paw:'#F6F4F1',bean:'#F2A4B2',hair:'#2A2A2E',hairDark:'#101012',hairLight:'#F2F0EC'}),
 mocha:makeCat({name:'mocha',label:'Mocha',desc:'tortoiseshell',coat:'calico',top:'#30241F',bot:'#1F1713',rimLight:1,earCols:['#C9772F','#30241F'],
  patches:[[-.52,-.5,.17,.11,.6,'#C9772F',1],[-.4,-.62,.07,.05,.2,'#E2A866',2],[.06,-.62,.06,.2,.1,'#C9772F',3],[.56,-.3,.15,.09,-.5,'#C9772F',4],[.84,.12,.11,.08,.4,'#E2A866',5],
   [-.82,.16,.14,.1,-.5,'#C9772F',6],[-.32,.6,.13,.07,.25,'#E2A866',7],[.4,.58,.11,.07,-.3,'#C9772F',8],[.36,-.74,.09,.05,.3,'#E2A866',9],[-.66,.42,.07,.05,0,'#E2A866',10]],
  inner:'#7A5A54',nose:'#6E4A42',noseLine:'#3A2420',iris:['#F6C44C','#C2761A'],liner:'#120C0A',ink:'#F2C45C',mouthLine:'#8A6E64',whisk:'#EADFD0',padDot:'rgba(150,120,100,.5)',
  eye:{w:.2,h:.17},paw:'#6A4630',bean:'#2A1C18',hair:'#6A4A34',hairDark:'#2A1F1A',hairLight:'#D89A58'}),
 silver:makeCat({name:'silver',label:'Silver',desc:'silver tabby',coat:'tabby',top:'#D6DADF',bot:'#A8AEB6',light:'#EEF0F2',chinCol:'#FFFFFF',stripe:'#1D1F23',inner:'#E6BDB8',
  nose:'#C2655C',noseLine:'#7C3832',iris:['#CBE27A','#4C983C'],liner:'#16171A',ink:'#1D1F23',mouthLine:'#6E6A6C',whisk:'#FFFFFF',padDot:'#2A2C30',
  eye:{w:.2,h:.16,round:0},pupil0:.1,blushAt:[.58,.22],paw:'#D6DADF',bean:'#C2655C',hair:'#BCC1C8',hairDark:'#3A3C42',hairLight:'#F2F4F6'}),
 cloud:makeCat({name:'cloud',label:'Cloud',desc:'Ragdoll',coat:'point',fluff:1,ruff:{rx:1.3,ry:.98,dy:.2,col:['#F7F2E9','#DED4C4']},bib:'#FFFFFF',rx:1.14,ry:.92,n:2.3,
  top:'#F4EFE6',bot:'#DCD3C6',point:'#7D8796',earCols:['#7D8796','#7D8796'],muzzle:'#FBF9F6',ear:{h:.84,bw:.5,tuft:1},inner:'#C4A8AE',nose:'#D49AA4',noseLine:'#A0707A',
  iris:['#6FA8F2','#2C64D6'],liner:'#232A36',ink:'#8FC0F8',mouthLine:'#A89CA0',whisk:'#FFFFFF',padDot:'rgba(110,116,130,.45)',eye:{w:.22,h:.2},pupil0:.22,
  paw:'#FFFFFF',bean:'#D49AA4',hair:'#E8E2D8',hairDark:'#8A92A0',hairLight:'#FFFFFF'}),
 leo:makeCat({name:'leo',label:'Leo',desc:'Bengal',coat:'calico',top:'#D9A050',bot:'#B97A30',muzzle:'#F4E2C0',ear:{h:.74,bw:.5,rot:.5,tip:.1,cx:.75},
  patches:[[-.1,-.6,.024,.17,.14,'#3E2412',11],[.1,-.6,.024,.17,-.14,'#3E2412',12],[0,-.7,.022,.12,0,'#3E2412',13],[-.84,.1,.15,.022,-.3,'#3E2412',14],[.84,.1,.15,.022,.3,'#3E2412',15],
   ...[[-.6,-.42,.4,1],[.62,-.4,-.3,2],[-.34,-.76,.2,3],[.36,-.76,-.2,4],[-.84,.36,.3,5],[.86,.36,-.3,6],[-.55,.6,.2,7],[.57,.6,-.2,8]].flatMap(([x,y,r,sd])=>[[x,y,.12,.095,r,'#4A2A14',sd],[x,y,.06,.045,r,'#9C5E24',sd]])],
  inner:'#E2B49A',nose:'#C66E58',noseLine:'#7A3A28',iris:['#DADC62','#6C9A32'],liner:'#24160C',ink:'#24160C',mouthLine:'#7A5034',whisk:'#FFF6E6',padDot:'#3A2412',
  eye:{w:.2,h:.15,round:0},pupil0:.1,blushAt:[.58,.24],paw:'#E2B470',bean:'#4A2C18',hair:'#D09048',hairDark:'#4A2C16',hairLight:'#F2D29A'}),
 button:makeCat({name:'button',label:'Button',desc:'Scottish Fold',rx:1.2,ry:.94,n:2.5,top:'#BCA9B3',bot:'#988592',ear:{h:.58,bw:.46,rot:.62,tip:.2,cx:.9,fold:1},
  inner:'#C9A4AC',nose:'#B88A96',noseLine:'#7E5A66',noseW:.17,iris:['#F8A642','#C2561A'],liner:'#2E2630',ink:'#2E2630',mouthLine:'#6E6068',whisk:'#F4EEF0',
  padDot:'rgba(90,70,80,.4)',eye:{w:.22,h:.21},pupil0:.24,paw:'#BCA9B3',bean:'#B88A96',hair:'#ADA0A6',hairDark:'#7A6C74',hairLight:'#D8CED2'}),
 puff:makeCat({name:'puff',label:'Puff',desc:'Persian',fluff:1,ruff:{rx:1.46,ry:1.08,dy:.2,col:['#F3E4C8','#D8C09A']},bib:'#FFFFFF',rx:1.24,ry:.94,n:2.6,
  top:'#EED8B4',bot:'#D4B488',earSpread:.86,ear:{h:.5,bw:.42,rot:.62,tip:.12,cx:.8,tuft:1},nosePh:-.3,noseW:.15,noseH:.1,
  inner:'#F0B8B0',nose:'#E89A94',noseLine:'#B06A64',iris:['#F8B04A','#C8601A'],liner:'#3A2A20',ink:'#3A2A20',mouthLine:'#A88A78',whisk:'#FFF8EE',padDot:'rgba(170,140,110,.5)',
  whisk2:{len:1.2},eye:{th:.45,w:.22,h:.21},pupil0:.24,paw:'#F3E4C8',bean:'#E89A94',hair:'#EAD6B4',hairDark:'#B89A70',hairLight:'#FFF6E6'}),
 noodle:makeCat({name:'noodle',label:'Noodle',desc:'Sphynx',hairless:1,wrinkles:1,rx:1.04,ry:.94,n:2,top:'#E8C1AE',bot:'#CF9F8C',earSpread:.86,ear:{h:1.1,bw:.62,rot:.58,tip:.1,cx:.75},
  inner:'#EBA898',nose:'#D88A7C',noseLine:'#A45E50',iris:['#F6F07A','#C9C42E'],liner:'#3A2620',ink:'#3A2620',mouthLine:'#A87464',whisk:'#F4E2D8',padDot:'rgba(170,110,95,.4)',
  whisk2:{wcols:[1],len:.85,alpha:.5,brow:1},eye:{w:.21,h:.15,round:0},pupil0:.1,paw:'#E8C1AE',bean:'#D88A7C',hair:'#E0B6A2',hairDark:'#A87A66',hairLight:'#F6DED2'})});
const MORE=['ginger','midnight','latte','patches','blue','snow','oreo','mocha','silver','cloud','leo','button','puff','noodle'];

/** Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle. */
function kittenOf(p){const k=JSON.parse(JSON.stringify(p));k.kitten=true;k.base=p.name;k.label=p.label+' kitten';k.voice=3;
 k.rx=p.rx*.97;k.ry=p.ry*1.02;k.n=2.05;k.ear.h*=1.12;k.ear.bw*=1.06;k.ear.tuft=0;
 k.eye.w*=1.2;k.eye.h*=1.32;k.eye.round=1;k.eye.th+=.02;k.pupil0=Math.max(p.pupil0,.18);
 k.nosePh=p.nosePh+.08;k.noseW*=.85;k.noseH*=.85;k.whisk2.len*=.7;k.whisk2.brow=1;
 if(k.ruff){k.ruff.rx*=.94;k.ruff.ry*=.92}return k}

const CAT_IDS=['shrimpy','momo',...MORE];
/** A stored cat ID to its preset. An unknown ID (or anything that is not a string) falls back to Shrimpy. */
const catById=id=>typeof id==='string'&&own(PRESETS,id)?PRESETS[id]:PRESETS.shrimpy;

Object.assign(api,{PRESETS,MORE,CAT_IDS,makeCat,kittenOf,catById});

// ── Geometry: outline, face warp, anchors ────────────────────────────────────
/**
 * Head turn toward the cursor. The face is a real 3D rotation of the head ellipsoid,
 * with the muzzle standing proud of it so it swings further than the cheeks, and the
 * head outline leans into the turn. yaw/pitch are the share of upstream's 0.62/0.5 rad
 * gaze the face takes; the pupils carry the rest.
 */
const FACE={yaw:.82,pitch:.6,pitchDown:.32,lean:.08,bend:.1,muzzle:.12,nose:.05};
/** Head width D (px) from which the full cat is drawn; below it the compact drawing (ink eyes, no irises, stripes or whiskers). */
const DETAIL_FULL_MIN=28;
const detailOf=D=>D>=DETAIL_FULL_MIN?'full':'compact';
/**
 * Ear scale for the compact drawing, so the ears keep their headroom in the compact notch:
 * 1 from Ø28 up, easing down to COMPACT_EAR_SCALE at Ø20 and below.
 * PROVISIONAL: the spec only says "ears scaled down at Ø20"; the owner confirms the value on the
 * stage-1 contact sheet. To change it, edit the constant and regenerate the fixtures.
 */
const COMPACT_EAR_SCALE=.8;
const earScale=D=>D>=DETAIL_FULL_MIN?1:lerp(COMPACT_EAR_SCALE,1,clamp((D-20)/(DETAIL_FULL_MIN-20),0,1));
/** Outline sample count: small heads (R under 20 px) use fewer points. */
const outlineSteps=R=>R<20?72:200;
/** The badge sits beside the right ear, and moves to the left in the compact notch so it never sits under the camera housing. */
const badgeSide=compactNotch=>compactNotch?-1:1;
/** Cursor to gaze: how far the cursor is from the cat in px, to -1…1 (tanh over 240 px across, 180 px up and down). */
const CURSOR={x:240,y:180};
const cursorLook=(dx,dy)=>({x:Math.tanh(dx/CURSOR.x),y:-Math.tanh(dy/CURSOR.y)});
/** Pupil travel inside the eye: up to 0.24 of the eye width across and 0.18 of its height up and down. */
const pupilOffset=(yaw,pitch,w,h)=>[clamp(yaw/.62,-1,1)*.24*w,-clamp(pitch/.5,-1,1)*.18*h];
/** The share of the gaze the face takes (FACE) and the roll fade: yf, pf, the warp pitch pt and the face opacity fa. */
function faceAngles(s){const yf=s.yaw*FACE.yaw,pf=s.pitch*(s.pitch>0?FACE.pitch:FACE.pitchDown),pt=wrapA(pf+s.lift+s.roll);return{yf,pf,pt,fa:clamp((Math.cos(pt)-.05)/.3,0,1)}}

/** The neutral pose: every animatable property at rest. The engine's `s` starts here, and layout() reads one. */
const newPose=()=>({yaw:0,pitch:0,roll:0,tilt:0,open:1,sx:1,sy:1,oy:0,ox:0,tint:0,blush:0,es:1,badgeS:0,earL:0,earR:0,earU:1,earF:0,pupil:.45,mouth:0,purr:0,lid:0,lift:0,wh:0,paws:0,smile:0,tongue:0,mround:0,mskew:0,wavy:0});

/**
 * Superellipse outline as points [x, y], optionally with a fluffy edge (spike) on the lower half.
 * The fluff is a fixed sum of sines, so it needs no random numbers and is identical everywhere.
 */
function supPoints(rx,ry,n,dy,spike,count,steps=200,bend=null){const e=2/n,pts=[];
 for(let i=0;i<=steps;i++){const a=i/steps*TAU,c=Math.cos(a),s=Math.sin(a);let k=1;
  if(spike){const low=Math.max(0,s+.55)/1.55,vary=.55+.45*Math.sin(a*5.3+1.1)*Math.sin(a*2.7+.4);k+=low*spike*vary*Math.pow(Math.abs(Math.cos(a*count)),1.8)}
  let x=Math.sign(c)*Math.pow(Math.abs(c),e)*rx*k,y=Math.sign(s)*Math.pow(Math.abs(s),e)*ry*k+dy;
  if(bend){const tx=x/rx,ty=y/ry;x+=bend[0]*rx*Math.max(0,1-ty*ty);y+=bend[1]*ry*Math.max(0,1-tx*tx)}
  pts.push([x,y])}
 return pts}

/**
 * Face warp: maps a point drawn on the flat front view (units of R) onto the head
 * ellipsoid rotated by yaw and pitch, so markings, whisker pads and the muzzle turn with
 * the eyes. Points outside the head outline stay put. Identity at rest, so the rest pose
 * matches the board exactly.
 */
function mkWarp(p,yaw,pt,R){const a=p.rx,b=p.ry,vm=Math.sin(p.nosePh)-.12;
 if(Math.abs(yaw)<1e-4&&Math.abs(pt)<1e-4)return(x,y)=>[x*R,y*R];
 const cY=Math.cos(yaw),sY=Math.sin(yaw),cP=Math.cos(pt),sP=Math.sin(pt);
 return(x,y)=>{const u=x/a,v=-y/b,q=1-u*u-v*v;if(q<=0)return[x*R,y*R];
  const du=u/.55,dv=(v-vm)/.45,w=Math.sqrt(q)+FACE.muzzle*Math.exp(-(du*du+dv*dv)),u1=u*cY+w*sY,w1=w*cY-u*sY,v1=v*cP+w1*sP;
  return[u1*a*R,-v1*b*R]}}

/** Flattens M/Q/L commands (units of R) into a dense point list, so the warp can bend every edge. */
function flatten(cmds){const out=[];let px=0,py=0;
 for(const c of cmds){if(c[0]==='M'){px=c[1];py=c[2];out.push([px,py])}
  else if(c[0]==='Q'){for(let i=1;i<=10;i++){const t=i/10,m=1-t;out.push([m*m*px+2*m*t*c[1]+t*t*c[3],m*m*py+2*m*t*c[2]+t*t*c[4]])}px=c[3];py=c[4]}
  else{for(let i=1;i<=8;i++){const t=i/8;out.push([px+(c[1]-px)*t,py+(c[2]-py)*t])}px=c[1];py=c[2]}}return out}
const MOMO_WHITE=flatten([['M',0,-.6],['Q',-.13,-.4,-.17,-.12],['Q',-.19,.1,-.26,.2],['Q',-.5,.38,-.8,.36],['L',-1.3,.3],['L',-1.3,1.3],['L',1.3,1.3],['L',1.3,.3],['L',.8,.36],['Q',.5,.38,.26,.2],['Q',.19,.1,.17,-.12],['Q',.13,-.4,0,-.6]]);

/** One ear, in head-local px before tilt and squash. `ek` is the compact ear scale (earScale), 1 when not compact. */
function earGeom(p,s,sd,R,yf,pf,ek=1){const E=p.ear,rx=p.rx*R,ry=p.ry*R,th=sd*.6+yf*.85,f=Math.max(.3,Math.cos(th));
 return{bx:Math.sin(th)*p.earSpread*rx+Math.sin(yf)*FACE.bend*.54*rx,by:-.68*ry-Math.sin(pf+s.lift)*.12*ry,
  rot:sd*(E.rot+(sd<0?s.earL:s.earR)+.95*s.earF),h:E.h*R*s.earU*(1-.4*s.earF)*ek,bw:E.bw*R*f*ek,tip:E.tip*R*ek,cx:E.cx||.95}}

/**
 * Everything geometric about one cat in one pose, in px: where the head is, the warp, the eyes, the
 * nose and mouth, the ears, the badge. Drawing code only consumes this.
 *   p preset, s pose (the engine's `s`), cx/cy the cat's resting centre, D the head width.
 *   o.T seconds (for the purr shake), o.detail 'full'|'compact', o.badgeSide 1|-1, o.earScale (default 1).
 * Head-local means relative to the head centre, before the tilt and squash. `mouth` is in world px
 * and null while the nose is turned out of sight. `W` maps flat-view R-units to head-local px.
 */
function layout(p,s,cx,cy,D,o={}){const R=D/(2*p.rx),full=detailLevel(D,o.detail).full,T=o.T||0,ek=o.earScale===undefined?1:o.earScale,rx=p.rx*R,ry=p.ry*R;
 const base={x:cx,y:cy,R},purr=s.purr>.01?Math.sin(T*TAU*24)*.007*s.purr:0;
 cx+=(s.ox+purr)*R;cy+=s.oy*R;const at={x:cx,y:cy,R,D};
 const {yf,pf,pt,fa}=faceAngles(s);
 cx+=Math.sin(s.yaw)*FACE.lean*R;cy-=Math.sin(s.pitch)*FACE.lean*.8*R;
 const W=mkWarp(p,yf,pt,R);
 const eyes=[-1,1].map(sd=>{const th=sd*p.eye.th+yf,cp=Math.cos(p.eye.ph+pt),[x,y]=W(Math.sin(sd*p.eye.th)*Math.cos(p.eye.ph)*p.rx,-Math.sin(p.eye.ph)*p.ry);
  return{sd,visible:Math.cos(th)*cp>.04,x,y,fx:clamp(Math.cos(th)/Math.cos(p.eye.th),.55,1.08),fy:clamp(cp/Math.cos(p.eye.ph),.18,1.08)}});
 let nose={visible:false},mouth=null;
 if(Math.cos(yf)*Math.cos(p.nosePh+pt)>.04){const [nx0,ny0]=W(0,-Math.sin(p.nosePh)*p.ry),nx=nx0+Math.sin(yf)*FACE.nose*R,ny=ny0-Math.sin(pf)*FACE.nose*.8*R,nf=Math.max(.3,Math.cos(yf)),nw=p.noseW*R*nf,nh=p.noseH*R,my=ny+nh/2;
  nose={visible:true,nx,ny,nf,nw,nh,my};
  const lx=nx*s.sx,ly=(my+.12*R)*s.sy,c=Math.cos(s.tilt),sn=Math.sin(s.tilt);mouth={x:cx+lx*c-ly*sn,y:cy+lx*sn+ly*c}}
 const side=o.badgeSide||1;
 return{R,D,full,rx,ry,base,at,head:{x:cx,y:cy},yf,pf,pt,fa,W,steps:outlineSteps(R),
  bend:[Math.sin(yf)*FACE.bend,-Math.sin(pf)*FACE.bend*.7],ruff:{dx:-Math.sin(s.yaw)*FACE.lean*1.1*R,dy:Math.sin(s.pitch)*FACE.lean*.9*R},
  eyes,nose,mouth,ears:[-1,1].map(sd=>({sd,...earGeom(p,s,sd,R,yf,pf,ek)})),
  badge:{x:cx+side*1.4*R*s.sx,y:cy-.92*R*s.sy,k:s.badgeS*(full?1:1.25),small:!full,side}}}

/**
 * The draw order, as named layers. The renderer draws a *behind* pass, the head, then a *front* pass,
 * so outfits (sub-project I) can sit behind or in front of the head. Each layer's data comes from layout().
 */
const PASSES={behind:['glow','zoomTrails','ruff','bib','paws','ears'],head:['head','markings','tint','rim','blush','eyes','mouth','nose'],front:['foldEars','whiskers','badge','particles','balls']};

Object.assign(api,{newPose,FACE,DETAIL_FULL_MIN,detailOf,COMPACT_EAR_SCALE,earScale,outlineSteps,badgeSide,CURSOR,cursorLook,pupilOffset,faceAngles,supPoints,mkWarp,flatten,MOMO_WHITE,earGeom,layout,PASSES});

// ── Ear fit: ears that stay inside the strip ─────────────────────────────────
// The compact island's top edge is the top of the screen, and a mask cannot give ears room above it. So the renderer shrinks the ears
// just enough that no ear rises above the strip. This is the solve, in closed form; the page and both apps use it.
const EAR_FIT={margin:.5,minimum:.35};
/**
 * The factor (EAR_FIT.minimum … 1) to multiply the ear scale by so that no ear rises above `ceiling`, a y in the layout's own
 * coordinates (the top edge of the strip the cat sits in: 0 in the compact notch). 1 means the ears already fit, and a cat so close
 * to the ceiling that even the smallest ears would not fit is held at `minimum`, and a pose that is not a number gives 1 (nothing to fit).
 * `margin` is the room kept under the ceiling, in px.
 *   L is a layout() result made with earScale `ek`; the answer is the factor for ek, so layout(..., {earScale: ek * factor}) fits.
 *   s is the pose that made it (the tilt and squash turn the ears).
 * An ear scales about its own base, so its highest point rises in proportion to the scale and one linear solve replaces a search.
 * The top edge of an ear is a parabola (x = 0.9 tip u, y = -h + tip (0.475 + 0.825 u²) for u in -1…1, in ear space), and the world
 * height of an ear-space point is y0 + A x + B y, so the highest point is where u = -0.9 A / (1.65 B), held to -1…1.
 */
function earFit(L,s,ceiling,margin=EAR_FIT.margin,minimum=EAR_FIT.minimum){
 const ct=Math.cos(s.tilt),st=Math.sin(s.tilt);let f=1;
 for(const e of L.ears){
  const cr=Math.cos(e.rot),sr=Math.sin(e.rot),A=st*s.sx*cr+ct*s.sy*sr,B=ct*s.sy*cr-st*s.sx*sr,y0=L.head.y+st*s.sx*e.bx+ct*s.sy*e.by;
  const rise=u=>.9*A*e.tip*u+B*(-e.h+e.tip*(.475+.825*u*u)); // height of the top edge at u above the ear's base (negative: higher up)
  const d=Math.min(rise(-1),rise(1),rise(B>1e-9?clamp(-.9*A/(1.65*B),-1,1):0));
  if(y0+d>=ceiling+margin||d>=-1e-9)continue;
  f=Math.min(f,Math.max(minimum,(ceiling+margin-y0)/d))}
 return Number.isFinite(f)?Math.max(minimum,Math.min(1,f)):1}
Object.assign(api,{EAR_FIT,earFit});

// ── Compact detail: flat fills ───────────────────────────────────────────────
/**
 * What the renderer draws at head width D: `detail` ('full' | 'compact'), `full`, and `flatFill`, which is on exactly when the cat is
 * compact (below Ø28). `override` is layout()'s o.detail: an explicit 'full' or 'compact' wins over D.
 */
const detailLevel=(D,override)=>{const full=override?override==='full':D>=DETAIL_FULL_MIN;return{detail:full?'full':'compact',full,flatFill:!full}};
/**
 * The flat drawing, for when detailLevel().flatFill is on. At Ø12 to Ø27 a gradient cannot be seen and costs a shading pass each, so:
 *   head: one fill, the preset's top and bot colour mixed headMix of the way (0.5, halfway);
 *   ears: one fill each, the ear's top and bot colour (the ear's own colour, if it has one, is both) mixed earMix of the way;
 *   ruff: one fill, the ruff's inner colour mixed ruffMix of the way (0.6) to its outer one;
 *   rim:  no rim gradient (rimGradient false). The white rim line of the dark coats stays;
 *   tabby crown band: one ellipse, radii crown.rx and crown.ry in R, at the centre where the gradient was, in the stripe colour at crown.alpha;
 *   point mask: one ellipse, radii point.rx and point.ry in R, at the centre where the gradient was, in the point colour at point.alpha.
 *     Tuned to the gradient it replaces (a fade 1.55 R wide by R tall to 0.66 R): the same total ink, and an edge between where that fade had
 *     dropped to half and to a quarter of its strength, which is what it showed at Ø20 and at Ø28 on Latte and Cloud.
 * Everything else (markings, eyes, blush, the state tint) is drawn as in the full cat.
 */
const FLAT_FILL={headMix:.5,earMix:.5,ruffMix:.6,rimGradient:false,crown:{rx:.4,ry:.26,alpha:.5},point:{rx:.86,ry:.54,alpha:.85}};
const mixHex=(a,b,t)=>{const y=hex(b);return hex(a).map((v,i)=>lerp(v,y[i],t))};
/** The flat colours of a preset, [r, g, b] in 0…255 (not rounded): the head, the two ears (left, right), the ruff (null without one) and the point mask (null unless the coat is 'point'). */
function flatFillColors(p){const ear=sd=>{const c=p.earCols&&p.earCols[sd<0?0:1];return mixHex(c||p.top,c||p.bot,FLAT_FILL.earMix)};
 return{head:mixHex(p.top,p.bot,FLAT_FILL.headMix),ears:[ear(-1),ear(1)],ruff:p.ruff?mixHex(p.ruff.col[1],p.ruff.col[0],FLAT_FILL.ruffMix):null,point:p.coat==='point'?hex(p.point):null}}
Object.assign(api,{detailLevel,FLAT_FILL,mixHex,flatFillColors});

// ── Collar: the agent colour, worn as a thin collar ──────────────────────────
// The colour that used to fill the upstream figure (task.color) is worn as a collar in one of three styles, or not at all.
// Style IDs are frozen contract values (they are stored in settings), in this order: tag (Band and tag), band (Band),
// kerchief (Neckerchief) and off (the default). Pure maths: the renderer paints what collarGeometry returns.
const COLLAR_STYLES=['tag','band','kerchief','off'];
/** The renderer pass the collar is drawn in: between 'foldEars' and 'whiskers' of PASSES.front. PASSES itself stays as A-0 pinned it (fixtures only grow). */
const COLLAR_PASS='front';
/** A stored collar style to a style. An unknown ID, or anything that is not a string, falls back to 'off'. */
const collarStyleOf=id=>typeof id==='string'&&COLLAR_STYLES.includes(id)?id:'off';
/** Smallest sizes, in DEVICE pixels, so a collar still reads as a colour at Ø12 and Ø20. */
const COLLAR_MIN={band:3,tag:6,kerchiefW:7,kerchiefDrop:5};
/**
 * Where one collar sits, in head-local px (before tilt and squash), turning with the face warp. `null` for 'off'.
 *   tag:      {style, R, width, band, tag}   band: a polyline along the lower outline, left to right, inset so its outer edge stays
 *   band:     {style, R, width, band}        inside the head; width: its stroke width (a tenth of R, never under COLLAR_MIN.band
 *   kerchief: {style, R, kerchief}           device px); tag: {x, y, r}, a round tag at centre front; kerchief: {pts, apex}, a
 *                                            triangle under the chin (pts along the lower outline, apex below them).
 * o.dpr is the device pixel ratio (default 2, and 2 for anything that is not above 0); o.detail is as in layout().
 */
function collarGeometry(p,s,D,style,o={}){
 const id=collarStyleOf(style);if(id==='off')return null;
 const dpr=o.dpr>0?o.dpr:2,{R,W}=layout(p,s,0,0,D,{detail:o.detail}),px=n=>n/dpr/R; // device px to R-units
 const width=Math.max(.1*R,COLLAR_MIN.band/dpr),k=Math.max(.7,Math.min(.92,1-(width/2+.5/dpr)/(p.ry*R)));
 const N=90,ring=supPoints(p.rx*k,p.ry*k,p.n,0,0,0,N).slice(0,N); // R-units; index i is angle i/N of a turn, y down
 const out={style:id,R};
 if(id==='kerchief'){const hw=Math.min(p.rx*k,Math.max(.5*p.rx,px(COLLAR_MIN.kerchiefW)*.65)),arc=ring.filter(([x,y])=>y>0&&Math.abs(x)<=hw).sort((a,b)=>a[0]-b[0]),
  [ax,ay]=W(0,p.ry*k),top=Math.max(...arc.map(q=>W(...q)[1]));
  out.kerchief={pts:arc.map(q=>W(...q)),apex:[ax,Math.max(ay,top)+Math.max(.34*R,COLLAR_MIN.kerchiefDrop/dpr)]}}
 else{const lower=ring.slice(N*40/360,N*140/360+1).reverse(); // left to right, 40° to 140°
  out.width=width;out.band=lower.map(([x,y])=>W(x,y));
  if(id==='tag'){const [x,y]=W(0,p.ry*k);out.tag={x,y,r:Math.max(.16*R,COLLAR_MIN.tag/dpr/2)}}}
 return out}
Object.assign(api,{COLLAR_STYLES,collarStyleOf,COLLAR_MIN,COLLAR_PASS,collarGeometry});

// ── Personality ──────────────────────────────────────────────────────────────
// Six traits, 0…1, that bend the behaviour a cat already has. 0.5 is neutral, so the
// Balanced preset is exactly the approved motion. Any coat can wear any personality.
const TRAITS=[['energy','Energy','sleepy','bouncy'],['curiosity','Curiosity','aloof','nosy'],['chatty','Chattiness','quiet','talkative'],['affection','Affection','independent','cuddly'],['sass','Sass','easy-going','grumpy'],['mischief','Mischief','well-behaved','troublemaker']];
const PERSONAS={
 balanced:{label:'Balanced',energy:.5,curiosity:.5,chatty:.5,affection:.5,sass:.5,mischief:.5},
 chill:{label:'Chill',energy:.12,curiosity:.35,chatty:.3,affection:.65,sass:.3,mischief:.2},
 grumpy:{label:'Grumpy',energy:.4,curiosity:.3,chatty:.45,affection:.15,sass:.95,mischief:.3},
 sweet:{label:'Sweet',energy:.5,curiosity:.55,chatty:.55,affection:1,sass:.1,mischief:.3},
 hyper:{label:'Hyper',energy:1,curiosity:.9,chatty:.75,affection:.5,sass:.3,mischief:1},
 chatty:{label:'Chatty',energy:.6,curiosity:.7,chatty:1,affection:.6,sass:.35,mischief:.5}};
const TRAIT_KEYS=TRAITS.map(t=>t[0]);
/** Traits as stored: a missing, non-numeric or NaN trait becomes 0.5, anything else is held to 0…1 (a settings file can be hand-edited). */
function normPers(P){const o={};for(const k of TRAIT_KEYS){const v=P&&typeof P[k]==='number'&&Number.isFinite(P[k])?P[k]:.5;o[k]=clamp(v,0,1)}return o}
/**
 * What a personality changes, as numbers. The engine reads only these.
 *   speed, hop, blinkEvery, gaze, earFlickEvery, chatter, slowBlinkEvery are multipliers (1 at neutral);
 *   pupil, smile, skew, blush, lid and earBack are added to the resting pose (0 at neutral);
 *   idle says which idle habits are on; poke is the reaction to a poke; pokeHiss adds a hiss to it.
 */
function persMultipliers(P0){const P=normPers(P0),energy=P.energy,sass=P.sass,aff=P.affection;
 return{speed:tm(energy,.55,1.5),hop:tm(energy,.45,1.4),blinkEvery:tm(energy,1.4,.75),pupil:(energy-.5)*.3,
  lid:Math.max(Math.max(0,.5-energy),Math.max(0,sass-.55)*.55),
  gaze:tm(P.curiosity,.35,1.2),earFlickEvery:tm(P.curiosity,1.6,.6),chatter:tm(P.chatty,.3,1.4),
  smile:(aff-.5)*.5-Math.max(0,sass-.5)*1.1,blush:Math.max(0,aff-.6)*.9,slowBlinkEvery:tm(aff,1.6,.5),
  skew:Math.max(0,sass-.5)*.9,earBack:Math.max(0,sass-.55)*.45,
  idle:{yawn:energy<.3,zoomies:P.mischief>.75&&energy>.7,mew:P.chatty>.7,purr:aff>.75,hmph:sass>.75,wink:P.mischief>.65},
  poke:aff>.75&&sass<.4?'love':'annoyed',pokeHiss:sass>.7}}
/** A preset as a cat stores it: its name plus the six traits. An unknown name gives Balanced. */
const personaNamed=name=>{const k=own(PERSONAS,name)?name:'balanced',{label,...traits}=PERSONAS[k];return{preset:k,...traits}};
/** Moving a slider: the new value (held to 0…1) and the preset becomes 'custom'. An unknown trait changes nothing. */
const slide=(pers,trait,value)=>TRAIT_KEYS.includes(trait)&&typeof value==='number'&&Number.isFinite(value)?{...pers,[trait]:clamp(value,0,1),preset:'custom'}:{...pers};

Object.assign(api,{TRAITS,TRAIT_KEYS,PERSONAS,normPers,persMultipliers,personaNamed,slide});

// ── Rules: work clock and zoomies, sleep, wake, search ───────────────────────
/** An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s to be watchable. */
const ZOOM_AFTER_MS=5*60*1000;
/**
 * The work clock. Working, thinking and searching keep it running; approval and question pauses neither stop nor reset it;
 * every other state ends the run and stores how long it lasted in `workedFor` (never negative, even if the clock steps back).
 * Pure: pass the clock in, get the next one back.
 * `busySince` is null while no run is open.
 */
function workClockStep(clock,state,nowMs){const c={busySince:clock.busySince,workedFor:clock.workedFor};
 if(BUSY.has(state)){if(c.busySince===null)c.busySince=nowMs}
 else if(state!=='approval'&&state!=='question'){c.workedFor=c.busySince===null?0:Math.max(0,nowMs-c.busySince);c.busySince=null}
 return c}
const zoomiesOnFinish=(workedForMs,thresholdMs=ZOOM_AFTER_MS)=>workedForMs>=thresholdMs;
/** An idle cat falls asleep after this long with no agent event (ms). */
const SLEEP_AFTER_MS=10*60*1000;
/**
 * Milliseconds until the cat should fall asleep, for arming a one-shot timer (no polling): 10 minutes after the last
 * agent event. Only an idle cat sleeps, so any other state (approval and question included) gives null.
 * A negative or non-numeric quiet time counts as 0. 0 means: asleep now.
 */
const sleepDelay=(state,quietMs)=>state==='idle'?Math.max(0,SLEEP_AFTER_MS-Math.max(0,Number.isFinite(quietMs)?quietMs:0)):null;
/** Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile). */
const WAKE_EVENTS=['hook','hover','click'];
const wakes=kind=>WAKE_EVENTS.includes(kind);
/** Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers). */
const SEARCH_TOOLS={claude:['WebSearch','WebFetch','Grep','Glob'],gemini:['google_web_search','web_fetch','grep_search','search_file_content','glob'],codex:['web_search','grep_files']};
const SEARCH_SET=new Set(Object.values(SEARCH_TOOLS).flat());
const isSearchTool=name=>typeof name==='string'&&SEARCH_SET.has(name);
/** The state a tool event puts an agent in: a search tool is 'searching', any other tool 'working'. */
const toolState=name=>isSearchTool(name)?'searching':'working';

// ── Timelines: the greeting and the file flight ──────────────────────────────
// The greeting is Greeting v2, in the 640×150 reference space and 5.74 s long: the cat falls in with a landing squash,
// bounces, slides aside, pops up for a quick paw wave, slides back and settles with the badge and tint.
const NOTCH={W:184,H:32},COMPACT=288;
const GT={grow:.45,badge:2.72,blink2:3.8,tint0:3.85,tint1:4.15,leave:4.9,COLLAPSE:.34};
const GT2={fall0:.05,land:.62,bounce1:1.18,slide0:1.25,slide1:1.65,pop0:1.65,wave0:1.72,wave1:2.72,back0:2.75,back1:3.25,SLIDE:150};
const GREET_LEN=GT.leave+GT.COLLAPSE+.5;
const STREAKS=(()=>{const r=rng(7),cols=['#3B9EFF','#F29B38','#FF5A4E','#2EC4A0','#A78BFA'];return Array.from({length:16},(_,i)=>({a:i/16*TAU+(r()-.5)*.3,sp:230+r()*260,len:6+r()*9,t0:.08+r()*.14,col:cols[i%5]}))})();
/** Streak burst time: it starts when the cat lands. */
const streakTime=t=>t-(GT2.land-.1);
/** The island and the shared beats: size, blink, badge, tint, halo, header. Everything but the cat's own motion. */
function islandBase(t){const gx=seg(t,0,.5),g=Math.sin(Math.PI*gx/2)+.04*Math.sin(Math.PI*gx)*gx,gg=EZ.back(seg(t,.02,GT.grow)),
 blink=tb=>{const k=seg(t,tb,tb+.12);return k>0&&k<1?1-Math.sin(Math.PI*k)*.94:1};
 return{iw:lerp(NOTCH.W,640,g),ih:lerp(NOTCH.H,150,g),hb:lerp(3,58,gg),base:lerp(16,86,EZ.out(seg(t,.02,GT.grow))),open:Math.min(blink(1.95),blink(GT.blink2)),
  badge:EZ.back(seg(t,GT.badge,GT.badge+.28)),tint:.6*EZ.inOut(seg(t,GT.tint0,GT.tint1)),halo:EZ.out(seg(t,.3,.7)),haloBlue:seg(t,GT.tint0,GT.tint1),header:seg(t,.35,.6),card:seg(t,.18,.45)}}
/** The cat's fall, bounce, slide, pop and wave. */
function fallPose(t,B){const G=GT2,hb=B.hb,D=hb*1.34,base=B.base;
 let x=320,y=base,sx=1,sy=1,tilt=0,eye='dot',lookX=0,lookY=0,handL=0,handR=0,wave=-1;
 const fall=seg(t,G.fall0,G.land);y-=(1-fall*fall)*(base+70);                       // 1 fall in (accelerating)
 const sq=Math.sin(Math.PI*seg(t,G.land,G.land+.16));sy-=.2*sq;sx+=.14*sq;y+=D*.05*sq; // landing squash
 const b=seg(t,G.land+.16,G.bounce1);y-=4*b*(1-b)*hb*.3;sy+=.05*Math.sin(Math.PI*b);   // 2 small bounce
 const sq2=Math.sin(Math.PI*seg(t,G.bounce1,G.bounce1+.1));sy-=.07*sq2;sx+=.05*sq2;y+=D*.02*sq2;
 const out=EZ.inOut(seg(t,G.slide0,G.slide1)),ret=EZ.inOut(seg(t,G.back0,G.back1));   // 3 slide aside, 5 slide back
 x+=G.SLIDE*out*(1-ret);tilt=.1*Math.sin(Math.PI*seg(t,G.slide0,G.slide1))-.1*Math.sin(Math.PI*seg(t,G.back0,G.back1));
 const ant=Math.sin(Math.PI*seg(t,G.pop0-.1,G.pop0));sy-=.08*ant;y+=D*.03*ant;         // 4 pop up
 const pop=EZ.back(seg(t,G.pop0,G.pop0+.2))*(1-EZ.inOut(seg(t,G.back0,G.back0+.2)));
 y-=hb*.16*pop;sy+=.07*Math.sin(Math.PI*seg(t,G.pop0,G.pop0+.2));
 const flail=.55*(1-seg(t,G.land-.05,G.land+.1))*(t>G.fall0?1:0);                      // paws up while falling
 handL=flail;handR=Math.max(flail,pop);
 if(t>=G.wave0&&t<G.wave1+.2)wave=t-G.wave0;
 if(t>=G.land&&t<G.slide0)eye='happy';
 if(t>=G.slide0&&t<G.pop0)lookX=.5*out;
 if(t>=G.pop0&&t<G.back0){eye='happy';lookX=.3;lookY=-.4}
 if(t>=G.back0){const k=seg(t,G.back0,G.back1+.1);eye=k<.9?'content':'dot';lookX=lerp(.3,0,EZ.inOut(k));lookY=lerp(-.4,0,EZ.inOut(k))}
 return{iw:B.iw,ih:B.ih,hb,x,y,sx,sy,tilt,eye,lookX,lookY,handL,handR,wave,open:B.open,badge:B.badge,tint:B.tint,halo:B.halo,haloBlue:B.haloBlue,header:B.header,card:B.card,fx:1,minis:0}}
/** After GT.leave the island collapses to the compact notch and the cat settles. */
function collapsePose(t){const tc=GT.leave,a=islandBase(tc),e=EZ.inOut(seg(t,tc,tc+GT.COLLAPSE)),bx=320-COMPACT/2+40,bk=seg(t,tc+.14,tc+.26);
 return{iw:lerp(a.iw,COMPACT,e),ih:lerp(a.ih,32,e),hb:lerp(a.hb,20/1.34,e),x:lerp(320,bx,e),y:lerp(a.base,16,e),sx:1,sy:1,tilt:0,eye:'dot',lookX:0,lookY:0,handL:0,handR:0,wave:-1,
  open:bk>0&&bk<1?1-Math.sin(Math.PI*bk)*.94:1,badge:a.badge,tint:a.tint,halo:a.halo*(1-e),haloBlue:a.haloBlue,header:a.header*(1-seg(t,tc,tc+.1)),card:a.card*(1-seg(t,tc,tc+.18)),fx:1-seg(t,tc,tc+.2),minis:EZ.back(seg(t,tc+.24,tc+.42))}}
/**
 * The greeting pose at t seconds (0 … GREET_LEN), all in the 640×150 space: island iw×ih, cat centre x,y and head width hb×1.34,
 * squash sx/sy, tilt, eye shape ('dot' | 'happy' | 'content'), gaze lookX/lookY, paw raise handL/handR, wave clock (-1 = off), blink open,
 * and the 0…1 fades badge, tint, halo, haloBlue, header, card, fx (streaks), minis (the session cats).
 */
const greetingPose=t=>t<GT.leave?fallPose(t,islandBase(t)):collapsePose(t);

// ── The greeting's last beat: the session cats ───────────────────────────────
// Once the island has folded, the session cats pop in as a ROW of three (the prototype's), hold a moment, then glide into the 2×2 grid
// the compact island really shows; a fourth cat pops into the empty cell as they land. Every time is in seconds after `leave`, the moment
// the island starts to fold (GT.leave, or earlier when the pointer left), so the beat follows an early leave. GREET_LEN stays what it was
// (5.74 s, up to the settled row); GREET_END is where the whole greeting, glide included, ends.
const GT3={glide0:.8,glide1:1.3,four0:1,end:1.6};
const GREET_END=GT.leave+GT3.end;
/** The glide's two progress values: `grid` is the row becoming the grid, 0…1; `four` is the fourth cat's pop, 0…1 and a little over (EZ.back), like `minis`. */
const miniGlide=(t,leave=GT.leave)=>({grid:EZ.inOut(seg(t,leave+GT3.glide0,leave+GT3.glide1)),four:EZ.back(seg(t,leave+GT3.four0,leave+GT3.glide1))});
/** The prototype's row: head width, spacing and the first cat's inset from the island's right edge (px), and how far it sits below the strip's middle. */
const MINI_ROW={d:11,step:14,inset:12,dy:1};
/** The compact island's grid: cells `step` apart (the Mac's 12 pt cells and 4 pt gap, the Windows app's 13 px cells and 3 px gap), its centre `inset` px in from the island's right edge and level with the strip's middle, and the Mac's cat head width (an app with another size passes it as `d`). */
const MINI_GRID={step:16,inset:40,d:12};
/** Grid cell (top left, top right, bottom left, bottom right) to the row cat that glides into it, 0 being the row's right-most. The bottom left has none: the fourth cat pops in there. */
const MINI_FROM=[2,1,null,0];
/** A session cat narrower than this (px) is not drawn: it is the first frames of a pop, or a strip too short to hold it. */
const MINI_MIN_D=2;
/**
 * The four session cats, in the order of the grid's cells, as {x, y, d}: centre and head width in px in the greeting's 640×150 space, where the
 * island is centred at x = 320. `d` is 0 for a cat that is not there (yet), and already holds the pop and the strip's scale, so an app draws
 * every slot with d > 0 and nothing else. `minis` is the row's pop-in (greetingPose().minis), `g` is miniGlide(t, leave), `opts` the compact
 * island: W and H in px, and `d`, the head width of one grid cat in the app (the Mac's 12, the Windows app's 13). A strip shorter than 32 px
 * shrinks the whole thing the way the Mac's miniGridScale does: min(1, (H - 4) / 28).
 */
function miniSlots(minis,g,{W=COMPACT,H=NOTCH.H,d=MINI_GRID.d}={}){
 const k=Math.min(1,Math.max(0,H-4)/28),right=320+W/2,gx=right-MINI_GRID.inset,gy=H/2,s=MINI_GRID.step/2*k;
 return MINI_FROM.map((from,i)=>{
  const x1=gx+(i%2?s:-s),y1=gy+(i<2?-s:s),row=from!==null,
   x=row?lerp(right-(MINI_ROW.inset+MINI_ROW.step*from)*k,x1,g.grid):x1,y=row?lerp(gy+MINI_ROW.dy*k,y1,g.grid):y1,
   dd=(row?lerp(MINI_ROW.d,d,g.grid)*minis:d*g.four)*k;
  return{x,y,d:dd<MINI_MIN_D?0:dd}})}

/** A dropped file arcs into the cat's mouth over this long (ms). k is 0…1 along the flight. */
const FLIGHT_MS=380;
function flightAt(from,to,R,k){const q=EZ.inOut(k),cx=(from.x+to.x)/2,cy=Math.min(from.y,to.y)-60,u=1-q;
 return{x:u*u*from.x+2*u*q*cx+q*q*to.x,y:u*u*from.y+2*u*q*cy+q*q*to.y,size:lerp(R*.62,R*.14,q),rot:(1-q)*.5-.25}}

Object.assign(api,{ZOOM_AFTER_MS,workClockStep,zoomiesOnFinish,SLEEP_AFTER_MS,sleepDelay,WAKE_EVENTS,wakes,SEARCH_TOOLS,isSearchTool,toolState,NOTCH,COMPACT,GT,GT2,GREET_LEN,STREAKS,streakTime,islandBase,greetingPose,GT3,GREET_END,miniGlide,MINI_ROW,MINI_GRID,MINI_FROM,MINI_MIN_D,miniSlots,FLIGHT_MS,flightAt});

// ── Motion profiles ──────────────────────────────────────────────────────────
// Classic: upstream timings 1:1. Playful: cat body language on top of the same engine.
const CLASSIC={key:'classic',label:'Classic',
 rest:{idle:['pill',0],working:['pill',0],thinking:['pill',0],searching:['pill',0],approval:['wide',0],question:['pill',.17],error:['flat',0],finished:['happy',0],ratelimit:['tired',0],sleeping:['closed',0],dizzy:['spiral',0]},
 eye(st){return this.rest[st][0]},
 enter(c,st,prev){const a=c.anim.bind(c);switch(st){
  case 'idle':if(prev!=='idle')c.blink();break;
  case 'approval':a('oy',[[-.2,150,'out'],[0,300,'back']]);break;
  case 'error':a('ox',[[.08,50,'out'],[-.08,70,'inOut'],[.05,70,'inOut'],[0,90,'out']]);break;
  case 'finished':a('roll',[[TAU,950,'inOut']],()=>{c.s.roll=0});c.later(500,()=>c.emit('spark',5),'st');break;
  case 'ratelimit':c.emit('sweat',1);break;
  case 'dizzy':a('roll',[[2*TAU,1300,'inOut']],()=>{c.s.roll=0});break;
  default:c.blink()}},
 targets(c,st,T,tg){tg.tilt=this.rest[st][1];tg.earL=0;tg.earR=0;tg.earU=1;tg.earF=0;tg.pupil=.45;tg.oy=0;
  let ty=c.lookX*.62,tp=c.lookY*.5;
  if(st==='thinking'){ty=ty*.35+.55*.55;tp=tp*.3+.55*.5}
  if(st==='sleeping'){ty=0;tp=-.14;tg.sy=1+.035*Math.sin(1.8*T);tg.sx=1-.035*.57*Math.sin(1.8*T)}
  if(st==='searching'){ty=Math.sin(2.6*T)*.6;tp=-.06}
  if(st==='dizzy')ty=Math.sin(9*T)*.25;
  if(st==='approval')tg.oy=-Math.abs(Math.sin(5.2*T))*.07;
  return[ty,tp]},
 post(c,st,T,kG){if(!c.tw.ox)c.s.ox+=(0-c.s.ox)*kG},
 ambient(c,t){if(t<c.nextAmb)return;if(c.state==='sleeping')c.emit('z',1);if(c.state==='ratelimit'&&!c.mini&&c.rand()<.5)c.emit('sweat',1);c.nextAmb=t+1300},
 squash:[.78,1.16],
 emote(c,n){const a=c.anim.bind(c),d=1800;switch(n){
  case 'love':c.ov('heart',d);a('blush',[[1,300,'out'],[1,d-600,'lin'],[0,300,'inOut']]);c.emit('heart',4);a('oy',[[-.1,160,'out'],[0,300,'back']]);break;
  case 'surprised':c.ov('dot',d);a('oy',[[-.3,140,'out'],[0,380,'back']]);a('es',[[1.25,120,'out'],[1,500,'inOut']]);break;
  case 'proud':c.ov('star',d);c.emit('star',5);a('tilt',[[-.14,220,'out'],[-.14,d-500,'lin'],[0,280,'inOut']]);a('blush',[[.7,250,'out'],[.7,d-550,'lin'],[0,300,'inOut']]);break;
  case 'wink':c.ov('wink',d);a('tilt',[[.12,160,'out'],[.12,d-400,'lin'],[0,240,'inOut']]);break;
  case 'yawn':c.ov('tired',d);a('sy',[[1.12,500,'inOut'],[1,500,'inOut']]);a('sx',[[.94,500,'inOut'],[1,500,'inOut']]);a('mouth',[[.8,500,'inOut'],[0,500,'inOut']]);c.later(700,()=>{c.ov('closed',1100);c.emit('z',2)});break;
  case 'happy':c.ov('happy',d);a('blush',[[.6,200,'out'],[0,600,'inOut']]);break;
  case 'annoyed':c.ov('line',800);break}}};

const PLAYFUL={key:'playful',label:'Playful',
 // eye, tilt, earL, earR, earU, earF, pupil, oy
 rest:{idle:['pill',0,0,0,1,0,.45,0],working:['pill',0,-.08,-.08,1.1,0,.5,0],thinking:['pill',.14,0,.38,1,0,.55,0],searching:['wide',0,-.1,-.1,1.15,0,.92,.05],approval:['wide',0,-.12,-.12,1.22,0,.75,0],question:['pill',.24,-.05,.5,1,0,.7,0],error:['flat',0,0,0,1,1,.12,0],finished:['happy',0,.12,.12,1,0,.45,0],ratelimit:['tired',0,0,0,.9,.45,.4,0],sleeping:['closed',0,0,0,1,.25,.45,.08],dizzy:['spiral',0,0,0,1,0,.45,0]},
 eye(st){return this.rest[st][0]},
 enter(c,st,prev){const a=c.anim.bind(c);if(prev==='sleeping'&&st!=='sleeping'&&st!=='dizzy')c.later(220,()=>c.zoomies(),'st');switch(st){
  case 'idle':if(prev!=='idle')c.blink();break;
  case 'working':c.blink();c.twitch('earL');c.later(140,()=>c.twitch('earR'),'st');break;
  case 'thinking':c.blink();break;
  case 'searching':a('oy',[[.12,160,'out'],[.05,300,'inOut']]);break;
  case 'approval':a('oy',[[.08,110,'out'],[-.26,170,'out'],[0,340,'back']]);a('sy',[[.88,110,'out'],[1.1,170,'out'],[1,340,'back']]);a('sx',[[1.08,110,'out'],[.94,170,'out'],[1,340,'back']]);a('earU',[[1.4,140,'out'],[1.22,300,'inOut']]);break;
  case 'question':a('tilt',[[.3,220,'out'],[.24,300,'inOut']]);c.blink();break;
  case 'error':a('sx',[[1.14,80,'out'],[1,450,'inOut']]);a('sy',[[1.1,80,'out'],[1,450,'inOut']]);a('oy',[[.07,80,'out'],[0,420,'inOut']]);a('earF',[[1,90,'out']]);a('wh',[[.35,80,'out'],[0,500,'inOut']]);c.mpose({mouth:.75,smile:-1,mround:0},650,80,220);c.later(900,()=>c.hairball(),'st');break;
  case 'finished':if(zoomiesOnFinish(c.workedFor,c.cfg.zoomAfter)){c.later(150,()=>c.zoomies(),'st');c.later(2200,()=>c.emit('spark',4),'st');break}a('tilt',[[.16,260,'inOut'],[-.16,420,'inOut'],[.08,320,'inOut'],[0,300,'inOut']]);a('blush',[[.8,250,'out'],[.8,900,'lin'],[0,500,'inOut']]);c.later(350,()=>c.emit('spark',5),'st');break;
  case 'ratelimit':c.nextYawn=c.now()+300;break}},
 targets(c,st,T,tg){const r=this.rest[st];tg.tilt=r[1];tg.earL=r[2];tg.earR=r[3];tg.earU=r[4];tg.earF=r[5];tg.pupil=r[6];tg.oy=r[7];
  let ty=c.lookX*.62,tp=c.lookY*.5;
  if(st==='thinking'){ty=ty*.35-.55*.55;tp=tp*.3+.55*.5}
  if(st==='sleeping'){ty=0;tp=-.14;tg.sy=1+.04*Math.sin(1.2*T);tg.sx=1-.04*.57*Math.sin(1.2*T)}
  if(st==='searching'){ty=Math.sin(2.2*T)*.55;tg.earL=-.1-Math.sin(2.2*T)*.28;tg.earR=-.1+Math.sin(2.2*T)*.28}
  if(st==='dizzy'){ty=Math.sin(3.5*T)*.2;tg.tilt=Math.sin(7*T)*.12;tg.earL=Math.sin(9*T)*.45;tg.earR=-Math.sin(9*T+1)*.45}
  if(st==='approval')tg.oy=-Math.pow(Math.max(0,Math.sin(TAU*T/1.4)),4)*.09;
  if(st==='working')tg.oy=-Math.pow(Math.abs(Math.sin(Math.PI*1.6*T)),2)*.035;
  return[ty,tp]},
 post(c,st,T,kG){const s=c.s;if(!c.tw.ox){if(st==='searching')s.ox=Math.sin(16*T)*.012;else if(st==='dizzy')s.ox=Math.cos(7*T)*.07;else s.ox+=(0-s.ox)*kG}if(st==='dizzy'&&!c.tw.oy)s.oy=Math.sin(7*T)*.05},
 ambient(c,t){const st=c.state;
  if(st==='idle'&&t>=c.nextBlep){if(!c.tw.tongue&&!c.tw.mouth)c.rand()<.55?c.blep():c.lick();c.nextBlep=t+c.u(8000,15000)}
  if(['idle','working','thinking','sleeping','finished','question'].includes(st)&&t>=c.nextTw){c.twitch(c.rand()<.5?'earL':'earR');c.nextTw=t+(st==='working'?c.u(1500,3000):st==='sleeping'?c.u(4000,8000):c.u(3000,7000))*c.pm().earFlickEvery}
  if(st==='idle'&&t>=c.nextSB){c.slowBlink();c.nextSB=t+c.u(8000,14000)*c.pm().slowBlinkEvery}
  if(st==='ratelimit'&&t>=c.nextYawn){this.emote(c,'yawn');c.nextYawn=t+4800}
  if(st==='sleeping'&&t>=c.nextAmb){c.emit('z',1);c.nextAmb=t+1600}},
 squash:[.86,1.1],
 emote(c,n){const a=c.anim.bind(c),d=1800;switch(n){
  case 'love':c.ov('closed',d);a('purr',[[1,200,'out'],[1,d-500,'lin'],[0,300,'inOut']]);a('blush',[[1,300,'out'],[1,d-600,'lin'],[0,300,'inOut']]);a('earL',[[.18,250,'out'],[.18,d-500,'lin'],[0,250,'inOut']]);a('earR',[[.18,250,'out'],[.18,d-500,'lin'],[0,250,'inOut']]);a('tilt',[[c.lookX>=0?.12:-.12,400,'inOut'],[0,900,'inOut']]);c.emit('heart',3);break;
  case 'surprised':c.ov('dot',1100);a('earU',[[1.38,90,'out'],[1,600,'inOut']]);a('sx',[[1.12,80,'out'],[1,500,'inOut']]);a('sy',[[1.12,80,'out'],[1,500,'inOut']]);a('oy',[[-.2,120,'out'],[0,400,'back']]);a('pupil',[[1,100,'out'],[1,700,'lin'],[.45,400,'inOut']]);a('wh',[[.4,80,'out'],[0,500,'inOut']]);break;
  case 'proud':c.ov('happy',d);a('lift',[[.28,260,'out'],[.28,d-560,'lin'],[0,300,'inOut']]);a('earU',[[1.15,200,'out'],[1.15,d-500,'lin'],[1,300,'inOut']]);c.emit('spark',4);a('blush',[[.5,250,'out'],[.5,d-550,'lin'],[0,300,'inOut']]);break;
  case 'wink':c.ov('wink',1100);c.twitch('earR');a('tilt',[[.1,180,'out'],[.1,700,'lin'],[0,240,'inOut']]);break;
  case 'yawn':c.ov('closed',1300);a('mouth',[[1,450,'out'],[1,500,'lin'],[0,350,'inOut']]);a('sy',[[1.12,450,'inOut'],[1,800,'inOut']]);a('sx',[[.94,450,'inOut'],[1,800,'inOut']]);a('earF',[[.75,450,'inOut'],[c.tg.earF,800,'inOut']]);break;
  case 'happy':c.ov('happy',1400);a('oy',[[-.06,120,'out'],[0,160,'inOut'],[-.06,120,'out'],[0,200,'back']]);a('earU',[[1.12,150,'out'],[1,600,'inOut']]);a('blush',[[.6,200,'out'],[0,700,'inOut']]);break;
  case 'annoyed':c.ov('line',900);a('earF',[[1,60,'out'],[1,700,'lin'],[c.tg.earF,400,'inOut']]);a('wh',[[.4,60,'out'],[0,400,'inOut']]);break}}};

const PROFILES={classic:CLASSIC,playful:PLAYFUL};

/**
 * Shared settings every engine reads unless it is given its own: the global motion style, a per-cat motion override
 * (by cat ID), a per-cat personality (preset name plus six traits), and how long a run of work earns zoomies (ms).
 */
const cfg={motion:'playful',override:{},pers:{},zoomAfter:ZOOM_AFTER_MS};

// ── Engine ───────────────────────────────────────────────────────────────────
class CatEngine{
 /**
  * o.now() milliseconds and o.rand() 0…1 are injected (defaults: performance.now and Math.random, looked up late).
  * o.cfg is the shared settings {motion, override, pers, zoomAfter} (default: the module's `cfg`).
  * o.quiet turns off every random idle habit (blinks, ear flicks, bleps, personality), leaving only what is asked for.
  * o.log, an array, collects [ms, 'name'] for blinks, flicks, bleps, licks, emotes, zoomies and hairballs.
  */
 constructor(p,o={}){this.p=p;this.mini=!!o.mini;
  this.now=o.now||(()=>performance.now());this.rand=o.rand||(()=>Math.random());this.cfg=o.cfg||cfg;this.quiet=!!o.quiet;this.log=o.log||null;
  this.s=newPose();
  this.tg={yaw:0,pitch:0,tilt:0,sx:1,sy:1,es:1,oy:0,earL:0,earR:0,earU:1,earF:0,pupil:.45,purr:0,lid:0,mouth:0,smile:0,tongue:0,mround:0,mskew:0,wavy:0};
  this.tw={};this.q=[];this.parts=[];this.col=hex(COL.idle);this.colT=this.col.slice();this.gc=[255,255,255];this.ga=.12;
  this.state='idle';this.badge=null;this.eyeOv=null;this.eyeUntil=0;this.bt=0;this.lookX=0;this.lookY=0;this.slaps=[];this.dizzyUntil=0;this.saved=null;
  this.slotH=0;this.slotT=0;this.slotV=0;this.chew=0;this.chewStart=0;this.chewUntil=0;this.catching=false;
  this.waveStart=0;this.waveUntil=0;this.greetTok=0;this.balls=[];this.hbTok=0;this.zoomTok=0;this.zoomUntil=0;this.zv=0;this.mfx=0;this.busySince=null;this.workedFor=0;
  const t=this.now();this.nextBlink=t+this.u(1500,3500);this.nextTw=t+this.u(2000,5000);this.nextSB=t+this.u(6000,10000);this.nextAmb=t+1300;this.nextYawn=0;this.nextBlep=t+this.u(5000,9000);this.nextPers=t+this.u(3000,6000);this.blushBase=0;this.miniNext=0;this.miniLook={x:0,y:0};
  this.setState(o.state||'idle',true)}
 /** The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful. */
 get motion(){const m=this.cfg.override[this.p.base||this.p.name]||this.cfg.motion;return own(PROFILES,m)?m:'playful'}
 get prof(){return PROFILES[this.motion]}
 get pers(){return this.cfg.pers[this.p.base||this.p.name]||PERSONAS.balanced}
 /** What this cat's personality changes (persMultipliers). */
 pm(){return persMultipliers(this.pers)}
 u(a,b){return a+this.rand()*(b-a)}
 note(ev){if(this.log)this.log.push([Math.round(this.now()),ev])}
 anim(k,keys,done){this.tw[k]={from:this.s[k],keys,i:0,t0:this.now(),done}}
 later(d,fn,tag){this.q.push({at:this.now()+d,fn,tag})}
 ov(shape,d){this.eyeOv=shape;this.eyeUntil=this.now()+d}
 /** Holds a mouth pose for d ms, then eases back to the state's mouth. */
 mpose(v,d,i=150,o=250){for(const k in v)this.anim(k,[[v[k],i,'out'],[v[k],Math.max(0,d-i-o),'lin'],[this.tg[k],o,'inOut']])}

 blep(){this.note('blep');this.anim('tongue',[[.7,150,'out'],[.7,1300,'lin'],[this.tg.tongue,220,'inOut']])}

 lick(){this.note('lick');this.anim('mouth',[[.16,90,'out'],[this.tg.mouth,170,'inOut']]);this.anim('tongue',[[1,90,'out'],[this.tg.tongue,180,'inOut']])}
 slowBlink(){this.note('slowblink');this.anim('lid',[[.75,380,'inOut'],[.75,320,'lin'],[0,480,'inOut']])}
 eyeShape(){return this.eyeOv&&this.now()<this.eyeUntil?this.eyeOv:this.prof.eye(this.state)}
 blink(){if(this.tw.open)return;this.note('blink');this.anim('open',[[.06,70,'inOut'],[1,130,'out']])}
 twitch(ear){this.note('twitch:'+ear);const b=this.tg[ear];this.anim(ear,[[b+.5,60,'out'],[b,280,'back']]);this.anim('wh',[[.25,60,'out'],[0,300,'inOut']])}
 emit(k,n){for(let i=0;i<n;i++)this.parts.push({k,x:(this.rand()-.5)*.9+(k==='z'?.55:0)+this.s.ox/1.3,y:-.85-this.rand()*.2+this.s.oy/1.3,vx:(this.rand()-.5)*.35+(k==='z'?.18:0),vy:-(.45+this.rand()*.35),age:-.14*i,life:1.3+this.rand()*.5,size:.15+this.rand()*.08,rot:this.rand()*6})}
 setBadge(b){const tok=++this.bt;this.anim('badgeS',[[0,90,'inOut']]);this.later(100,()=>{if(tok!==this.bt)return;this.badge=b;if(b)this.anim('badgeS',[[1,280,'back']])})}
 setState(st,force){if(!own(COL,st))return;if(!force&&st===this.state)return;const prev=this.state;this.state=st;this.q=this.q.filter(x=>x.tag!=='st');if(st!=='dizzy')this.dizzyUntil=0;
  this.colT=hex(COL[st]);this.s.tint=TINT[st];const b=BADGE[st]||null;if(b!==this.badge||force)this.setBadge(b);
  for(const k of ['oy','ox','roll','sx','sy','tilt','earF','earU','lid',...MKEYS])delete this.tw[k];this.s.roll=0;
  {const wc=workClockStep({busySince:this.busySince,workedFor:this.workedFor},st,this.now());this.busySince=wc.busySince;this.workedFor=wc.workedFor}
  if(this.eyeUntil!==Infinity)this.eyeOv=null;
  this.prof.enter(this,st,prev)}
 emote(n){this.note('emote:'+n);if(n==='hello')return this.greet();if(n==='zoomies')return this.zoomies();if(n==='hairball')return this.hairball();this.prof.emote(this,n);if(own(EMOUTH,n)){const m=EMOUTH[n];this.mpose(m[0],m[1])}}
 slap(){this.interruptGreet();const t=this.now();this.slaps=this.slaps.filter(x=>t-x<1700);this.slaps.push(t);const [a,b]=this.prof.squash;
  this.anim('sy',[[a,70,'out'],[1.1,130,'out'],[1,170,'inOut']]);this.anim('sx',[[b,70,'out'],[.95,130,'out'],[1,170,'inOut']]);
  if(this.state==='dizzy')return;
  if(this.slaps.length>=3){this.slaps=[];this.saved=this.state;this.setState('dizzy');this.dizzyUntil=t+3300;return}
  const M=this.pm();if(M.poke==='love')return this.emote('love');this.emote('annoyed');if(M.pokeHiss)this.mpose({mouth:.6,smile:-1,mround:0},500,60,180)}
 /** Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks. */
 persAmbient(t){const I=this.pm().idle;if(this.state!=='idle'||t<this.nextPers)return;this.nextPers=t+this.u(6000,11000);const r=this.rand();
  if(I.yawn&&r<.5)return this.emote('yawn');
  if(I.zoomies&&r<.35)return this.zoomies();
  if(I.mew&&r<.6)return this.mpose({mouth:.42,mround:.4,smile:.2},420,100,180);
  if(I.purr&&r<.55){this.anim('lid',[[.75,380,'inOut'],[.75,600,'lin'],[0,480,'inOut']]);return this.anim('purr',[[1,200,'out'],[1,1000,'lin'],[0,300,'inOut']])}
  if(I.hmph&&r<.55)return this.mpose({smile:-.85,mskew:-.7},1000);
  if(I.wink&&r<.5){this.ov('wink',550);this.blep()}}
 /** Paw wave, upstream BotEngine.greet() timings with paws for hands. */
 greet(){const t=this.now(),tok=++this.greetTok,a=this.anim.bind(this),ok=()=>tok===this.greetTok;this.waveStart=t+450;this.waveUntil=t+1550;
  this.ov('happy',2000);a('oy',[[-.06,220,'out'],[0,220,'back']]);
  this.later(250,()=>{if(!ok())return;a('paws',[[1,280,'out']]);a('sy',[[.95,100,'out'],[1,260,'back']]);a('sx',[[1.04,100,'out'],[1,260,'back']]);if(this.motion==='playful')a('earU',[[1.15,200,'out'],[1.15,900,'lin'],[1,400,'inOut']])});
  this.later(450,()=>{if(ok())this.mpose({mouth:.45,mround:.45,smile:.35},650,90,200)});
  this.later(550,()=>{if(ok())this.blink()});this.later(1500,()=>{if(ok())this.blink()});
  this.later(1550,()=>{if(!ok())return;this.waveUntil=0;a('paws',[[0,200,'inOut']])});
  this.later(1750,()=>{if(ok())this.ov('happy',300)})}
 interruptGreet(){if(this.s.paws<=.01&&this.now()>=this.waveUntil)return;this.greetTok++;this.waveUntil=0;this.waveStart=0;this.anim('paws',[[0,150,'inOut']])}
 /** File catch: open wide while a file hovers, snap on the drop, gulp and chew on arrival. */
 catchOpen(on){if(on===this.catching)return;this.catching=on;
  if(on){this.slotT=.55;this.eyeOv='wide';this.eyeUntil=Infinity;this.anim('oy',[[-.05,160,'out'],[-.03,200,'inOut']])}
  else{this.slotT=0;if(this.eyeUntil===Infinity){this.eyeOv=null;this.eyeUntil=0}}}
 catchDrop(){this.catching=true;this.slotT=1.05;this.eyeOv='wide';this.eyeUntil=Infinity}
 catchArrive(){this.catching=false;this.slotT=0;const t=this.now(),a=this.anim.bind(this);this.chewStart=t+80;this.chewUntil=t+930;this.ov('happy',1250);
  a('sy',[[.8,80,'out'],[1.16,130,'out'],[1,220,'back']]);a('sx',[[1.24,80,'out'],[.92,130,'out'],[1,220,'back']]);
  if(this.motion==='playful'){a('earU',[[1.15,150,'out'],[1,500,'inOut']]);a('blush',[[.6,200,'out'],[0,800,'inOut']])}
  this.later(950,()=>this.lick());this.later(1000,()=>this.emit('spark',3))}
 catchReject(ext){this.catching=false;this.slotT=0;this.eyeOv=null;this.eyeUntil=0;this.later(120,()=>this.hairball(ext))}
 /** Hairball: ears back, three heaves, then it comes up (with the file, if it was one). */
 hairball(file){this.note('hairball');const a=this.anim.bind(this),pl=this.motion==='playful',tok=++this.hbTok,tg=this.tg;
  this.ov('closed',1300);if(pl)a('earF',[[.7,150,'out'],[.7,1000,'lin'],[tg.earF,400,'inOut']]);
  a('oy',[[.06,140,'out'],[0,180,'inOut'],[.07,140,'out'],[0,180,'inOut'],[.09,140,'out'],[-.02,160,'inOut'],[.11,170,'out'],[0,320,'back']]);
  a('sy',[[.92,140,'out'],[1.04,180,'inOut'],[.9,140,'out'],[1.05,180,'inOut'],[.88,140,'out'],[1.06,160,'inOut'],[.86,170,'out'],[1,320,'back']]);
  a('sx',[[1.05,140,'out'],[.98,180,'inOut'],[1.07,140,'out'],[.97,180,'inOut'],[1.09,140,'out'],[.96,160,'inOut'],[1.1,170,'out'],[1,320,'back']]);
  a('mouth',[[.22,140,'out'],[0,180,'inOut'],[.28,140,'out'],[0,180,'inOut'],[.34,140,'out'],[0,160,'inOut'],[1.05,170,'out'],[1.05,160,'lin'],[tg.mouth,260,'inOut']]);
  a('mround',[[.3,140,'out'],[.3,800,'lin'],[0,170,'out'],[0,420,'lin'],[tg.mround,200,'inOut']]);
  a('smile',[[-.7,140,'out'],[-.7,970,'lin'],[.5,330,'inOut'],[.5,700,'lin'],[tg.smile,300,'inOut']]);
  this.later(1110,()=>{if(tok===this.hbTok)this.spitBall(file)});
  this.later(1450,()=>{if(tok!==this.hbTok)return;this.ov('happy',900);if(pl)a('blush',[[.45,200,'out'],[0,700,'inOut']]);this.later(320,()=>this.lick())})}
 spitBall(file){const m=this._mouth,b0=this._base;if(!m||!b0)return;const R=b0.R,dir=this.rand()<.5?-1:1,mx=(m.x-b0.x)/R,my=(m.y-b0.y)/R;
  this.balls.push({x:mx,y:my,vx:dir*this.u(.55,.85),vy:this.u(-.9,-.6),rot:0,age:0,life:file?2.6:2.4,file:file||null,seed:(this.rand()*1e9)|0,floor:this.p.ruff?1.34:1.12});
  for(let i=0;i<4;i++)this.parts.push({k:'hair',x:mx/1.3+(this.rand()-.5)*.15,y:my/1.3,vx:(this.rand()-.5)*.5,vy:this.u(-.35,-.15),age:-.05*i,life:.9+this.rand()*.4,size:.12+this.rand()*.05,rot:this.rand()*6})}
 /** Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop. */
 zoomies(){this.note('zoomies');const a=this.anim.bind(this),pl=this.motion==='playful',tok=++this.zoomTok,tg=this.tg;this.interruptGreet();
  this.zoomUntil=this.now()+1950;this.ov('wide',1900);
  a('pupil',[[1,120,'out'],[1,1750,'lin'],[tg.pupil,400,'inOut']]);a('earF',[[.55,150,'out'],[.55,1750,'lin'],[tg.earF,400,'inOut']]);
  a('ox',[[-.05,70,'inOut'],[.04,70,'inOut'],[-.05,70,'inOut'],[.04,70,'inOut'],[0,60,'inOut'],[.88,240,'in'],[.97,90,'out'],[.84,110,'inOut'],[-.88,380,'inOut'],[-.97,90,'out'],[-.84,110,'inOut'],[.3,320,'inOut'],[0,260,'back']]);
  this.mpose({mouth:.32,tongue:.9,smile:.6,mround:0},1950,150,300);
  this.later(670,()=>{if(tok===this.zoomTok)this.dust(1)});this.later(1250,()=>{if(tok===this.zoomTok)this.dust(-1)});
  this.later(1950,()=>{if(tok!==this.zoomTok)return;this.ov('happy',900);a('sy',[[.84,90,'out'],[1.06,150,'out'],[1,220,'back']]);a('sx',[[1.14,90,'out'],[.96,150,'out'],[1,220,'back']]);this.emit('spark',3);if(pl)a('blush',[[.5,200,'out'],[0,800,'inOut']])})}
 dust(dir){const y=(this.p.ruff?1.1:.88)/1.3;for(let i=0;i<4;i++)this.parts.push({k:'dust',x:(this.s.ox+dir*.45)/1.3+(this.rand()-.5)*.2,y:y+(this.rand()-.5)*.06,vx:-dir*this.u(.12,.35),vy:-this.u(.03,.12),age:-i*.04,life:.55+this.rand()*.2,size:.09+this.rand()*.05,rot:0})}
 /** How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider. */
 mouthOpen(){return Math.max(this.s.mouth+(this.mfx||0),this.slotH+this.chew)}
 /**
  * Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth,
  * the personality, and the file-catch, wave and zoomies overrides. t is the clock in ms, T the same in seconds.
  * It reads the engine's inputs (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
  */
 computeTargets(t,T){const tg=this.tg,st=this.state,pf=this.prof;
  tg.sx=1;tg.sy=1;tg.es=1;tg.purr=0;tg.lid=0;const Mo=MOUTH[st];MKEYS.forEach((k,i)=>tg[k]=Mo[i]);this.mfx=mouthFx(st,T);
  let [ty,tp]=pf.targets(this,st,T,tg);
  // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
  const M=this.pm();ty*=M.gaze;tp*=M.gaze;
  tg.smile+=M.smile;tg.mskew+=M.skew;
  if(st!=='sleeping')tg.lid=Math.max(tg.lid,M.lid);
  tg.earF=Math.max(tg.earF,M.earBack);tg.oy*=M.hop;tg.pupil=clamp(tg.pupil+M.pupil,.1,1);
  this.blushBase=st==='sleeping'?0:M.blush;this.mfx*=M.chatter;
  if(this.mini&&!['thinking','searching','sleeping','dizzy'].includes(st)){if(t>this.miniNext){this.miniLook={x:this.u(-.88,.88),y:this.u(-.55,.45)};this.miniNext=t+this.u(500,2000)}ty=this.miniLook.x*.62;tp=this.miniLook.y*.5;tg.sy=1+Math.sin(2.2*T)*.04;tg.sx=1-Math.sin(2.2*T)*.02}
  if(this.catching){tg.earU=1.25;tg.pupil=.95;ty*=.3;tp=tp*.3+.12}
  if(t>this.waveStart&&t<this.waveUntil){const wt=(t-this.waveStart)/1000;tg.tilt=-.06+Math.sin(TAU*1.2*wt)*.07}
  if(t<this.zoomUntil){const zv=this.zv;ty=clamp(zv*.25,-.62,.62);tp=-.05;tg.tilt=clamp(zv*.05,-.2,.2);tg.sx=1+Math.min(.16,Math.abs(zv)*.045);tg.sy=1-Math.min(.09,Math.abs(zv)*.025);tg.oy=-Math.abs(Math.sin(T*TAU*4.5))*.05*Math.min(1,Math.abs(zv)/1.5)}
  tg.yaw=ty;tg.pitch=tp}
 /** One frame. dt is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range. */
 update(dt){dt=Number.isFinite(dt)?Math.min(Math.max(dt,0),.25):0;
  const t=this.now(),T=t/1000,s=this.s,tg=this.tg,st=this.state,pf=this.prof;
  for(const k in this.tw){const w=this.tw[k];let el=t-w.t0;while(w.i<w.keys.length){const key=w.keys[w.i],d=Math.max(1,key[1]);if(el<d){s[k]=lerp(w.from,key[0],EZ[key[2]](el/d));break}el-=d;w.t0+=d;w.from=key[0];s[k]=key[0];w.i++}if(w.i>=w.keys.length){delete this.tw[k];w.done&&w.done()}}
  const v=(s.ox-(this._ox??s.ox))/Math.max(dt,1e-3);this._ox=s.ox;this.zv+=(v-this.zv)*Math.min(1,dt*18);
  const due=this.q.filter(x=>x.at<=t);this.q=this.q.filter(x=>x.at>t);due.forEach(x=>x.fn());
  this.computeTargets(t,T);
  const M=this.pm(),ke=M.speed,kL=1-Math.pow(.0025,dt*ke),kG=1-Math.pow(.0008,dt*ke),kC=1-Math.pow(.002,dt);
  for(const k of ['yaw','pitch'])if(!this.tw[k])s[k]+=(tg[k]-s[k])*kL;
  for(const k of ['tilt','sx','sy','es','oy','earL','earR','earU','earF','pupil','purr','lid',...MKEYS])if(!this.tw[k])s[k]+=(tg[k]-s[k])*kG;
  pf.post(this,st,T,kG);
  const gT=hex(GLOW[st]||'#FFFFFF'),gaT=st==='dizzy'?0:(st==='idle'||st==='sleeping'?.12:.42);
  for(let i=0;i<3;i++){this.col[i]+=(this.colT[i]-this.col[i])*kC;this.gc[i]+=(gT[i]-this.gc[i])*kC}this.ga+=(gaT-this.ga)*kC;
  if(!this.quiet&&t>=this.nextBlink){if(st!=='sleeping'&&st!=='dizzy'){this.blink();if(this.rand()<.22)this.later(230,()=>this.blink())}this.nextBlink=t+(2200+this.rand()*3200)*M.blinkEvery}
  if(this.eyeOv&&t>this.eyeUntil)this.eyeOv=null;
  if(!this.quiet){pf.ambient(this,t);this.persAmbient(t)}
  if(this.dizzyUntil&&t>this.dizzyUntil){const b=this.saved||'idle';this.dizzyUntil=0;this.setState(b,true);this.emote('happy')}
  for(const p of this.parts)p.age+=dt;this.parts=this.parts.filter(p=>p.age<p.life);
  for(const b of this.balls){b.age+=dt;b.vy+=5.5*dt;b.x+=b.vx*dt;b.y+=b.vy*dt;if(b.y>b.floor){b.y=b.floor;if(b.vy>.6){b.vy*=-.38;b.vx*=.7}else{b.vy=0;b.vx*=Math.pow(.2,dt)}}b.rot+=b.vx*dt*5}
  this.balls=this.balls.filter(b=>b.age<b.life);
  // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream slot spring). Stepped at most 1/60 s at a time: one step at 60 fps or faster,
  // exactly as upstream, and several on a slow frame, because a single step longer than about 0.066 s diverges.
  const om=TAU/.25;for(let r=dt;r>0;r-=1/60){const h=Math.min(r,1/60),acc=om*om*(this.slotT-this.slotH)-2*.6*om*this.slotV;this.slotV+=acc*h;this.slotH=Math.max(0,this.slotH+this.slotV*h)}
  this.chew=t>=this.chewStart&&t<this.chewUntil?.16*(.5-.5*Math.cos(TAU*4.2*(t-this.chewStart)/1000)):0}}

/** Paw positions for the engine's wave (upstream greet timings), head-local. */
function enginePaws(e,R,rx,ry){const s=e.s;if(s.paws<=.01)return[];const n=e.now(),bodyH=2*ry,waving=e.waveStart>0&&n>=e.waveStart&&n<e.waveUntil,out=[];
 for(const sd of [-1,1]){let x=sd*rx*1.0,y=ry*.78,rot=0,beans=false;
  if(sd>0&&waving){const wt=(n-e.waveStart)/1000,rise=EZ.out(Math.min(1,wt/.18));x=lerp(x,rx*1.12+Math.cos(13*wt)*.06*bodyH,rise);y=lerp(y,-ry*.12-Math.sin(13*wt)*.12*bodyH,rise);rot=(.35+Math.sin(13*wt)*.3)*rise;beans=rise>.5}
  else if(sd<0&&waving)y+=Math.sin(6*(n-e.waveStart)/1000)*.04*bodyH;
  out.push({x,y,k:s.paws,rot,beans})}return out}

Object.assign(api,{CLASSIC,PLAYFUL,PROFILES,cfg,CatEngine,enginePaws});

// ── Stored settings: what the Cat section of Settings saves, cleaned ────────
// Settings saves a character, a motion style, a collar style and the fur-lines switch, and per cat a motion override, a collar
// override and a personality. A settings file can be hand-edited, copied from an older build or half written, so both apps pass
// what they read through cleanCatSettings before anything else sees it. Raw in, clean out, never a throw.
// The shape is the same on both sides, raw or clean (the Mac builds the raw one from its UserDefaults keys, cat.character,
// cat.motion.<id> and so on; Windows and Linux read their `cat` block):
//   {character, motionStyle, collar, furLines, cats: {<id>: {motion, collar, personality}}}   with all 16 cat IDs once clean.
/** "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style. */
const FOLLOW='follow';
/** The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful. */
const MOTION_STYLES=['playful','classic'];
const motionStyleOf=v=>MOTION_STYLES.includes(v)?v:'playful';
/** A cat's own motion: 'follow' or a style. Anything else (an unknown style, a number, null) is 'follow': no valid override. */
const motionOverrideOf=v=>MOTION_STYLES.includes(v)?v:FOLLOW;
/** A cat's own collar: 'follow' or one of the four collar styles ('off' included, which is an override like any other). Anything else is 'follow'. */
const collarOverrideOf=v=>COLLAR_STYLES.includes(v)?v:FOLLOW;
/** A stored cat ID to a cat ID. An unknown ID, or anything that is not a string, is Shrimpy (as catById does). */
const catIdOf=v=>CAT_IDS.includes(v)?v:'shrimpy';
const isPlain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const sameTraits=(a,b)=>TRAIT_KEYS.every(k=>Math.abs(a[k]-b[k])<=1e-9);
/**
 * A stored personality to a clean one: {preset, energy, curiosity, chatty, affection, sass, mischief}. It may be an object, or the JSON
 * text of one (the Mac keeps the text). Text that is not JSON, and JSON that is not an object, give Balanced. The traits go through
 * normPers (held to 0..1, missing or not a number is 0.5). 'custom' is how a hand-tuned personality is stored: the preset is kept only
 * when it names one of the six AND the traits are still that preset's (within 1e-9); anything else, a missing or unknown name included, is 'custom'.
 */
function cleanPersonality(raw){let v=raw;
 if(typeof v==='string'){try{v=JSON.parse(v)}catch{return personaNamed('balanced')}}
 if(!isPlain(v))return personaNamed('balanced');
 const traits=normPers(v),named=typeof v.preset==='string'&&own(PERSONAS,v.preset)?v.preset:null;
 return{preset:named&&sameTraits(traits,PERSONAS[named])?named:'custom',...traits}}
/** Everything Settings saves, cleaned. Never throws; unknown keys are dropped; the result always holds all 16 cats, in CAT_IDS order. */
function cleanCatSettings(raw){const r=isPlain(raw)?raw:{},cats=isPlain(r.cats)?r.cats:{},out={character:catIdOf(r.character),motionStyle:motionStyleOf(r.motionStyle),collar:collarStyleOf(r.collar),furLines:r.furLines===true,cats:{}};
 for(const id of CAT_IDS){const c=own(cats,id)&&isPlain(cats[id])?cats[id]:{};out.cats[id]={motion:motionOverrideOf(c.motion),collar:collarOverrideOf(c.collar),personality:cleanPersonality(c.personality)}}
 return out}
/** What a fresh install holds: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality. */
const defaultCatSettings=()=>cleanCatSettings(null);
/** "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The character and the global settings stay. */
function applyToAllCats(settings,id){const s=cleanCatSettings(settings),from=s.cats[catIdOf(id)],out={...s,cats:{}};
 for(const c of CAT_IDS)out.cats[c]={motion:from.motion,collar:from.collar,personality:{...from.personality}};
 return out}
/** The motion style a cat plays: its own override, else the global style. */
function motionFor(settings,id){const s=cleanCatSettings(settings),m=s.cats[catIdOf(id)].motion;return m===FOLLOW?s.motionStyle:m}
/** The collar style a cat wears (when it has a colour to wear): its own override, else the global style. */
function collarFor(settings,id){const s=cleanCatSettings(settings),c=s.cats[catIdOf(id)].collar;return c===FOLLOW?s.collar:c}
/** The shared settings an engine reads (the `cfg` of CatEngine, without zoomAfter): the global style, an override for each cat that has one, every cat's personality. */
function engineCfg(settings){const s=cleanCatSettings(settings),override={},pers={};
 for(const id of CAT_IDS){const c=s.cats[id];if(c.motion!==FOLLOW)override[id]=c.motion;pers[id]=c.personality}
 return{motion:s.motionStyle,override,pers}}
Object.assign(api,{FOLLOW,MOTION_STYLES,motionStyleOf,motionOverrideOf,collarOverrideOf,catIdOf,cleanPersonality,cleanCatSettings,defaultCatSettings,applyToAllCats,motionFor,collarFor,engineCfg});

// ── Display modes: the stored settings (sub-project B) ───────────────────────
// Settings → Cat → Display picks how the cats are shown: one cat everywhere (the default and what shipped), a cat for each agent, or the user's two
// cats side by side. What it saves goes through cleanDisplaySettings, a function of its own: cleanCatSettings and every settings-cases.json
// line stay exactly as they were, and an app cleans the same raw block with both. Raw in, clean out, never a throw.
//   raw or clean:  {displayMode, pair, agentCats: {<pillId>: <catId>}}
//   macOS keys:    cat.displayMode, cat.pair (JSON text of two cat IDs), cat.agentCat.<pillId>   Windows and Linux: the same three fields of the `cat` block.
/** The display modes, in the order Settings lists them. Frozen contract values, like the cat IDs: an unknown stored mode is 'one'. */
const DISPLAY_MODES=['one','perAgent','two'];
const displayModeOf=v=>DISPLAY_MODES.includes(v)?v:'one';
/** Two cats mode's pair before the user picks: Shrimpy and Momo. */
const DEFAULT_PAIR=['shrimpy','momo'];
/** What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen (agentCatFor). */
const DEFAULT_AGENT_CATS={integration_claude:'shrimpy',agent_codex:'momo'};
/** A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end. */
const MAX_AGENT_CATS=256;
/** A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters (`agent_` pills are lowercase, digits and hyphens). Names that are prototype members are refused. */
const PILL_ID=/^[a-z][a-z0-9_-]{1,63}$/;
const isPillId=v=>typeof v==='string'&&PILL_ID.test(v)&&v!=='constructor'&&v!=='prototype';
/** Agent pills are Claude Code's pill (integration_claude, despite its prefix) and every agent_* pill. Every other pill is an integration or an AI provider. */
const isAgentPill=v=>isPillId(v)&&(v==='integration_claude'||(v.startsWith('agent_')&&v.length>6));
/** The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or null for a pill that has none. */
const defaultAgentCat=id=>isPillId(id)&&own(DEFAULT_AGENT_CATS,id)?DEFAULT_AGENT_CATS[id]:null;
const isCatId=v=>typeof v==='string'&&CAT_IDS.includes(v);
/**
 * A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole,
 * is Shrimpy and Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
 */
function cleanPair(raw){let v=raw;
 if(typeof v==='string'){try{v=JSON.parse(v)}catch{return[...DEFAULT_PAIR]}}
 if(!Array.isArray(v)||v.length!==2||!v.every(isCatId))return[...DEFAULT_PAIR];
 return v[0]===v[1]?[v[0],CAT_IDS[(CAT_IDS.indexOf(v[1])+1)%CAT_IDS.length]]:[v[0],v[1]]}
/**
 * A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an
 * unknown pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (agentCatFor
 * gives that agent a coat again). The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
 */
function cleanAgentCats(raw){const out={};if(!isPlain(raw))return out;let n=0;
 for(const id of Object.keys(raw).filter(isPillId).sort()){if(n>=MAX_AGENT_CATS)break;
  const c=raw[id],d=defaultAgentCat(id);if(isCatId(c)){out[id]=c;n++}else if(d){out[id]=d;n++}}
 return out}
/** Everything Display saves, cleaned: {displayMode, pair, agentCats}. Never throws. */
function cleanDisplaySettings(raw){const r=isPlain(raw)?raw:{};return{displayMode:displayModeOf(r.displayMode),pair:cleanPair(r.pair),agentCats:cleanAgentCats(r.agentCats)}}
/** What a fresh install holds: One cat, Shrimpy and Momo, no stored agent coats. */
const defaultDisplaySettings=()=>cleanDisplaySettings(null);
Object.assign(api,{DISPLAY_MODES,displayModeOf,DEFAULT_PAIR,DEFAULT_AGENT_CATS,MAX_AGENT_CATS,PILL_ID,isPillId,isAgentPill,defaultAgentCat,cleanPair,cleanAgentCats,cleanDisplaySettings,defaultDisplaySettings});

// ── Display modes: giving agents their cats ──────────────────────────────────
/**
 * One coat for a new agent. `taken` lists the cat IDs already in use (a coat used twice is listed twice), `rand` returns 0 up to, not including, 1,
 * and `avoid` is a coat that is never chosen. A coat nobody uses is chosen at random (rand() is called once, and only then); when every coat is in use,
 * the least-used one is chosen, ties broken in CAT_IDS order (rand() is not called).
 */
function pickCat(taken,rand,avoid){const use={};for(const c of taken)use[c]=(use[c]||0)+1;
 const pool=CAT_IDS.filter(c=>c!==avoid),free=pool.filter(c=>!use[c]);
 if(free.length){const r=typeof rand==='function'?rand():0;return free[Math.min(free.length-1,Math.max(0,Math.floor(Number.isFinite(r)?r*free.length:0)))]}
 let best=pool[0];for(const c of pool)if((use[c]||0)<(use[best]||0))best=c;return best}
/**
 * The cat of an agent pill: its stored coat, else its default (Claude Code Shrimpy, Codex Momo), else a coat chosen now: random, from those used neither by
 * another agent (a stored one, or a default that no stored coat has replaced) nor as the Main cat; when all 16 are taken, the least-used (see pickCat).
 * Returns {cat, agentCats, assigned}: `agentCats` is the cleaned map, with the new pill added when `assigned` is true, which is the app's cue to store
 * it. A pill that is not an agent pill (an integration, or an ID that is not a pill ID) gets the Main cat and is never stored.
 */
function agentCatFor(pillId,agentCats,mainCat,rand){const map=cleanAgentCats(agentCats),main=catIdOf(mainCat);
 if(!isAgentPill(pillId))return{cat:main,agentCats:map,assigned:false};
 if(own(map,pillId))return{cat:map[pillId],agentCats:map,assigned:false};
 const d=defaultAgentCat(pillId);if(d)return{cat:d,agentCats:map,assigned:false};
 const cat=pickCat([...Object.values({...DEFAULT_AGENT_CATS,...map}),main],rand,null),next=cleanAgentCats({...map,[pillId]:cat});
 return{cat,agentCats:next,assigned:own(next,pillId)}}
/**
 * The dice button: a new random coat for one agent. Its current coat (stored or default) is never chosen again, and the rest is agentCatFor's rule, with
 * this agent's own coat set aside. Always stored, a default agent included. Returns {cat, agentCats}.
 */
function rerollAgentCat(pillId,agentCats,mainCat,rand){const map=cleanAgentCats(agentCats),main=catIdOf(mainCat);
 if(!isAgentPill(pillId))return{cat:main,agentCats:map};
 const eff={...DEFAULT_AGENT_CATS,...map},cur=eff[pillId]||null;delete eff[pillId];
 const cat=pickCat([...Object.values(eff),main],rand,cur);
 return{cat,agentCats:cleanAgentCats({...map,[pillId]:cat})}}
/** agentCatFor for each pill in turn (integrations are skipped): the map after every agent has a coat. "Reset to defaults" is this with an empty map. */
function assignAgentCats(pillIds,agentCats,mainCat,rand){let map=cleanAgentCats(agentCats);
 for(const id of Array.isArray(pillIds)?pillIds:[])map=agentCatFor(id,map,mainCat,rand).agentCats;return map}
Object.assign(api,{pickCat,agentCatFor,rerollAgentCat,assignAgentCats});

// ── Display modes: which cat appears where (the cast) ────────────────────────
// A cat stands for an agent's pill. The big cat shows the focused pill; castOf says, for the chosen mode, which coat each place wears.
//   one:      the Main cat everywhere.
//   perAgent: the focused agent's cat is the big cat (the Main cat when the focus is an integration or nothing); every agent pill wears its agent's cat;
//             integration pills wear the Main cat.
//   two:      the pair: cat 1 is the big cat and shows the focused pill, cat 2 shows the busiest other agent; pills wear the Main cat.
/** The most pills the row and the 2x2 grid hold (both apps show `others.prefix(4)` / `otherTasks.slice(0, 4)`). */
const PILL_ROW=4;
/** How busy an agent is, for the busiest-other rule: 0 waits for you (approval or question), 1 error, 2 working, thinking or searching, 3 anything else. */
const busyRank=st=>st==='approval'||st==='question'?0:st==='error'?1:BUSY.has(st)?2:3;
const rankKey=(a,b)=>{for(let i=0;i<a.length;i++)if(a[i]!==b[i])return a[i]-b[i];return 0};
/**
 * The cast of one mode. `input`: {tasks, focusId, mainCat, pair, agentCats}.
 *   tasks    the island's pills in the app's own order, each {id, state, last}: `id` the pill ID, `state` one of STATES (anything else is idle),
 *            `last` the time of the pill's last event in ms (any clock; a missing or non-number one is 0). A pill listed twice counts once.
 *   focusId  the focused pill, or null.     mainCat, pair, agentCats  as stored (cleaned here), so a raw value is fine.
 * Returns {mode, big, second, pills, drop, greeting}:
 *   big       {pill, cat}: the big cat, compact or expanded. `pill` is the focused pill (null when there is none).
 *   second    null, or in Two cats mode {pill, cat}: the busiest other agent and pair cat 2. `pill` is null when no other agent pill exists (cat 2 idles, no badge).
 *             The busiest other agent is the agent pill other than the focused one that ranks first by busyRank (waiting on you, then error, then
 *             busy, then anything else), then by the most recent `last`, then by its place in `tasks`.
 *   pills     the row and the 2x2 grid: the tasks other than the focused one and, in Two cats mode, other than `second.pill`, the first PILL_ROW of them,
 *             each {pill, cat}, in the app's order.
 *   drop      the cat of the drop view and the drag ghost: the big cat's.
 *   greeting  {cat, pair, sessions}: `cat` the cat that falls in (the Main cat in every mode); `pair` null, or in Two cats mode the pair, which arrives
 *             together at the settle; `sessions` the four session cats in the grid's cell order (top left, top right, bottom left, bottom right):
 *             the cats of `pills` (in Per agent mode, the agents' own, so the glide hands over to the grid without a change), the Main cat for a cell with no pill.
 * An agent that has no stored coat and no default wears the Main cat here: agentCatFor gives it one when it is first seen, before it is drawn.
 */
function castOf(mode,input){const m=displayModeOf(mode),inp=isPlain(input)?input:{},main=catIdOf(inp.mainCat),pr=cleanPair(inp.pair),map=cleanAgentCats(inp.agentCats),seen=new Set(),list=[];
 for(const t of Array.isArray(inp.tasks)?inp.tasks:[]){if(!isPlain(t)||!isPillId(t.id)||seen.has(t.id))continue;seen.add(t.id);
  list.push({id:t.id,state:STATES.includes(t.state)?t.state:'idle',last:typeof t.last==='number'&&Number.isFinite(t.last)?t.last:0})}
 const focus=isPillId(inp.focusId)?inp.focusId:null,agentCat=id=>own(map,id)?map[id]:defaultAgentCat(id)||main,catOf=id=>m==='perAgent'&&isAgentPill(id)?agentCat(id):main;
 const big={pill:focus,cat:m==='two'?pr[0]:catOf(focus)};
 let second=null;
 if(m==='two'){let best=null;
  list.forEach((t,i)=>{if(t.id===focus||!isAgentPill(t.id))return;const key=[busyRank(t.state),-t.last,i];if(!best||rankKey(key,best.key)<0)best={id:t.id,key}});
  second={pill:best?best.id:null,cat:pr[1]}}
 const pills=list.filter(t=>t.id!==focus&&!(second&&t.id===second.pill)).slice(0,PILL_ROW).map(t=>({pill:t.id,cat:catOf(t.id)}));
 return{mode:m,big,second,pills,drop:big.cat,greeting:{cat:main,pair:m==='two'?pr:null,sessions:[0,1,2,3].map(i=>pills[i]?pills[i].cat:main)}}}
Object.assign(api,{PILL_ROW,busyRank,castOf});

// ── Kittens: subagents shown as kittens beside their parent ──────────────────
// A subagent is a kitten of its parent's cat. Each agent pill keeps a list of kittens, and kittenStep is the one reducer that changes it. The list holds
// plain objects {id, type, session, state, born, last, until}: `id` the subagent's agent_id, `type` its agent_type, `session` the session it belongs to (or null),
// `state` working, searching, approval or leaving, `born` and `last` the times of its start and its last event (ms, any clock, the same one in every event),
// `until` null, or, once it is leaving, the time it is removed. There is no timer: a leaving kitten is dropped by the next event, and kittenView hides it from `until` on.
/** At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped. */
const KITTEN_MAX=8;
/** A kitten that has stopped plays a happy blink for this long (ms), then goes. */
const KITTEN_LEAVE_MS=600;
const KITTEN_STATES=['working','searching','approval','leaving'];
const isKittenId=v=>typeof v==='string'&&v.length>0&&v.length<=128;
const typeOfAgent=v=>typeof v==='string'?v.slice(0,64):'';
const sessionOf=v=>isKittenId(v)?v:null;
/** A kitten list as an app may hold it, made safe: entries that are not kittens, or repeat an id, are dropped; every entry is a fresh object. */
function cleanKittens(list){const out=[],seen=new Set();
 for(const k of Array.isArray(list)?list:[]){if(!isPlain(k)||!isKittenId(k.id)||seen.has(k.id)||!KITTEN_STATES.includes(k.state)||!Number.isFinite(k.born)||!Number.isFinite(k.last))continue;
  seen.add(k.id);out.push({id:k.id,type:typeOfAgent(k.type),session:sessionOf(k.session),state:k.state,born:k.born,last:k.last,until:k.state==='leaving'&&Number.isFinite(k.until)?k.until:null})}
 return out}
const capKittens=L=>{while(L.length>KITTEN_MAX){let o=0;for(let i=1;i<L.length;i++)if(L[i].born<L[o].born)o=i;L.splice(o,1)}return L};
/**
 * The reducer. `list` is one pill's kittens, `ev` an event {type, t, ...} with `t` the time in ms; the result is a new list and nothing is changed.
 *   start       {id, agentType, session}   SubagentStart: a kitten, working. `session` (the hook's session_id) is optional. A second start for an id that is there only refreshes it.
 *   tool        {id, tool}        a Pre/PostToolUse that carries an agent_id: searching when `tool` is in SEARCH_TOOLS (toolState), else working.
 *   permission  {id}              a PermissionRequest from the subagent: approval.
 *   resolved    {id}              that request was answered: back to working.
 *   stop        {id}              SubagentStop: leaving for KITTEN_LEAVE_MS, then gone.
 *   end         {session}     the parent stopped or its session ended: no kittens. With a `session`, only that session's kittens go, and the ones with no session (two sessions of
 *                             one agent share a pill, and one of them stopping must not take the other's kittens); without one, every kitten goes.
 *   sweep                         the cat's sleep timer fired: a kitten whose last event is SLEEP_AFTER_MS or more ago is gone (its stop never came).
 *   tick                          nothing but the time.
 * Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or for a kitten that is already leaving, changes
 * nothing: a late tool event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to show. An event that is not
 * an object, has no finite `t` or has an unknown type returns the list as it is (cleaned). Never throws.
 */
function kittenStep(list,ev){let L=cleanKittens(list);
 if(!isPlain(ev)||!Number.isFinite(ev.t))return L;
 const t=ev.t,at=id=>L.findIndex(k=>k.id===id&&k.state!=='leaving'),set=(i,p)=>{L[i]={...L[i],...p}};
 L=L.filter(k=>k.state!=='leaving'||k.until>t);
 switch(ev.type){
  case 'start':{if(!isKittenId(ev.id))break;const i=L.findIndex(k=>k.id===ev.id);
   if(i>=0&&L[i].state!=='leaving'){set(i,{last:t,type:typeOfAgent(ev.agentType)||L[i].type,session:sessionOf(ev.session)||L[i].session});break}
   if(i>=0)L.splice(i,1);
   L.push({id:ev.id,type:typeOfAgent(ev.agentType),session:sessionOf(ev.session),state:'working',born:t,last:t,until:null});capKittens(L);break}
  case 'tool':{const i=at(ev.id);if(i>=0)set(i,{state:toolState(ev.tool),last:t});break}
  case 'permission':{const i=at(ev.id);if(i>=0)set(i,{state:'approval',last:t});break}
  case 'resolved':{const i=at(ev.id);if(i>=0)set(i,{state:L[i].state==='approval'?'working':L[i].state,last:t});break}
  case 'stop':{const i=at(ev.id);if(i>=0)set(i,{state:'leaving',last:t,until:t+KITTEN_LEAVE_MS});break}
  case 'end':{const q=sessionOf(ev.session);L=q===null?[]:L.filter(k=>k.session!==null&&k.session!==q);break}
  case 'sweep':L=L.filter(k=>t-k.last<SLEEP_AFTER_MS);break}
 return L}
/** The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`, a later start first when they tie). */
const kittenOrder=list=>cleanKittens(list).map((k,i)=>({k,i})).sort((a,b)=>(b.k.state==='approval')-(a.k.state==='approval')||b.k.born-a.k.born||b.i-a.i).map(x=>x.k);
/** What is drawn at `now` (ms): the kittens in kittenOrder, without a leaving kitten whose time is up. A `now` that is not a number hides nothing. */
const kittenView=(list,now)=>kittenOrder(cleanKittens(list).filter(k=>k.state!=='leaving'||!Number.isFinite(now)||k.until>now));
/**
 * Where kittens sit. Every number is a multiple of a unit: `D`, the parent's head width, with the origin at the parent's head centre (x to the right, y down),
 * or `H`, the pill's height, with the origin at the pill's trailing edge (x positive towards the trailing end, so the kittens' x is negative) and
 * the middle of its height. `d` is a kitten's head width. The numbers are the brainstorm mockup's, divided by its parent's size: Ø15 kittens under a
 * Ø58 big cat (centres 24, 42 and 60 px right of it and 34 px down, 18 apart), Ø12 beside a Ø20 compact cat (22 and 35 px right, 5 down, "+N" 42 right and
 * 10 up), Ø15 in a 28 px pill.
 *   align 'start': the i-th kitten is at x0 + i * step; 'center': the row is centred on x0.   max: the most kittens drawn; the rest is "+N".
 *   moreAt: where the "+N" label is centred (default: the next slot after the last one drawn; the pair's is below the middle of its row, away from the other cat's kittens), and moreSize its text height.
 *   label: for the pair in the compact notch, which has no room beside it: only a count "×N", drawn by the second cat of the pair, at that spot.
 */
const KITTEN_PLACES={
 bigExpanded:{unit:'D',max:3,d:15/58,x0:24/58,y0:34/58,step:18/58,align:'start',moreSize:.2},
 bigCompact:{unit:'D',max:2,d:12/20,x0:22/20,y0:5/20,step:13/20,align:'start',moreAt:[42/20,-10/20],moreSize:.25},
 pairCompact:{unit:'D',max:0,label:{x:1.1,y:.3,size:.5}},
 pairExpanded:{unit:'D',max:3,d:15/58,x0:0,y0:34/58,step:18/58,align:'center',moreAt:[0,50/58],moreSize:.2},
 pill:{unit:'H',max:3,d:15/28,x0:-17.5/28,y0:0,step:-16/28,align:'start',moreSize:.36}};
/** The place kittens go for the big cat (and, in Two cats mode, for cat 2): bigExpanded or bigCompact; in Two cats mode pairExpanded or pairCompact. */
const kittenPlaceOf=(mode,expanded)=>displayModeOf(mode)==='two'?(expanded?'pairExpanded':'pairCompact'):(expanded?'bigExpanded':'bigCompact');
/**
 * The slots for one parent's kittens in one place. `kittens` is what kittenView returned (already in order). Returns
 * {place, unit, count, shown, more, moreAt, label}: `shown` the first `max` kittens as {id, state, x, y, d}; `more` how many are left over;
 * `moreAt` {x, y, size} or null when none is left over; `label` null, or for pairCompact {text: "×N", x, y, size} when there is a kitten. An unknown place shows nothing.
 */
function kittenSlots(place,kittens){const P=own(KITTEN_PLACES,place)?KITTEN_PLACES[place]:null,L=Array.isArray(kittens)?kittens.filter(k=>isPlain(k)&&isKittenId(k.id)):[],count=L.length;
 if(!P)return{place:String(place),unit:null,count,shown:[],more:0,moreAt:null,label:null};
 const n=Math.min(count,P.max),x=i=>P.align==='center'?P.x0+(i-(n-1)/2)*P.step:P.x0+i*P.step,more=P.label?0:count-n;
 return{place,unit:P.unit,count,shown:L.slice(0,n).map((k,i)=>({id:k.id,state:typeof k.state==='string'?k.state:'working',x:x(i),y:P.y0,d:P.d})),more,
  moreAt:more>0?{x:P.moreAt?P.moreAt[0]:P.x0+P.max*P.step,y:P.moreAt?P.moreAt[1]:P.y0,size:P.moreSize}:null,
  label:P.label&&count>0?{text:`×${count}`,x:P.label.x,y:P.label.y,size:P.label.size}:null}}
Object.assign(api,{KITTEN_MAX,KITTEN_LEAVE_MS,KITTEN_STATES,cleanKittens,kittenStep,kittenOrder,kittenView,KITTEN_PLACES,kittenPlaceOf,kittenSlots});

// ── Small eyes: the coloured eyes of the compact detail level (sub-project B) ─
// Below Ø28 the plain resting eyes (pill, wide, dot and tired) used to be the cat's ink colour, the same for every cat. They are now small coloured eyes:
// a round iris in the coat's colours, a slit pupil, one catchlight and a thin dark rim, so Shrimpy stays green-eyed and Momo gold-eyed down to Ø12.
// This is the geometry only, in px of the eye's own frame (its centre is the origin, y down, before the renderer's foreshortening). The colours are
// the renderer's: the iris is a radial gradient from the preset's iris[0] at the centre to iris[1] at radius `iris.r` (irisR for the right eye, sd = 1,
// when the coat has one), the pupil is Theme.Cat.pupil, the catchlight white at 0.92, the rim the preset's liner colour. The expression shapes
// (happy, closed, wink's right eye, spiral, heart, star, line and flat) stay ink and are not part of this.
/** The resting shapes that become a small coloured eye. The left eye of a wink is one too (the right is an ink arc). */
const SMALL_EYE_SHAPES=['pill','wide','dot','tired'];
/**
 * The numbers. Sizes are fractions of u = R * es, the head radius times the expression scale (the surprised emote makes the eyes bigger), and are
 * full widths and heights. The iris is 0.42 wide and 0.46 tall (the ink pill it replaces was 0.34 by 0.40); the pupil 0.18 by 0.40, held inside the iris.
 * wide is the iris times (1.16, 1.12), as the ink shape was; dot is a round iris (0.42 by 0.42) with a round, dilated pupil (0.26 across); tired
 * shows at most `open` 0.42 of the eye. The pupil moves with the gaze (yaw / 0.62 and pitch / 0.5, held to -1 to 1) by at most travel.x of the iris's
 * half-width across and travel.y of its half-height up or down (0.2 and 0.08: a slit pupil that nearly fills the iris has little room), and so never leaves it. The catchlight has radius max(0.075 u, 0.45 px) at (-0.11 u, -0.10 u), kept to the same
 * share of the iris when the eye is smaller or squinting; the rim is max(0.05 u, 0.5 px) wide. A blink or squint under `closeBelow` of the eye's
 * height closes it to a line, as the realistic eye does (its arc, in the ink colour). A kitten's eye is `kitten.w` times wider and `kitten.h` times
 * taller, the ratio kittenOf gives a kitten's eyes.
 * The black coats `bright` (and their kittens, which keep the coat id) glow like the old pill: the renderer fills the iris flat with the lighter of the
 * preset's two iris colours by luminance, draws no rim (`rim` 0, `flat` true), and the slit pupil is `brightPupil.w` wide (dot keeps its round pupil).
 * An explicit list, not a preset field, so the other coats and the old preset fixtures do not change.
 */
const SMALL_EYE={iris:{w:.42,h:.46},pupil:{w:.18,h:.40},wide:{w:1.16,h:1.12},dot:{iris:[.42,.42],pupil:[.26,.26]},tired:{open:.42},
 light:{x:-.11,y:-.10,r:.075,minR:.45},rim:{k:.05,min:.5},travel:{x:.2,y:.08},closeBelow:.22,pupilFit:.87,kitten:{w:1.2,h:1.32},line:{width:.045,minWidth:1,curve:.4},
 bright:['midnight','oreo','mocha'],brightPupil:{w:.12}};
/** True when the renderer draws shape `shape` of the eye `sd` (-1 left, 1 right) with smallEye at the compact level, and false when it stays ink. */
const usesSmallEye=(shape,sd)=>SMALL_EYE_SHAPES.includes(shape)||(shape==='wink'&&sd<0);
/**
 * One small eye. `o`: {sd (-1 or 1, default -1), R (head radius, px), es (expression scale, default 1), open (0 to 1: pose.open * (1 - pose.lid), default 1),
 * yaw and pitch (the pose's, default 0), kitten (default false), cat (a coat id; only a string in SMALL_EYE.bright is a bright coat, anything else is normal)}. A non-number is taken as its default; R is held to 0 up to 10000, es to 0 up to 10 and `open` to 0 up to 1. Returns null for a
 * shape that is not a small eye (draw the ink shape), else
 *   {shape, closed: false, iris: {rx, ry, r}, pupil: {x, y, rx, ry}, light: {x, y, r}, rim[, flat: true, rim 0]}    the two ellipses' radii, their centres, the gradient radius r
 *   {shape, closed: true, line: {x0, y0, cx, cy, x1, y1, width}}                                  a quadratic arc in the ink colour, drawn at alpha 0.9
 */
function smallEye(shape,opts){const o=isPlain(opts)?opts:{};if(!usesSmallEye(shape,o.sd===1?1:-1))return null;
 const num=(v,d)=>typeof v==='number'&&Number.isFinite(v)?v:d,S=SMALL_EYE,R=Math.max(0,Math.min(1e4,num(o.R,0))),u=R*Math.max(0,Math.min(10,num(o.es,1))),sh=shape==='wink'?'pill':shape,kit=o.kitten===true,bri=typeof o.cat==='string'&&S.bright.includes(o.cat),kw=kit?S.kitten.w:1,kh=kit?S.kitten.h:1;
 const open=Math.max(0,Math.min(1,num(o.open,1))),op=sh==='tired'?Math.min(open,S.tired.open):open;
 const base=sh==='dot'?S.dot.iris:[S.iris.w*(sh==='wide'?S.wide.w:1),S.iris.h*(sh==='wide'?S.wide.h:1)],rx0=base[0]/2*kw*u,ry0=base[1]/2*kh*u;
 if(op<S.closeBelow)return{shape,closed:true,line:{x0:-rx0,y0:0,cx:0,cy:S.line.curve*ry0,x1:rx0,y1:0,width:Math.max(S.line.minWidth,S.line.width*u)}};
 const ry=ry0*op,pw=(sh==='dot'?S.dot.pupil[0]:bri?S.brightPupil.w:S.pupil.w)/2*kw*u,pry=Math.min((sh==='dot'?S.dot.pupil[1]:S.pupil.h)/2*kh*u,S.pupilFit*ry),
  gx=Math.max(-1,Math.min(1,num(o.yaw,0)/.62)),gy=Math.max(-1,Math.min(1,num(o.pitch,0)/.5)),
  px=gx*S.travel.x*rx0,py=-gy*S.travel.y*ry;
 return{shape,closed:false,iris:{rx:rx0,ry,r:Math.max(rx0,ry)},pupil:{x:px,y:py,rx:pw,ry:pry},
  light:{x:S.light.x/(S.iris.w/2)*rx0,y:S.light.y/(S.iris.h/2)*ry,r:Math.max(S.light.r*u,S.light.minR)},rim:bri?0:Math.max(S.rim.k*u,S.rim.min),...(bri?{flat:true}:{})}}
Object.assign(api,{SMALL_EYE_SHAPES,SMALL_EYE,usesSmallEye,smallEye});

// ── The desktop cat: the trip (sub-project H) ────────────────────────────────
// The big cat can leave the notch and live on the desktop. desktopStep is the one machine for its trip and desktopFlightAt the flight between the notch and
// the desktop. A "spot" is the cat's head centre on the desktop, in points, y down, the origin at the top left of the main screen. Everything here is new
// names: nothing above this section changed, and the apps' copies of the older rules (KITTEN_PLACES, kittenSlots, flightAt, the cleaners) stay valid.
/**
 * The phases of the trip. Frozen contract values, like the cat IDs. The spec lists six; flyingHome is the seventh: a double-click, the menu or the switch
 * "flies it home", and none of the six is that flight (retracting ends at the notch spot for an alert, flyingHome ends at home).
 */
const DESKTOP_PHASES=['home','flyingOut','onDesktop','retracting','atNotchForAlert','returning','flyingHome'];
/**
 * What each phase means to an app. flight: the cat is in the air. dir: 'out' flies towards the desktop spot, 'in' towards the notch spot.
 * drawn: the desktop window draws the cat. notchEmpty: the big cat's spot in the notch is empty (never two copies of one cat: drawn implies notchEmpty).
 * on: what Settings stores as "the cat is out". home and flyingHome are off, so quitting mid-flight leaves the cat home.
 */
const DESKTOP_PHASE_INFO={
 home:{flight:false,dir:null,drawn:false,notchEmpty:false,on:false},
 flyingOut:{flight:true,dir:'out',drawn:true,notchEmpty:true,on:true},
 onDesktop:{flight:false,dir:null,drawn:true,notchEmpty:true,on:true},
 retracting:{flight:true,dir:'in',drawn:true,notchEmpty:true,on:true},
 atNotchForAlert:{flight:false,dir:null,drawn:false,notchEmpty:false,on:true},
 returning:{flight:true,dir:'out',drawn:true,notchEmpty:true,on:true},
 flyingHome:{flight:true,dir:'in',drawn:true,notchEmpty:true,on:false}};
/**
 * The events desktopStep takes. dragOut and move carry a `spot` {x, y}; the others carry nothing.
 *   dragOut{spot}  the big cat was dropped on the desktop         move{spot}   the desktop cat was dragged to a new spot
 *   toggle         the menu-bar item, ⌃⌥D or the Settings switch  sendHome     a double-click, "Send home", or the cat dropped on the notch
 *   alertOn        an approval or a question became pending       alertOff     both are clear         flightDone  a flight reached its end
 *   launch         the app started after the greeting and the cat was out         screensChanged   the connected screens changed
 */
const DESKTOP_EVENTS=['dragOut','move','toggle','sendHome','alertOn','alertOff','flightDone','launch','screensChanged'];
/**
 * What an app does on a transition (the `act` desktopStep returns; null means nothing). Flights go between the notch spot and the desktop spot.
 *   place     the cat was dropped at event.spot: show it there, no flight        flyOut    fly from the notch spot to the desktop spot
 *   flyHome   fly from the desktop spot to the notch spot                          retract   the surprised emote, then fly from the desktop spot to the notch spot
 *   turn      reverse the flight in progress: carry on the other way from progress 1 - t (desktopFlightAt retraces its own path)
 *   keep      the flight goes on the same way under its new phase; nothing to show   land   the flight ended at the desktop spot
 *   dock      the flight ended at the notch spot: the notch shows the cat again       goHome the cat was already in the notch spot: it is simply back there
 *   move      the dragged cat was released at event.spot: clamp it (clampSpot) and save it
 *   resettle  the screens changed: find the spot again (spotFor) and put the cat there
 */
const DESKTOP_ACTS=['place','flyOut','flyHome','retract','turn','keep','land','dock','goHome','move','resettle'];
/** phase → event → [next phase, act]. An event that is not listed makes no sense in that phase and changes nothing. */
const DESKTOP_NEXT={
 home:{dragOut:['onDesktop','place'],toggle:['flyingOut','flyOut'],launch:['flyingOut','flyOut']},
 flyingOut:{toggle:['flyingHome','turn'],sendHome:['flyingHome','turn'],alertOn:['retracting','turn'],flightDone:['onDesktop','land'],screensChanged:['flyingOut','resettle']},
 onDesktop:{move:['onDesktop','move'],toggle:['flyingHome','flyHome'],sendHome:['flyingHome','flyHome'],alertOn:['retracting','retract'],screensChanged:['onDesktop','resettle']},
 retracting:{toggle:['flyingHome','keep'],sendHome:['flyingHome','keep'],alertOff:['returning','turn'],flightDone:['atNotchForAlert','dock']},
 atNotchForAlert:{toggle:['home','goHome'],sendHome:['home','goHome'],alertOff:['returning','flyOut']},
 returning:{toggle:['flyingHome','turn'],sendHome:['flyingHome','turn'],alertOn:['retracting','turn'],flightDone:['onDesktop','land'],screensChanged:['returning','resettle']},
 flyingHome:{toggle:['flyingOut','turn'],flightDone:['home','dock']}};
/** A spot is {x, y} of finite numbers no larger than 100000 in size. */
const SPOT_LIMIT=1e5;
const dkSpot=v=>isPlain(v)&&typeof v.x==='number'&&typeof v.y==='number'&&Math.abs(v.x)<=SPOT_LIMIT&&Math.abs(v.y)<=SPOT_LIMIT?{x:v.x,y:v.y}:null;
/**
 * The trip's machine. `state` is a phase (anything else counts as 'home'), `ev` an event {type, ...}. Returns {state, act}: the next phase and what the app does
 * (DESKTOP_ACTS), or the same phase with act null when the event makes no sense there. dragOut and move without a valid spot make no sense either. An alert that
 * clears mid-flight turns the cat around (retracting + alertOff is returning); a sendHome during an alert ends the trip at home (an approval that lands while
 * the cat is home does not take it out). Pure, and it never throws.
 */
function desktopStep(state,ev){const s=DESKTOP_PHASES.includes(state)?state:'home',same={state:s,act:null};
 if(!isPlain(ev)||typeof ev.type!=='string'||!own(DESKTOP_NEXT[s],ev.type))return same;
 if((ev.type==='dragOut'||ev.type==='move')&&!dkSpot(ev.spot))return same;
 const [next,act]=DESKTOP_NEXT[s][ev.type];return{state:next,act}}
/** The flight between the notch spot and the desktop spot takes this long (ms), about 0.6 s. */
const DESKTOP_FLIGHT_MS=600;
/** The flight's arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right). */
const DESKTOP_ARC={lift:.25,max:90};
/**
 * Where the cat is `t` (0 to 1, held to that range; a t that is not a number is 0) of the way along a flight from `from` to `to` ({x, y}; anything else counts as 0, 0):
 * a quadratic arc eased in and out (EZ.inOut), with the cat at full size the whole way (scale 1). Returns {x, y, scale}. The path is the same both ways:
 * the position at (from, to, t) is the position at (to, from, 1 - t), so a flight that turns around carries on from 1 - t and retraces itself.
 */
function desktopFlightAt(from,to,t){const f=dkSpot(from)||{x:0,y:0},g=dkSpot(to)||{x:0,y:0},k=typeof t==='number'&&!Number.isNaN(t)?clamp(t,0,1):0,q=EZ.inOut(k),dx=g.x-f.x,dy=g.y-f.y,len=Math.hypot(dx,dy);
 let nx=0,ny=0;if(len>0){nx=dy/len;ny=-dx/len;if(ny>0||(ny===0&&nx<0)){nx=-nx;ny=-ny}}
 const lift=Math.min(len*DESKTOP_ARC.lift,DESKTOP_ARC.max),cx=(f.x+g.x)/2+nx*lift,cy=(f.y+g.y)/2+ny*lift,u=1-q;
 return{x:u*u*f.x+2*u*q*cx+q*q*g.x,y:u*u*f.y+2*u*q*cy+q*q*g.y,scale:1}}
// The file catch (fixes after H). A file on its way into the island is an alert to the desktop cat: it flies to the notch as it does for an approval (the surprised emote, then the arc), the
// island's catch plays with that one cat, and it flies back to its spot when the drop flow is over. To desktopStep this is alertOn and alertOff, so there is no new phase, event or act and
// every older fixture row stands. What is new is the one rule for "something wants the cat at the notch", the one test a catch waits on, and one constant.
/** How long a dropped file waits for the desktop cat to be at the notch (ms) before the catch plays anyway. The surprise is 450 ms and the flight 600, so a cat that left at the first sign of the drag is usually there already. */
const DESKTOP_CATCH_WAIT_MS=1500;
/**
 * Whether something wants the desktop cat at the notch: an approval, a question, a chat's approval card, a pill whose state is 'approval' or 'question' (`pillStates`, a list of state
 * names), a file on its way into the island (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen), or an incoming transfer offer from another machine
 * (`transferOffer`: a card is waiting for a click; sub-project G2). A flag counts only when it is exactly true; input that is not an object is no alert. Pure, never throws.
 */
function desktopAlert(input){const o=isPlain(input)?input:{};
 return o.approval===true||o.question===true||o.chatApproval===true||o.fileCatch===true||o.transferOffer===true||(Array.isArray(o.pillStates)&&o.pillStates.some(s=>s==='approval'||s==='question'))}
/**
 * Whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty, home and atNotchForAlert (exactly the phases the
 * desktop window does not draw). A value that is not a phase counts as home.
 */
function desktopCatchReady(phase){const p=DESKTOP_PHASES.includes(phase)?phase:'home';return !DESKTOP_PHASE_INFO[p].notchEmpty}
Object.assign(api,{DESKTOP_PHASES,DESKTOP_PHASE_INFO,DESKTOP_EVENTS,DESKTOP_ACTS,DESKTOP_NEXT,desktopStep,DESKTOP_FLIGHT_MS,DESKTOP_ARC,desktopFlightAt,DESKTOP_CATCH_WAIT_MS,desktopAlert,desktopCatchReady});

// ── The desktop cat: size, frame rate and kittens (sub-project H) ────────────
/** The desktop cat's three sizes, as the head width in points. The IDs are frozen contract values, like the cat IDs; `medium` is the default. */
const DESKTOP_SIZES={small:48,medium:64,large:96};
const DESKTOP_SIZE_IDS=['small','medium','large'];
const DEFAULT_DESKTOP_SIZE='medium';
/** A stored size to one of the three IDs. Anything else, the case and the type included, is 'medium'. */
const desktopSizeOf=v=>DESKTOP_SIZE_IDS.includes(v)?v:DEFAULT_DESKTOP_SIZE;
/** The frame rates (per second). `asleep` is one still frame every 2 s, redrawn for a slow breath; `off` draws nothing. */
const DESKTOP_FPS={motion:60,active:20,idle:5,asleep:.5,off:0};
/** The cursor is "near" the cat within this many points of the cat's centre. */
const DESKTOP_NEAR=150;
/**
 * The frame rate the app aims for, from what the cat is doing: {phase, hidden, dragging, emote, kittenMotion, dance, asleep, working, cursorDist}.
 *   phase         a DESKTOP_PHASES ID; only a phase the desktop window draws (flyingOut, onDesktop, retracting, returning, flyingHome) is ever drawn there
 *   hidden        true while the screen is asleep or locked, the display is off, or a fullscreen app covers the cat
 *   dragging, emote, kittenMotion (a kitten arriving or leaving), dance (the music bob)   each true when it is going on
 *   asleep        the ten-minute sleep; the app clears it the moment a hover, a click or an agent event wakes the cat
 *   working       the cat's agent is working, thinking or searching
 *   cursorDist    points from the cursor to the cat's centre; leave it out when the app cannot know (Wayland)
 * In this order: 0 when it is not drawn or hidden; 60 for any motion (a flight included); 0.5 asleep; 20 working or the cursor near; else 5.
 * Only `true` counts for a flag, and anything that is not an object, or has no phase, draws nothing. Pure, and it never throws.
 */
function desktopFps(i){if(!isPlain(i)||!DESKTOP_PHASES.includes(i.phase)||!DESKTOP_PHASE_INFO[i.phase].drawn||i.hidden===true)return DESKTOP_FPS.off;
 if(DESKTOP_PHASE_INFO[i.phase].flight||i.dragging===true||i.emote===true||i.kittenMotion===true||i.dance===true)return DESKTOP_FPS.motion;
 if(i.asleep===true)return DESKTOP_FPS.asleep;
 if(i.working===true||(Number.isFinite(i.cursorDist)&&i.cursorDist<=DESKTOP_NEAR))return DESKTOP_FPS.active;
 return DESKTOP_FPS.idle}
/**
 * Where the desktop cat's kittens sit: the same slot maths as KITTEN_PLACES (the i-th kitten at x0 + i * step, up to `max`, then "+N" at the next slot), in its own
 * table so the table both apps copy stays as it is. Units are D, the cat's head width, from its head centre (x right, y down): the kittens stand in a row at the
 * lower right, clear of the badge (upper right) and of the ruff. They scale with the size, so one table serves Ø48, Ø64 and Ø96.
 */
const DESKTOP_KITTEN_PLACE={unit:'D',max:3,d:.3,x0:.82,y0:.22,step:.33,moreSize:.2};
/**
 * The slots for the cat's kittens. `kittens` is what kittenView returned (already in order). `side` 1 puts them on the right of the cat, -1 on its left
 * (a cat in the right half of its screen keeps them on screen); anything else is 1. Returns {place: 'desktop', unit, count, shown, more, moreAt, label: null}
 * as kittenSlots does: `shown` the first three as {id, state, x, y, d}, `more` how many are left over, `moreAt` {x, y, size} of the "+N" or null.
 */
function desktopKittenSlots(kittens,side){const P=DESKTOP_KITTEN_PLACE,m=side===-1?-1:1,L=Array.isArray(kittens)?kittens.filter(k=>isPlain(k)&&isKittenId(k.id)):[],count=L.length,n=Math.min(count,P.max),more=count-n;
 return{place:'desktop',unit:P.unit,count,shown:L.slice(0,n).map((k,i)=>({id:k.id,state:typeof k.state==='string'?k.state:'working',x:m*(P.x0+i*P.step),y:P.y0,d:P.d})),more,
  moreAt:more>0?{x:m*(P.x0+P.max*P.step),y:P.y0,size:P.moreSize}:null,label:null}}
Object.assign(api,{DESKTOP_SIZES,DESKTOP_SIZE_IDS,DEFAULT_DESKTOP_SIZE,desktopSizeOf,DESKTOP_FPS,DESKTOP_NEAR,desktopFps,DESKTOP_KITTEN_PLACE,desktopKittenSlots});

// ── The desktop cat: spots on the screens (sub-project H) ────────────────────
// Where the cat sits, per arrangement of connected screens. A screen is {frame: {x, y, w, h}, visible: {x, y, w, h}, main: true}, in points with y down and the origin at
// the top left of the main screen (the Mac converts from AppKit's bottom-left origin): `frame` is the whole screen and `visible` what the menu bar and the Dock leave
// (it defaults to the frame and is held inside it); `main` marks the screen with the menu bar. A spot is the cat's head centre {x, y}.
/** The cat keeps this many points between its head and the edge of the visible frame, so it never sits under the menu bar or the Dock. */
const DESKTOP_MARGIN=24;
/** The first spot ever: this fraction of the main screen's visible frame across (right of centre) and down (a third, below the notch). */
const DESKTOP_DEFAULT={x:.6,y:1/3};
/** A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys). */
const MAX_DESKTOP_SPOTS=32;
const dkRect=v=>isPlain(v)&&['x','y','w','h'].every(k=>typeof v[k]==='number'&&Math.abs(v[k])<=1e6)&&v.w>=1&&v.h>=1?{x:v.x,y:v.y,w:v.w,h:v.h}:null;
/** The screens that are screens, as {frame, visible, main}, sorted by frame and at most 16. A screen without a usable frame is dropped; a visible frame that is missing or outside its frame is the frame. */
function dkScreens(raw){const out=[];
 for(const s of Array.isArray(raw)?raw.slice(0,256):[]){const f=isPlain(s)?dkRect(s.frame):null;if(!f)continue;
  const v=dkRect(s.visible),x0=v?Math.max(v.x,f.x):0,y0=v?Math.max(v.y,f.y):0,x1=v?Math.min(v.x+v.w,f.x+f.w):0,y1=v?Math.min(v.y+v.h,f.y+f.h):0;
  out.push({frame:f,visible:v&&x1>x0&&y1>y0?{x:x0,y:y0,w:x1-x0,h:y1-y0}:f,main:s.main===true})}
 return out.sort((a,b)=>a.frame.x-b.frame.x||a.frame.y-b.frame.y||a.frame.w-b.frame.w||a.frame.h-b.frame.h).slice(0,16)}
const dkRound=v=>Math.floor(v+.5);
/**
 * The key a screen arrangement is remembered under: the frames, rounded to whole points (half up: floor(v + 0.5)), sorted, written "x,y,w,h" and joined with "|". The order
 * the screens come in does not matter; the visible frames and the main flag are not part of it (moving the Dock must not forget the spot). No screens: "".
 */
function screenKey(screens){return dkScreens(screens).map(s=>[s.frame.x,s.frame.y,s.frame.w,s.frame.h].map(dkRound)).sort((a,b)=>a[0]-b[0]||a[1]-b[1]||a[2]-b[2]||a[3]-b[3]).map(r=>r.join(',')).join('|')}
const SCREEN_KEY=/^-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}(\|-?\d{1,7},-?\d{1,7},\d{1,7},\d{1,7}){0,15}$/;
/** True for exactly the strings screenKey writes: whole-string shape, no leading zeros or -0, positive sizes, frames in sorted order, at most 16. */
const isScreenKey=k=>typeof k==='string'&&SCREEN_KEY.test(k)&&screenKey(k.split('|').map(q=>{const [x,y,w,h]=q.split(',').map(Number);return{frame:{x,y,w,h}}}))===k;
const dkHas=(r,p)=>p.x>=r.x&&p.x<r.x+r.w&&p.y>=r.y&&p.y<r.y+r.h;
const dkMain=S=>S.find(s=>s.main)||S.find(s=>dkHas(s.frame,{x:0,y:0}))||S[0];
/** The spot held inside a screen's visible frame, `d` (the head width) and DESKTOP_MARGIN from every edge; a frame too small for that holds the centre. */
const dkPlace=(s,p,d)=>{const v=s.visible,m=DESKTOP_MARGIN+d/2,at=(lo,len,c)=>len<=2*m?lo+len/2:clamp(c,lo+m,lo+len-m);return{x:at(v.x,v.w,p.x),y:at(v.y,v.h,p.y)}};
/** The first spot ever, on the main screen (the one marked main, else the one at the origin, else the first by frame), for a size ID. null with no screens. */
function defaultDesktopSpot(screens,size){const S=dkScreens(screens);if(!S.length)return null;const s=dkMain(S),v=s.visible;
 return dkPlace(s,{x:v.x+v.w*DESKTOP_DEFAULT.x,y:v.y+v.h*DESKTOP_DEFAULT.y},DESKTOP_SIZES[desktopSizeOf(size)])}
/**
 * Keeps a spot where the cat may sit: on the screen whose frame holds it, inside that screen's visible frame, DESKTOP_MARGIN from the head's edge (so the centre is
 * margin + d/2 from every edge). A spot on no screen (its screen was unplugged, or it is not a spot) moves to the main screen's default spot. `size` is a size ID
 * (anything else is medium). null with no screens.
 */
function clampSpot(spot,screens,size){const S=dkScreens(screens);if(!S.length)return null;const p=dkSpot(spot),s=p&&S.find(q=>dkHas(q.frame,p));
 return s?dkPlace(s,p,DESKTOP_SIZES[desktopSizeOf(size)]):defaultDesktopSpot(screens,size)}
/**
 * A stored map from screen key to spot, cleaned. It may be an object, or the JSON text of one (the Mac stores text; text that is not JSON is {}). A key that is not
 * what screenKey writes is dropped (`__proto__` included), and so is a value that is not a spot. The result is in code-point order of the keys, at most MAX_DESKTOP_SPOTS.
 */
function cleanDesktopSpots(raw){let v=raw;if(typeof v==='string'){try{v=JSON.parse(v)}catch{return{}}}
 const out={};if(!isPlain(v))return out;let n=0;
 for(const k of Object.keys(v).filter(isScreenKey).sort()){if(n>=MAX_DESKTOP_SPOTS)break;const s=dkSpot(v[k]);if(s){out[k]=s;n++}}
 return out}
/** The spot to use now: the one remembered for this arrangement of screens, held where the cat may sit, else the default spot. null with no screens. */
function spotFor(spots,screens,size){if(!dkScreens(screens).length)return null;const k=screenKey(screens),m=cleanDesktopSpots(spots);
 return own(m,k)?clampSpot(m[k],screens,size):defaultDesktopSpot(screens,size)}
/** The map after the cat was released at `spot` on these screens: this arrangement's spot is the clamped one, the others stay. Always keeps the new key, even in a full map. */
function rememberSpot(spots,screens,spot,size){const m=cleanDesktopSpots(spots),c=clampSpot(spot,screens,size);if(!c)return m;const k=screenKey(screens),out={};
 for(const q of Object.keys(m).filter(q=>q!==k).slice(0,MAX_DESKTOP_SPOTS-1).concat(k).sort())out[q]=q===k?c:m[q];return out}
Object.assign(api,{DESKTOP_MARGIN,DESKTOP_DEFAULT,MAX_DESKTOP_SPOTS,screenKey,isScreenKey,defaultDesktopSpot,clampSpot,cleanDesktopSpots,spotFor,rememberSpot});

// ── The desktop cat: the stored settings (sub-project H) ─────────────────────
// What the cat's menu and Settings save: whether it is out, its size, and its spot for each arrangement of screens. A clean-up of its own, like cleanDisplaySettings:
// cleanCatSettings, cleanDisplaySettings and every line of settings-cases.json and display-cases.json stay as they were, and an app cleans the same stored block with
// each function it needs. Raw in, clean out, never a throw.
//   raw or clean:  {on, size, spots: {<screenKey>: {x, y}}}
//   macOS keys:    cat.desktop.on (a Bool), cat.desktop.size (small, medium or large), cat.desktop.spots (the JSON text of the map)
//   Windows and Linux: the `desktop` object of the `cat` block of settings.json, {on, size, spots} with `spots` an object.
/**
 * Everything the desktop cat saves, cleaned: {on, size, spots}. `on` is true only for the boolean true (the number 1 and the text "true" are off), `size` one of the three
 * IDs (anything else is medium), `spots` what cleanDesktopSpots keeps (an object or JSON text of screen keys to spots). Never throws.
 */
function cleanDesktopSettings(raw){const r=isPlain(raw)?raw:{};return{on:r.on===true,size:desktopSizeOf(r.size),spots:cleanDesktopSpots(r.spots)}}
/** What a fresh install holds: the cat at home, Medium, no spots. */
const defaultDesktopSettings=()=>cleanDesktopSettings(null);
Object.assign(api,{cleanDesktopSettings,defaultDesktopSettings});

// ── The wardrobe (sub-project I): outfits for the big cats ───────────────────
// Sixteen outfits, drawn new for NotchMeow, and two ways to choose: None and Auto (the season). One outfit at a time, worn by every cat in a big-cat role (the
// island's main cat, both cats of Two cats mode, each agent's big cat, the desktop cat) at every size, and never by a kitten or a small cat. Everything here is pure:
// the IDs and their clean-up, Auto's calendar, who wears it, where an outfit sits on a head (anchors) and the shapes it is made of (geometry). The renderers paint the
// shapes; the colours are roles that the theme (shared/theme.json, the `outfits` group) resolves. Only new names: nothing above this section changed.
// The 18 selection IDs and their order (the grid's, the menu's and the shortcut's cycle) are frozen contract values: they are stored.
const OUTFIT_IDS=['auto','none','partyhat','santahat','witchhat','bunnyears','sunglasses','beanie','bow','scarf','roundglasses','crown','bell','bandana','fishclip','flower','shrimpclip','blossomclip'];
/** The names the UI shows, by ID. */
const OUTFIT_NAMES={auto:'Auto',none:'None',partyhat:'Party hat',santahat:'Santa hat',witchhat:'Witch hat',bunnyears:'Bunny ears',sunglasses:'Sunglasses',beanie:'Beanie',bow:'Bow',scarf:'Scarf',roundglasses:'Round glasses',crown:'Crown',bell:'Bell',bandana:'Bandana',fishclip:'Fish clip',flower:'Flower',shrimpclip:'Shrimp clip',blossomclip:'Peach-blossom clip'};
/** The grid's rows: the two choices, then the four groups with their headings. */
const OUTFIT_GROUPS=[{id:'choice',name:'',ids:['auto','none']},{id:'seasonal',name:'Seasonal',ids:['partyhat','santahat','witchhat','bunnyears','sunglasses']},{id:'everyday',name:'Everyday',ids:['beanie','bow','scarf','roundglasses','crown']},{id:'extras',name:'Cat extras',ids:['bell','bandana','fishclip','flower']},{id:'own',name:"The cats' own",ids:['shrimpclip','blossomclip']}];
/** The 16 outfits that are drawn (everything but the two choices). */
const OUTFIT_DRAWN=OUTFIT_IDS.slice(2);
const DEFAULT_OUTFIT='auto';
/** A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is 'auto'. */
const outfitIdOf=v=>typeof v==='string'&&OUTFIT_IDS.includes(v)?v:DEFAULT_OUTFIT;
/**
 * What Settings stores for the wardrobe, cleaned: {outfit}. `raw` is the stored block as plain JSON (the `cat` block of settings.json, or the Mac's values gathered into one
 * object); a clean-up of its own, like cleanDisplaySettings, so cleanCatSettings and the older fixtures stay as they were. Never throws.
 *   macOS key: cat.outfit (a string)     Windows and Linux: the `outfit` key of the `cat` block of settings.json
 */
function cleanWardrobeSettings(raw){const r=isPlain(raw)?raw:{};return{outfit:outfitIdOf(r.outfit)}}
/** Gregorian Easter Sunday of a year from 1583 to 9999 as {month, day} (the Meeus/Jones/Butcher computation); null for any other year. */
function easterOf(year){if(!Number.isInteger(year)||year<1583||year>9999)return null;
 const a=year%19,b=Math.floor(year/100),c=year%100,d=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30,i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),n=h+l-7*m+114;
 return{month:Math.floor(n/31),day:n%31+1}}
/** Days since 1970-01-01 of a calendar date, from the date numbers alone (no clock, no time zone), so a difference of two dates can never be shifted by daylight saving. */
const owDays=(y,m,d)=>{const yy=m<=2?y-1:y,era=Math.floor(yy/400),yoe=yy-era*400,doy=Math.floor((153*(m+(m>2?-3:9))+2)/5)+d-1,doe=yoe*365+Math.floor(yoe/4)-Math.floor(yoe/100)+doy;return era*146097+doe-719468};
const owValid=(y,m,d)=>Number.isInteger(y)&&Number.isInteger(m)&&Number.isInteger(d)&&y>=1&&y<=9999&&m>=1&&m<=12&&d>=1&&d<=[31,y%4===0&&(y%100!==0||y%400===0)?29:28,31,30,31,30,31,31,30,31,30,31][m-1];
/**
 * What Auto wears on a local date (year, month, day as numbers; the northern calendar, the same for everyone). The first rule that matches wins, and the order is the contract:
 *   1 Dec 31 to Jan 2 partyhat   2 Dec 1 to Dec 26 santahat   3 Oct 1 to Nov 1 witchhat   4 Good Friday to Easter Monday (Easter -2 to +1) bunnyears   5 Jun 21 to Aug 31 sunglasses
 * Anything else, and a date that is not a real date, is 'none'. Pure: the same in Node, Swift and TypeScript.
 */
function autoOutfitFor(y,m,d){if(!owValid(y,m,d))return'none';
 if((m===12&&d===31)||(m===1&&d<=2))return'partyhat';
 if(m===12&&d<=26)return'santahat';
 if(m===10||(m===11&&d===1))return'witchhat';
 const E=easterOf(y);if(E){const k=owDays(y,m,d)-owDays(y,E.month,E.day);if(k>=-2&&k<=1)return'bunnyears'}
 if((m===6&&d>=21)||m===7||m===8)return'sunglasses';
 return'none'}
/** The outfit to draw: the stored choice cleaned, with 'auto' replaced by what autoOutfitFor says for the date ('none' when nothing is worn). Never 'auto'. */
const resolveOutfit=(id,y,m,d)=>{const o=outfitIdOf(id);return o==='auto'?autoOutfitFor(y,m,d):o};
/** The roles a drawn cat can have. The apps map their views: the cast's big cats and the desktop cat are 'big', the pills' cats, the mini row and the grid 'small', the subagent kittens 'kitten'. */
const OUTFIT_ROLES=['big','small','kitten'];
/** Who wears the outfit: the big-cat role, at every size (the compact notch's Ø20 cat included). Anything else, and anything that is not a role, is bare. */
const outfitWorn=role=>role==='big';
Object.assign(api,{OUTFIT_IDS,OUTFIT_NAMES,OUTFIT_GROUPS,OUTFIT_DRAWN,DEFAULT_OUTFIT,outfitIdOf,cleanWardrobeSettings,easterOf,autoOutfitFor,resolveOutfit,OUTFIT_ROLES,outfitWorn});

// ── Where an outfit sits: slots, floors, anchors ─────────────────────────────
// An outfit is a short list of shapes in head-local px (before the tilt and squash, like collarGeometry), turning with the face warp. Three slots say where in the draw
// order a shape goes, without touching PASSES (A-0 pinned it): behind (after the cat's ears in the behind pass: bunny ears, so the head covers their roots), neck (in the
// front pass after the collar: scarf, bandana, bell) and top (after neck, before the whiskers: hats, crown, glasses, clips, bow, flower). The whiskers, the badge and the
// particles stay in front of every outfit. OUTFIT_ORDER is the whole order with the outfit's three places in it.
const OUTFIT_SLOTS=['behind','neck','top'];
const OUTFIT_ORDER={behind:[...PASSES.behind,'outfit.behind'],head:[...PASSES.head],front:['foldEars','collar','outfit.neck','outfit.top','whiskers','badge','particles','balls']};
/**
 * Smallest sizes, in DEVICE pixels (as COLLAR_MIN is), so an outfit still reads on the compact notch's Ø20 cat (40 device pixels wide at 2x):
 *   height  a hat's, a crown's or a bunny ear's height above the crown, when the room above it is short   line  the thinnest stroke   rim  a glasses rim
 *   ball    the radius of a pompom, a bell or a gem                                                          span  the narrowest solid part (an ear of the bunny, a tail, a clip)
 */
const OUTFIT_MIN={height:6,line:1,rim:2,ball:3,span:6};
/** Whether a coat's head is dark enough that an outfit's thin edge must be light to show: 'light' for a dark head, 'dark' for a light one (the flat head colour's luminance under 100). */
function outfitEdge(p){const c=mixHex(p.top,p.bot,FLAT_FILL.headMix);return .2126*c[0]+.7152*c[1]+.0722*c[2]<100?'light':'dark'}
/**
 * The room above the crown for a hat, in px: the distance from the crown to `ceiling` (the y of the top of the strip the cat sits in, in the same coordinates as `headY`, the head's y),
 * less the ear fit's margin. null when there is no ceiling (a number is required), which means no limit. `a` is outfitAnchors().
 */
const outfitRoom=(a,headY,ceiling)=>typeof ceiling==='number'&&Number.isFinite(ceiling)&&typeof headY==='number'&&Number.isFinite(headY)?Math.max(0,headY+a.top.y-ceiling-EAR_FIT.margin):null;
/**
 * Where the outfit parts attach to one cat in one pose, in head-local px:
 *   top   the crown between the ear bases, on the head outline        gap   the span between the two ear bases       half  gap/2       lean  a hat's lean with the face turn, rad
 *   ears  each ear {sd, bx, by, rot, h, tipX, tipY}: its base, its tilt and its tip     eyes  each eye frame {sd, visible, x, y, fx, fy}
 *   chin  {pts, front}: the lower head outline from 40 to 140 degrees, left to right, and its centre front     neck  the point the collar's tag hangs from (collarGeometry's)
 *   edge  'light' or 'dark' (outfitEdge)      R, rx, ry, D, full, dpr
 * o.dpr is the device pixel ratio (default 2); o.detail, o.earScale as in layout() (earScale defaults to what the renderer uses: 1 from Ø28, else earScale(D)).
 */
function outfitAnchors(p,s,D,o={}){
 const dpr=o.dpr>0?o.dpr:2,ek=o.earScale===undefined?(D>=DETAIL_FULL_MIN?1:earScale(D)):o.earScale,L=layout(p,s,0,0,D,{detail:o.detail,earScale:ek}),{R,rx,ry,W}=L,[eL,eR]=L.ears;
 const mx=(eL.bx+eR.bx)/2,gap=Math.abs(eR.bx-eL.bx),tx=clamp(mx/rx,-.95,.95),top={x:mx,y:-ry*Math.pow(Math.max(0,1-Math.pow(Math.abs(tx),p.n)),1/p.n)+L.bend[1]*ry*(1-tx*tx)};
 const N=90,ring=supPoints(rx,ry,p.n,0,p.fluff?.035:0,14,N,L.bend).slice(0,N),arc=ring.slice(N*40/360,N*140/360+1).reverse(),front=[(arc[12][0]+arc[13][0])/2,(arc[12][1]+arc[13][1])/2];
 const width=Math.max(.1*R,COLLAR_MIN.band/dpr),k=Math.max(.7,Math.min(.92,1-(width/2+.5/dpr)/(p.ry*R))),[nx,ny]=W(0,p.ry*k);
 return{R,rx,ry,D,full:L.full,dpr,top,gap,half:gap/2,lean:Math.sin(L.yf)*.15,
  ears:L.ears.map(e=>({sd:e.sd,bx:e.bx,by:e.by,rot:e.rot,h:e.h,tipX:e.bx+e.h*Math.sin(e.rot),tipY:e.by-e.h*Math.cos(e.rot)})),
  eyes:L.eyes.map(e=>({sd:e.sd,visible:e.visible,x:e.x,y:e.y,fx:e.fx,fy:e.fy})),chin:{pts:arc,front},neck:{x:nx,y:ny},edge:outfitEdge(p)}}
Object.assign(api,{OUTFIT_SLOTS,OUTFIT_ORDER,OUTFIT_MIN,outfitEdge,outfitRoom,outfitAnchors});

// ── What an outfit is made of ────────────────────────────────────────────────
// outfitGeometry returns the shapes of one outfit on one cat, in paint order, as plain data in head-local px, in a vocabulary of three:
//   {k:'poly',    slot, fill, stroke, sw, a, fine, pts}               a closed polygon (rounded shapes are sampled)
//   {k:'curve',   slot,       stroke, sw, a, fine, pts}               an open polyline, stroked with round caps and joins
//   {k:'ellipse', slot, fill, stroke, sw, a, fine, x, y, rx, ry, rot} an ellipse (rot in rad)
// `fill` and `stroke` are colour roles (the keys of the theme's `outfits` group) or null; the role 'edge' stands for the thin edge of this coat (anchors.edge: 'light' or 'dark',
// the theme's edgeLight and edgeDark). `a` is the alpha, `sw` the stroke width in px (0 with no stroke). A `fine` shape (a glint, a star, a rib) is left out of the cat drawn below
// Ø28, as the cat's own fine details are. A hat rises from the crown by a natural height, shortened to `o.room` (see outfitRoom) but never below the floor.
// o: {dpr, detail, earScale, collar, room}. `collar` is a collar style (it is read for the bell, which hangs from it, and never changed).
// An outfit ID that is not one of the drawn outfits, 'none' and 'auto' give [].
function outfitGeometry(id,p,s,D,o={}){
 if(!OUTFIT_DRAWN.includes(id))return[];
 const A=outfitAnchors(p,s,D,o),{R,dpr,top,full}=A,fl=n=>OUTFIT_MIN[n]/dpr,ln=Math.max(fl('line'),.03*R),g=A.half,ca=Math.cos(A.lean),sa=Math.sin(A.lean),out=[];
 const Q=(x,y,b=[top.x,top.y])=>[b[0]+x*ca-y*sa,b[1]+x*sa+y*ca],room=typeof o.room==='number'&&Number.isFinite(o.room)?o.room:Infinity,hatH=nat=>Math.max(fl('height'),Math.min(nat*R,room));
 const poly=(slot,pts,fill,st={})=>out.push({k:'poly',slot,fill,stroke:st.stroke===undefined?'edge':st.stroke,sw:st.stroke===null?0:st.sw||ln,a:st.a===undefined?1:st.a,fine:!!st.fine,pts});
 const curve=(slot,pts,stroke,sw,st={})=>out.push({k:'curve',slot,stroke,sw:Math.max(sw,fl('line')),a:st.a===undefined?1:st.a,fine:!!st.fine,pts});
 const ell=(slot,x,y,rx,ry,rot,fill,st={})=>out.push({k:'ellipse',slot,fill,stroke:st.stroke===undefined?'edge':st.stroke,sw:st.stroke===null?0:st.sw||ln,a:st.a===undefined?1:st.a,fine:!!st.fine,x,y,rx,ry,rot});
 const arcPts=(cx,cy,rx,ry,a0,a1,n=10)=>Array.from({length:n+1},(_,i)=>{const a=a0+(a1-a0)*i/n;return[cx+Math.cos(a)*rx,cy+Math.sin(a)*ry]});
 const star=(cx,cy,ro,ri)=>Array.from({length:10},(_,i)=>{const r=i%2?ri:ro,a=-Math.PI/2+i*Math.PI/5;return[cx+Math.cos(a)*r,cy+Math.sin(a)*r]});
 const pill=(slot,w,yc,hh,fill)=>poly(slot,[...arcPts(w-hh,yc,hh,hh,-Math.PI/2,Math.PI/2,6),...arcPts(hh-w,yc,hh,hh,Math.PI/2,Math.PI*1.5,6)].map(q=>Q(q[0],q[1])),fill); // a stadium shape, w its outer half width
 const ear=sd=>A.ears.find(e=>e.sd===sd);
 const ball=r=>Math.max(fl('ball'),r);
 /** A tapered leaf along a centre line: `c(t)` the centre, `w(t)` the half width, both for t from 0 to 1. */
 const leaf=(c,w,n=14)=>{const L=[],Rr=[];for(let i=0;i<=n;i++){const t=i/n,a=c(t),b=c(Math.min(1,t+.02)),d=c(Math.max(0,t-.02)),tx=b[0]-d[0],ty=b[1]-d[1],l=Math.hypot(tx,ty)||1,nx=-ty/l,ny=tx/l,ww=w(t);L.push([a[0]+nx*ww,a[1]+ny*ww]);Rr.push([a[0]-nx*ww,a[1]-ny*ww])}return[...L,...Rr.reverse()]};
 // ── Hats: they stand between the ear bases, so they are as wide as the gap and no wider
 if(id==='partyhat'){const Hh=hatH(1.35),b=[top.x,top.y+.05*R],w=.7,tx=.3,H=(x,y)=>Q(x*g,y*Hh,b),Lf=t=>H(-w+(tx+w)*t,-t),Rt=t=>H(w+(tx-w)*t,-t),tip=H(tx,-1);
  poly('top',[...arcPts(0,0,w*g,.1*R,Math.PI,0,8).map(q=>Q(q[0],-q[1],b)),tip],'partyA');
  for(const [t0,t1] of [[.16,.32],[.5,.64]])poly('top',[Lf(t0),Lf(t1),Rt(t1),Rt(t0)],'partyB',{stroke:null});
  poly('top',star(tip[0],tip[1]-.04*R,.2*R,.09*R),'partyStar',{fine:true,sw:ln})}
 else if(id==='santahat'){const Hh=hatH(.95),b=[top.x,top.y+.1*R],hw=.82,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',[H(-hw,0),H(-.74,-.45),H(-.4,-.86),H(0,-1),H(.42,-.88),H(.74,-.5),H(hw,0)],'santaRed');
  const c=t=>{const m=1-t;return H(2*m*t*(-.5)+t*t*(-.58),m*m*(-.95)+2*m*t*(-1.02)+t*t*(-.5))},tip=c(1);
  poly('top',leaf(c,t=>(.26-.18*t)*g,10),'santaRed',{stroke:null});
  ell('top',tip[0],tip[1],ball(.17*R),ball(.17*R),0,'fur');
  pill('top',.95*g,0,Math.max(fl('line')*2,.12*R),'fur')}
 else if(id==='witchhat'){const Hh=hatH(1.5),b=[top.x,top.y+.04*R],H=(x,y)=>Q(x*g,y*Hh,b);
  ell('top',...Q(0,0,b),.95*g,Math.max(.12*R,fl('line')*2),A.lean,'witchHat');
  poly('top',[H(-.52,0),H(-.36,-.4),H(-.08,-.72),H(.1,-.82),H(.62,-1),H(.4,-.66),H(.34,-.45),H(.52,0)],'witchHat');
  poly('top',[H(-.5,-.1),H(.5,-.1),H(.45,-.3),H(-.42,-.3)],'witchBand',{stroke:null});
  poly('top',[H(-.12,-.06),H(.12,-.06),H(.12,-.34),H(-.12,-.34)],'gold',{sw:ln})}
 else if(id==='bunnyears'){const cm=!full,Hh=hatH(cm?1.9:1.45),b=[top.x,top.y+(cm?.1:.5)*R],H=(x,y)=>Q(x*g,y*Hh,b);
  // Below Ø28 the ears are taller (their base sits nearer the crown) and wider, so they show above the head at Ø18 and Ø20; the open size is unchanged.
  for(const sd of [-1,1]){const bend=sd>0?.9:0,c=t=>{const x=sd*(.4+.22*t)+bend*Math.pow(Math.max(0,t-.55),2)*1.2;return H(x,-t)},wm=Math.max((cm?.5:.3)*g,fl('span')/2),w=t=>wm*Math.pow(Math.sin(Math.PI*(.2+.8*t)),.8);
   poly('behind',leaf(c,w),'bunnyOuter');
   poly('behind',leaf(t=>c(.06+.74*t),t=>w(.06+.74*t)*.55),'bunnyInner',{stroke:null})}}
 else if(id==='beanie'){const Hh=hatH(.78),b=[top.x,top.y+.26*R],hw=.95,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',arcPts(0,0,hw,1,Math.PI,Math.PI*2,14).map(q=>H(q[0],q[1])),'beanieBody');
  for(const x of [-.5,0,.5])curve('top',[H(x*.9,-.15),H(x,-.62),H(x*.5,-.92)],'beanieCuff',ln*.9,{fine:true,a:.7});
  pill('top',.96*g,0,Math.max(.14*R,fl('span')/2),'beanieCuff');
  const t=H(0,-1.0);ell('top',t[0],t[1]-.04*R,ball(.17*R),ball(.17*R),0,'fur')}
 else if(id==='crown'){const Hh=hatH(.55),b=[top.x,top.y+.12*R],hw=.7,H=(x,y)=>Q(x*g,y*Hh,b);
  poly('top',[H(-hw,0),H(-hw,-.72),H(-.4,-.4),H(0,-1),H(.4,-.4),H(hw,-.72),H(hw,0)],'gold');
  poly('top',[H(-hw,0),H(hw,0),H(hw,-.22),H(-hw,-.22)],'goldDark',{stroke:null,a:.85});
  [[-hw,-.72,'gemA'],[0,-1,'gemB'],[hw,-.72,'gemC']].forEach(([x,y,r])=>{const q=H(x,y),gr=ball(.09*R);ell('top',q[0],q[1]+gr,gr,gr,0,r)})}
 // ── Glasses: they follow the eye frames and flatten with the face turn
 else if(id==='sunglasses'||id==='roundglasses'){const sun=id==='sunglasses',E=p.eye,lr=(sun?1.75:1.95)*E.w*R,lv=(sun?1.55:1.7)*Math.max(E.h,.85*E.w)*R,fr=Math.max(fl('rim'),sun?.06*R:.045*R),eyes=A.eyes.filter(e=>e.visible);
  for(const e of eyes){const rx=Math.max(lr*e.fx,fl('ball')),ry=Math.max(lv*e.fy,fl('ball'));
   if(sun){const rim=A.edge==='light'; // a dark head: the frame's dark would vanish, so a thin light rim (the edge role) outlines the lens
    ell('top',e.x,e.y,rx,ry,0,'lens',rim?{stroke:'edge',sw:ln,a:.93}:{stroke:'frame',sw:fr,a:.93});poly('top',[[e.x-rx*.5,e.y-ry*.15],[e.x-rx*.12,e.y-ry*.62],[e.x+rx*.12,e.y-ry*.62],[e.x-rx*.3,e.y+ry*.08]],'glint',{stroke:null,a:.55,fine:true})}
   else{ell('top',e.x,e.y,rx,ry,0,'glassTint',{stroke:'rim',sw:fr,a:.22});ell('top',e.x,e.y,rx,ry,0,null,{stroke:'rim',sw:fr});curve('top',arcPts(e.x,e.y,rx*.72,ry*.72,Math.PI*1.05,Math.PI*1.4,5),'glint',ln,{fine:true,a:.8})}}
  if(eyes.length===2){const [a,b]=eyes.sort((u,v)=>u.sd-v.sd),ax=a.x+Math.max(lr*a.fx,fl('ball')),bx=b.x-Math.max(lr*b.fx,fl('ball')),my=(a.y+b.y)/2;curve('top',[[ax,a.y],[(ax+bx)/2,my-(sun?.06:.1)*R],[bx,b.y]],sun?'frame':'rim',fr)}
  for(const e of eyes){const ox=e.x+e.sd*Math.max(lr*e.fx,fl('ball'));curve('top',[[ox,e.y-lv*e.fy*.2],[ox+e.sd*.3*R*e.fx,e.y-lv*e.fy*.05]],sun?'frame':'rim',fr)}}
 // ── Clips, the bow and the flower: at an ear base, turning with the ear
 else if(id==='bow'){const e=ear(1),cx=e.bx-.12*R,cy=e.by+.02*R,u=Math.max(R*.9,fl('span')*1.6),rot=e.rot*.6;
  for(const sd of [-1,1])ell('top',cx+sd*.3*u*Math.cos(rot),cy+sd*.3*u*Math.sin(rot),.3*u,.21*u,rot+sd*.35,'bowRed');
  poly('top',[[cx-.05*u,cy+.1*u],[cx-.2*u,cy+.55*u],[cx-.05*u,cy+.45*u]],'bowKnot',{fine:true});poly('top',[[cx+.05*u,cy+.1*u],[cx+.2*u,cy+.55*u],[cx+.05*u,cy+.45*u]],'bowKnot',{fine:true});
  ell('top',cx,cy,ball(.1*u),ball(.1*u),0,'bowKnot')}
 else if(id==='fishclip'){const e=ear(-1),cx=e.bx+.24*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7),rot=e.rot*.5;
  ell('top',cx,cy,.27*u,.13*u,rot,'fishBody');
  poly('top',[[cx+.25*u*Math.cos(rot),cy+.25*u*Math.sin(rot)],[cx+.45*u,cy-.14*u],[cx+.45*u,cy+.14*u]],'fishFin');
  ell('top',cx-.13*u,cy-.02*u,.025*u,.025*u,0,'lens',{stroke:null,fine:true})}
 else if(id==='flower'){const e=ear(1),cx=e.bx-.22*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7);
  for(let i=0;i<5;i++){const a=-Math.PI/2+i*TAU/5;ell('top',cx+Math.cos(a)*.15*u,cy+Math.sin(a)*.15*u,ball(.13*u),ball(.09*u),a,'petal')}
  ell('top',cx,cy,ball(.07*u),ball(.07*u),0,'gold',{sw:ln})}
   // Below Ø28 (the detail cut) the shrimp is simple and bold: one thick curled C, one fanned tail with three tips, both in the shrimp colour with the edge round them.
   else if(id==='shrimpclip'&&!full){const e=ear(-1),cx=e.bx+.24*R,cy=e.by+.12*R,u=Math.max(R,fl('span')*1.7),r=.3*u,sw=Math.max(.2*u,fl('span')/2),a0=Math.PI*.25,a1=Math.PI*1.45,
    tx=cx+r*Math.cos(a1),ty=cy+r*Math.sin(a1),td=[-Math.sin(a1),Math.cos(a1)],nd=[Math.cos(a1),Math.sin(a1)],L=.55*u,w=.22*u,at=(a,b)=>[tx+a*td[0]+b*nd[0],ty+a*td[1]+b*nd[1]];
    curve('top',arcPts(cx,cy,r,r,a0,a1,10),'edge',sw+2*ln);curve('top',arcPts(cx,cy,r,r,a0,a1,10),'shrimp',sw);
    poly('top',[at(0,w*.5),at(L*.9,w),at(L*.45,w*.35),at(L*1.1,0),at(L*.45,-w*.35),at(L*.9,-w),at(0,-w*.5)],'shrimp')}
   else if(id==='shrimpclip'){const e=ear(-1),cx=e.bx+.24*R,cy=e.by+.12*R,u=Math.max(R,fl('span')*1.7),r=.15*u,sw=Math.max(.12*u,fl('span')/2);
    // a curled, segmented body: four segments along a C, a fine dark joint between each pair
    for(let i=0;i<4;i++){const a0=Math.PI*(.25+i*.3);curve('top',arcPts(cx,cy,r,r,a0,a0+Math.PI*.3,4),'shrimp',sw)}
    for(let i=1;i<4;i++){const a=Math.PI*(.25+i*.3);curve('top',[[cx+.8*r*Math.cos(a),cy+.8*r*Math.sin(a)],[cx+1.25*r*Math.cos(a),cy+1.25*r*Math.sin(a)]],'shrimpDark',ln)}
    // a fanned tail: three spikes, between notches, off the end of the C
    const a1=Math.PI*1.45,tx=cx+r*Math.cos(a1),ty=cy+r*Math.sin(a1);
    poly('top',[[tx,ty],[tx+.2*u,ty-.14*u],[tx+.13*u,ty-.03*u],[tx+.26*u,ty],[tx+.13*u,ty+.03*u],[tx+.2*u,ty+.14*u]],'shrimp',{});
    poly('top',[[tx,ty],[tx+.2*u,ty-.12*u],[tx+.12*u,ty-.02*u]],'shrimpDark',{fine:true});
    // two small feelers from the head end of the C
    const a2=Math.PI*.25,hx=cx+r*Math.cos(a2),hy=cy+r*Math.sin(a2);
    curve('top',[[hx,hy],[hx+.1*u,hy-.16*u]],'shrimpDark',ln);
    curve('top',[[hx,hy],[hx+.04*u,hy-.2*u]],'shrimpDark',ln)}
 else if(id==='blossomclip'){const e=ear(1),cx=e.bx-.22*R,cy=e.by+.1*R,u=Math.max(R,fl('span')*1.7);
  for(const sd of [-1,1])ell('top',cx+sd*.2*u,cy+.14*u,ball(.13*u),ball(.06*u),sd*.6,'leaf');
  for(let i=0;i<5;i++){const a=-Math.PI/2+i*TAU/5;ell('top',cx+Math.cos(a)*.13*u,cy+Math.sin(a)*.13*u,ball(.11*u),ball(.11*u),a,i%2?'blossomDeep':'blossom')}
  ell('top',cx,cy,ball(.05*u),ball(.05*u),0,'gold',{stroke:null})}
 // ── Neck: over the collar
 else if(id==='scarf'||id==='bandana'||id==='bell'){
  const inw=(q,d)=>{const l=Math.hypot(q[0],q[1])||1;return[q[0]*(1-d/l),q[1]*(1-d/l)]},pts=A.chin.pts.map(q=>inw(q,.12*R));
  if(id==='scarf'){const wd=Math.max(.42*R,fl('span'));curve('neck',pts,'edge',wd+2*ln,{a:.9});curve('neck',pts,'scarfA',wd);curve('neck',pts.map(q=>inw(q,-.1*R)),'scarfB',Math.max(.07*R,fl('line')*1.5));curve('neck',pts.map(q=>inw(q,.1*R)),'scarfB',Math.max(.07*R,fl('line')*1.5));
   const t0=pts[5],tw=Math.max(.27*R,fl('span')),tl=.5*R;poly('neck',[[t0[0]-tw/2,t0[1]-.05*R],[t0[0]+tw/2,t0[1]-.05*R],[t0[0]+tw/2-.06*R,t0[1]+tl],[t0[0]-tw/2-.06*R,t0[1]+tl]],'scarfA');
   poly('neck',[[t0[0]-tw/2-.015*R,t0[1]+tl*.55],[t0[0]+tw/2-.045*R,t0[1]+tl*.55],[t0[0]+tw/2-.05*R,t0[1]+tl*.7],[t0[0]-tw/2-.02*R,t0[1]+tl*.7]],'scarfB',{stroke:null})}
  else if(id==='bandana'){const apex=[A.chin.front[0],Math.max(...pts.map(q=>q[1]))+.48*R];
   poly('neck',[...pts.map(q=>inw(q,-.06*R)),apex],'bandanaRed');
   const kn=pts[2];poly('neck',[[kn[0]-.12*R,kn[1]],[kn[0]-.4*R,kn[1]+.3*R],[kn[0]-.05*R,kn[1]+.26*R]],'bandanaRed',{});
   ell('neck',kn[0],kn[1],ball(.1*R),ball(.1*R),0,'bandanaRed');
   [[0,.34],[-.28,.18],[.28,.18]].forEach(([x,y])=>ell('neck',A.chin.front[0]+x*R,A.chin.front[1]+y*R,ball(.045*R),ball(.045*R),0,'white',{stroke:null,fine:true}))}
  else{const G=collarGeometry(p,s,D,o.collar,{dpr:A.dpr,detail:o.detail});let at=[A.neck.x,A.neck.y];
   if(G&&G.tag)at=[G.tag.x,G.tag.y+G.tag.r];else if(G&&G.band)at=G.band[G.band.length>>1];else if(G&&G.kerchief)at=G.kerchief.apex;
   const r=ball(.2*R);ell('neck',at[0],at[1]-.1*R,ball(.07*R),ball(.07*R),0,null,{stroke:'silver',sw:Math.max(ln*1.4,fl('line'))});
   ell('neck',at[0],at[1]+.12*R,r,r,0,'gold');curve('neck',[[at[0]-r*.7,at[1]+.1*R],[at[0]+r*.7,at[1]+.1*R]],'goldDark',ln,{fine:true});ell('neck',at[0],at[1]+.12*R+r*.55,ball(.04*R),ball(.04*R),0,'goldDark',{stroke:null,fine:true})}}
 return full?out:out.filter(sh=>!sh.fine)}
Object.assign(api,{outfitGeometry});
/**
 * A digest of a list of shapes that two implementations can compare within the contract's tolerance: how many shapes and points, the box that holds them (an ellipse counts as
 * its axis-aligned box and its centre as a point, a stroke's width is not counted) and the mean of every point's x and of every y (a sum would be too big for the fixture's 12 digits). An empty list digests to zeros.
 */
function outfitDigest(shapes){let pts=0,sx=0,sy=0,x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;
 const add=(x,y)=>{pts++;sx+=x;sy+=y;x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y)};
 for(const sh of shapes){if(sh.k==='ellipse'){add(sh.x,sh.y);x0=Math.min(x0,sh.x-sh.rx);x1=Math.max(x1,sh.x+sh.rx);y0=Math.min(y0,sh.y-sh.ry);y1=Math.max(y1,sh.y+sh.ry)}else for(const q of sh.pts)add(q[0],q[1])}
 return shapes.length?{n:shapes.length,pts,bbox:[x0,y0,x1,y1],mx:sx/pts,my:sy/pts}:{n:0,pts:0,bbox:[0,0,0,0],mx:0,my:0}}
Object.assign(api,{outfitDigest});
// @@END-OF-CORE: every later task inserts its section immediately above this line.
return api;
});
