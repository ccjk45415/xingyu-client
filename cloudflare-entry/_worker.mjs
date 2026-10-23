/** Pages ingress uses an internal service binding; no request goes to the workers.dev hostname. */
import releases from './release-index.mjs';

export async function releaseResponse(request, env, index = releases) {
  const url = new URL(request.url), name = url.pathname.substring('/releases/'.length);
  const release = Object.hasOwn(index, name) ? index[name] : null;
  if (!release) return null;
  if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', {status:405,headers:{Allow:'GET, HEAD'}});
  const headers = {
    'Content-Type': release.type,
    'Content-Length': String(release.size),
    'Content-Disposition': `attachment; filename="${name}"`,
    'Cache-Control': 'public, max-age=31536000, immutable, no-transform',
    'X-Content-Type-Options': 'nosniff',
    'Accept-Ranges': 'none',
    ETag: `"${release.sha256}"`,
  };
  if (request.headers.get('If-None-Match') === headers.ETag) return new Response(null,{status:304,headers:{ETag:headers.ETag}});
  if (request.method === 'HEAD') return new Response(null,{headers});
  let position = 0, reader = null;
  async function next() {
    const path = release.chunks[position++];
    if (!path || !/^\/release-chunks\/[a-f0-9]{64}\/\d+\.part$/.test(path)) throw new Error('Invalid release chunk');
    const response = await env.ASSETS.fetch(new Request(new URL(path,url.origin), {headers:{'Accept-Encoding':'identity'}}));
    if (response.status !== 200 || !response.body) throw new Error('Release temporarily unavailable');
    reader = response.body.getReader();
  }
  try { await next(); } catch { return new Response('Release temporarily unavailable',{status:503}); }
  const body = new ReadableStream({
    async pull(controller) {
      try {
        while (reader) {
          const item = await reader.read();
          if (!item.done) { controller.enqueue(item.value); return; }
          reader.releaseLock(); reader = null;
          if (position < release.chunks.length) await next();
        }
        controller.close();
      } catch (error) { controller.error(error); }
    },
    async cancel() { if (reader) await reader.cancel(); },
  });
  return new Response(body,{headers});
}

export default {
  async fetch(request,env){
    const url=new URL(request.url),path=url.pathname;
    if(path.startsWith('/ai/')||path==='/health'||path==='/ws'||path.startsWith('/v1/')||path.startsWith('/dm/')||path.startsWith('/media/')||path==='/announcements'||path.startsWith('/announcements/')||path==='/discovery'||path.startsWith('/discovery/'))return env.CHAT_SERVICE.fetch(request);
    if(path==='/updates/android')return env.ASSETS.fetch(new Request(new URL('/updates/android.json',url),request));
    if(path.startsWith('/releases/')) {
      const release = await releaseResponse(request,env);
      if (release) return release;
    }
    return env.ASSETS.fetch(request);
  }
};
