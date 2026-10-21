export const LIMITS=Object.freeze({online:300,length:300,minute:15,dayUser:200,dayAll:10000,days:7});
export const roomOK=r=>r==='1'||r==='2';
// Match Cloudflare's UTC quota window (08:00 in Shanghai).
export const dayKey=ms=>Math.floor(ms/86400_000);
export const dayStart=ms=>dayKey(ms)*86400_000;
const invalid=message=>Object.assign(new Error(message),{status:400});
export function nickname(value){
  if(typeof value!=='string')throw invalid('请输入聊天昵称');
  const s=value.trim();if(!s||[...s].length>24||/[\x00-\x1f\x7f]/u.test(s))throw invalid('昵称应为1–24字，不能包含换行或控制字符');return s;
}
export function text(value){
  if(typeof value!=='string')throw invalid('消息格式不正确');
  const s=value.trim();if(!s||[...s].length>LIMITS.length||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/u.test(s))throw invalid('消息应为1–300字');return s;
}
export const nonceOK=s=>typeof s==='string'&&/^[a-zA-Z0-9_-]{16,80}$/.test(s);
export function limitReason({last=0,minute=0,user=0,all=0},now){
  if(all>=LIMITS.dayAll)return '今日聊天室消息额度已用完，下次北京时间08:00恢复';
  if(user>=LIMITS.dayUser)return '你今日已发送200条消息，下次北京时间08:00恢复';
  if(now-last<3000)return '发送太快，请稍等3秒';
  if(minute>=LIMITS.minute)return '每分钟最多发送15条消息，请稍后再试';
  return '';
}
