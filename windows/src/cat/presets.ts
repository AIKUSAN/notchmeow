// The cats: Shrimpy, Momo and the fourteen extra coats, and each one's kitten.
// A port of the presets section of design/prototype/cat-core.js (the tie-breaker). Units are R, the head radius.
//
// The ids are frozen contract values (they are stored in settings), in this order:
// shrimpy, momo, ginger, midnight, latte, patches, blue, snow, oreo, mocha, silver, cloud,
// leo, button, puff, noodle. `voice` is a pitch offset in semitones for sub-project C:
// Shrimpy -1, Momo +1, the extra coats 0, every kitten +3.

import { own } from "./base.ts";
import type { CatPreset, Patch } from "./types.ts";

/** What a coat may set on top of the shorthair template: any field, and the nested ones in part. */
type CoatSpec = Partial<Omit<CatPreset, "ear" | "eye" | "whisk2">> & {
  name: string;
  ear?: Partial<CatPreset["ear"]>;
  eye?: Partial<CatPreset["eye"]>;
  whisk2?: Partial<CatPreset["whisk2"]>;
};

export const PRESETS: Record<string, CatPreset> = {
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

/** The shorthair template for the extra coats; each cat only overrides what differs. */
function makeCat(o: CoatSpec): CatPreset {
  const base = {
    voice: 0, coat: "solid" as const, rx: 1.12, ry: 0.9, n: 2.2, fluff: 0, ruff: null, earSpread: 0.8,
    ear: { h: 0.8, bw: 0.5, rot: 0.46, tip: 0.09, tuft: 0, cx: 0.7 },
    noseW: 0.2, noseH: 0.13, nosePh: -0.42,
    whisk2: { rows: 3, cols: 2, x0: 0.16, dx: 0.065, y0: -0.01, dy: 0.06, slope: 0.02, dot: 0.014, wcols: [0, 1], a0: -0.1, da: 0.2, len: 1.32, dl: 0.1, droop: 0.1, w: 0.021, alpha: 0.95, brow: 2 },
    eye: { th: 0.43, ph: -0.02, w: 0.19, h: 0.17, round: 1 },
    pupil0: 0.2, blushAt: [0.55, 0.25] as [number, number],
  };
  const r = { ...base, ...o, ear: { ...base.ear, ...(o.ear || {}) }, eye: { ...base.eye, ...(o.eye || {}) }, whisk2: { ...base.whisk2, ...(o.whisk2 || {}) } };
  return r as CatPreset;
}

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
   ...[[-.6,-.42,.4,1],[.62,-.4,-.3,2],[-.34,-.76,.2,3],[.36,-.76,-.2,4],[-.84,.36,.3,5],[.86,.36,-.3,6],[-.55,.6,.2,7],[.57,.6,-.2,8]].flatMap(([x,y,r,sd]): Patch[]=>[[x,y,.12,.095,r,'#4A2A14',sd],[x,y,.06,.045,r,'#9C5E24',sd]])],
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
const MORE = ['ginger','midnight','latte','patches','blue','snow','oreo','mocha','silver','cloud','leo','button','puff','noodle'];

/** Kittens keep the parent's coat; rounder head, bigger eyes and ears, shorter muzzle. */
export function kittenOf(p: CatPreset): CatPreset {
  const k: CatPreset = JSON.parse(JSON.stringify(p));
  k.kitten = true; k.base = p.name; k.label = p.label + ' kitten'; k.voice = 3;
  k.rx = p.rx * .97; k.ry = p.ry * 1.02; k.n = 2.05; k.ear.h *= 1.12; k.ear.bw *= 1.06; k.ear.tuft = 0;
  k.eye.w *= 1.2; k.eye.h *= 1.32; k.eye.round = 1; k.eye.th += .02; k.pupil0 = Math.max(p.pupil0, .18);
  k.nosePh = p.nosePh + .08; k.noseW *= .85; k.noseH *= .85; k.whisk2.len *= .7; k.whisk2.brow = 1;
  if (k.ruff) { k.ruff.rx *= .94; k.ruff.ry *= .92 }
  return k;
}

/** The cat ids, frozen and in order: Shrimpy first, Momo second, then the extra coats. */
export const CAT_IDS: readonly string[] = ['shrimpy', 'momo', ...MORE];
export const DEFAULT_CAT = 'shrimpy';

/** A stored cat id to its preset. An unknown id (or anything that is not a string) falls back to Shrimpy. */
export const catById = (id: unknown): CatPreset => (typeof id === 'string' && own(PRESETS, id) ? PRESETS[id] : PRESETS[DEFAULT_CAT]);
