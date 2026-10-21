/** Pages ingress uses an internal service binding; no request goes to the workers.dev hostname. */
export default {
  async fetch(request,env){
    const url=new URL(request.url),path=url.pathname;
    if(path==='/health'||path==='/ws'||path.startsWith('/v1/')||path.startsWith('/dm/')||path.startsWith('/media/')||path==='/announcements'||path.startsWith('/announcements/'))return env.CHAT_SERVICE.fetch(request);
    if(path==='/updates/android')return env.ASSETS.fetch(new Request(new URL('/updates/android.json',url),request));
    return env.ASSETS.fetch(request);
  }
};
