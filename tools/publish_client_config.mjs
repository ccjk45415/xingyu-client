/** Sign locally; only --publish writes to the service. Private keys never leave this machine. */
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {sign} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {DEFAULT_CLIENT_CONFIG,validateClientConfig,verifyConfigEnvelope} from '../cloudflare-chat/src/client-config.mjs';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args=process.argv.slice(2),publish=args.includes('--publish'),file=args.find(arg=>!arg.startsWith('--'));
const origin='https://xingyu-chat-ccjk45415.pages.dev';
const config=file?JSON.parse(await readFile(path.resolve(file),'utf8')):structuredClone(DEFAULT_CLIENT_CONFIG);
validateClientConfig(config);
let revision=0;
const old=await fetch(origin+'/client-config',{signal:AbortSignal.timeout(15000)});
if(old.ok)revision=(await verifyConfigEnvelope(await old.json())).revision;
else if(old.status!==404)throw new Error('无法确认当前配置版本，未发布');
const now=Date.now(),document={schema:1,product:'moe.cangku.xingyu',revision:revision+1,issued_at:new Date(now).toISOString(),expires_at:new Date(now+30*86400000).toISOString(),config};
const bytes=Buffer.from(JSON.stringify(document)),privateKey=await readFile(path.join(root,'.toolchain/client-config/signing-key.pem'));
const envelope={payload:bytes.toString('base64'),signature:sign(null,bytes,privateKey).toString('base64')};
await verifyConfigEnvelope(envelope);
await mkdir(path.join(root,'app/build'),{recursive:true});
await writeFile(path.join(root,'app/build/client-config-preview.json'),JSON.stringify({document,envelope},null,2)+'\n');
if(publish){
  const token=(await readFile(path.join(root,'.toolchain/announcements/admin.key'),'utf8')).trim();
  if(!/^[a-f0-9]{64}$/.test(token))throw new Error('管理凭据无效');
  const response=await fetch(origin+'/client-config/publish',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(envelope),signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw new Error('配置未发布：'+response.status);
}
console.log(JSON.stringify({revision:document.revision,published:publish,preview:'app/build/client-config-preview.json'}));
