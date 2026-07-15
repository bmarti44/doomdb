import crypto from 'node:crypto';

export const WIDTH=320,HEIGHT=200,HUD_Y=168,TRANSPARENT=-1;
export const sha256=b=>crypto.createHash('sha256').update(b).digest('hex');
const at=(x,y)=>x*HEIGHT+y;

export function makeWorld(mutation={}){
  const p=Buffer.alloc(WIDTH*HEIGHT);
  for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)p[at(x,y)]=mutation.blankWorld?0:(x*3+y*5+(y>=100?17:0))&127;
  return p;
}

export function blit(dst,patch,x0,y0,mutation={}){
  for(let y=0;y<patch.height;y++)for(let x=0;x<patch.width;x++){
    const c=patch.pixels[y*patch.width+x],x2=x0+x,y2=y0+y;
    if(x2<0||x2>=WIDTH||y2<0||y2>=HEIGHT)continue;
    if(c===TRANSPARENT&&!mutation.opaqueTransparency)continue;
    dst[at(x2,y2)]=c===TRANSPARENT?0:c;
  }
}

const glyphs={
 '0':['111','101','101','101','111'],'1':['010','110','010','010','111'],'2':['111','001','111','100','111'],
 '3':['111','001','111','001','111'],'4':['101','101','111','001','001'],'5':['111','100','111','001','111'],
 '6':['111','100','111','101','111'],'7':['111','001','010','010','010'],'8':['111','101','111','101','111'],
 '9':['111','101','111','001','111'],'A':['010','101','111','101','101'],'E':['111','100','110','100','111'],
 'G':['111','100','101','101','111'],'I':['111','010','010','010','111'],'K':['101','101','110','101','101'],
 'L':['100','100','100','100','111'],'M':['10001','11011','10101','10101','10101'],'N':['1001','1101','1011','1001','1001'],
 'O':['111','101','101','101','111'],'P':['110','101','110','100','100'],'R':['110','101','110','101','101'],
 'S':['111','100','111','001','111'],'T':['111','010','010','010','010'],'U':['101','101','101','101','111'],
 'V':['101','101','101','101','010'],'W':['10101','10101','10101','10101','01010'],'Y':['101','101','010','010','010'],
 ':':['0','1','0','1','0'],'%':['1001','0010','0100','1000','1001'],'-':['000','000','111','000','000'],' ':['0','0','0','0','0']};

export function drawText(dst,text,x,y,color=250,mutation={}){
  let cx=x;
  for(const ch of String(text).toUpperCase()){
    const rows=glyphs[ch]??glyphs[' '],w=rows[0].length;
    for(let gy=0;gy<5;gy++)for(let gx=0;gx<w;gx++)if(rows[gy][gx]==='1'){
      const px=cx+gx,py=y+gy;if(px>=0&&px<WIDTH&&py>=0&&py<HEIGHT)dst[at(px,py)]=mutation.textColor??color;
    }
    cx+=w+1;
  }
  return {x0:x,y0:y,x1:cx-2,y1:y+4};
}

function line(dst,x0,y0,x1,y1,c,mutation={}){
  if(mutation.omitAutomapLines)return;
  let dx=Math.abs(x1-x0),sx=x0<x1?1:-1,dy=-Math.abs(y1-y0),sy=y0<y1?1:-1,e=dx+dy;
  for(;;){if(x0>=0&&x0<WIDTH&&y0>=0&&y0<HUD_Y)dst[at(x0,y0)]=c;if(x0===x1&&y0===y1)break;const e2=2*e;if(e2>=dy){e+=dy;x0+=sx}if(e2<=dx){e+=dx;y0+=sy}}
}

function hud(dst,state,assets,mutation={}){
  if(mutation.noHud)return;
  blit(dst,assets.status,0,HUD_Y,mutation);
  drawText(dst,String(state.health),18,184,250,mutation);drawText(dst,'%',32,184,250,mutation);
  drawText(dst,String(state.ammo),274,184,250,mutation);
  const keys=[state.blueKey,state.yellowKey,state.redKey];keys.forEach((v,i)=>{if(v)blit(dst,assets.keys[i],238+i*9,184,mutation)});
}

export function compose(fixture,state,mutation={}){
  const out=makeWorld(mutation),a=fixture.assets;
  if(state.mode==='AUTOMAP'){
    out.fill(mutation.automapBackground??0,0,WIDTH*HEIGHT);
    const visible=fixture.geometry.filter(g=>!g.hidden||state.automapState==='FULL');
    for(const g of visible)line(out,g.x1,g.y1,g.x2,g.y2,g.hidden?96:200,mutation);
    line(out,156,82,164,86,250,mutation);line(out,164,86,156,90,250,mutation);
  } else if(state.mode==='INTERMISSION'){
    out.fill(4);blit(out,a.intermission,0,0,mutation);
    drawText(out,'LEVEL COMPLETE',102,36,250,mutation);drawText(out,`KILLS: ${state.kills}%`,88,82,250,mutation);
    drawText(out,`ITEMS: ${state.items}%`,88,98,250,mutation);drawText(out,`SECRETS: ${state.secrets}%`,88,114,250,mutation);
  } else {
    const weapon=mutation.wrongWeapon?a.weapons.PISTOL:a.weapons[state.weapon];
    blit(out,weapon,Math.floor((WIDTH-weapon.width)/2),HUD_Y-weapon.height+(mutation.weaponShift??0),mutation);
    if(state.mode==='MENU'){
      blit(out,a.menuTitle,112,20,mutation);drawText(out,'NEW GAME',126,66,state.menuSelection===0?250:180,mutation);
      drawText(out,'OPTIONS',126,82,state.menuSelection===1?250:180,mutation);drawText(out,'QUIT GAME',126,98,state.menuSelection===2?250:180,mutation);
    }
    if(state.paused)blit(out,a.pause,132+(mutation.pauseShift??0),76,mutation);
  }
  hud(out,state,a,mutation);
  return out;
}

export function changedRegion(a,b){
  const pts=[];for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)if(a[at(x,y)]!==b[at(x,y)])pts.push([x,y]);
  if(!pts.length)return null;return {count:pts.length,x0:Math.min(...pts.map(p=>p[0])),x1:Math.max(...pts.map(p=>p[0])),y0:Math.min(...pts.map(p=>p[1])),y1:Math.max(...pts.map(p=>p[1]))};
}

export function frameRows(pixels){const rows=[];for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)rows.push({column:x,row:y,cidx:pixels[at(x,y)]});return rows;}
