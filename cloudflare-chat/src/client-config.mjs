const enc=new TextEncoder();
export const CONFIG_PUBLIC_KEY='+G+zF1gen2I8ziXBE14QxbGyXJKqS8a8R/ibO0g4qSk=';
export const DEFAULT_CLIENT_CONFIG=Object.freeze({
  home:{mobile_height:124,desktop_height:140,banner_order:['announcement','discovery'],card_density:'normal'},
  labels:{announcement:'公告',discovery:'发现',checkin:'签到'},
  features:{checkin:true,cloud_checkin:true,pinned:true},
});
function fail(){throw Object.assign(new Error('在线配置格式或签名无效'),{status:400});}
function exact(value,keys){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||Object.keys(value).some(k=>!keys.includes(k)))fail();}
export function validateClientConfig(value){
  exact(value,['home','labels','features']);
  const home=value.home, labels=value.labels,features=value.features;
  exact(home,['mobile_height','desktop_height','banner_order','card_density']);
  exact(labels,['announcement','discovery','checkin']);exact(features,['checkin','cloud_checkin','pinned']);
  if(!Number.isInteger(home.mobile_height)||home.mobile_height<100||home.mobile_height>180||!Number.isInteger(home.desktop_height)||home.desktop_height<100||home.desktop_height>200)fail();
  if(!Array.isArray(home.banner_order)||home.banner_order.length!==2||new Set(home.banner_order).size!==2||home.banner_order.some(v=>!['announcement','discovery'].includes(v)))fail();
  if(!['normal','compact'].includes(home.card_density))fail();
  for(const key of ['announcement','discovery','checkin'])if(typeof labels[key]!=='string'||!labels[key].trim()||[...labels[key]].length>16||/[\x00-\x1f\x7f]/.test(labels[key]))fail();
  if(Object.keys(features).length!==3||Object.values(features).some(v=>typeof v!=='boolean'))fail();
  return value;
}
export function base64Bytes(value){
  if(typeof value!=='string'||value.length>48000||!/^[A-Za-z0-9+/]+={0,2}$/.test(value))fail();
  try{return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}catch{fail();}
}
export async function verifyConfigEnvelope(envelope,{publicKey=CONFIG_PUBLIC_KEY,now=Date.now()}={}){
  exact(envelope,['payload','signature']);
  const bytes=base64Bytes(envelope.payload),signature=base64Bytes(envelope.signature);
  if(bytes.length>32000||signature.length!==64)fail();
  const key=await crypto.subtle.importKey('raw',base64Bytes(publicKey),'Ed25519',false,['verify']);
  if(!await crypto.subtle.verify('Ed25519',key,signature,bytes))fail();
  let document;try{document=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{fail();}
  exact(document,['schema','product','revision','issued_at','expires_at','config']);
  const issued=Date.parse(document.issued_at),expires=Date.parse(document.expires_at);
  if(document.schema!==1||document.product!=='moe.cangku.xingyu'||!Number.isSafeInteger(document.revision)||document.revision<1||!Number.isFinite(issued)||issued>now+300000||!Number.isFinite(expires)||expires<=now||expires<=issued||expires-issued>31*86400000)fail();
  validateClientConfig(document.config);
  return document;
}
