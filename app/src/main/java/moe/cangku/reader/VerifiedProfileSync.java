package moe.cangku.reader;

import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Refreshes an already-consented identity; never enrolls or rotates a chat token. */
final class VerifiedProfileSync {
    private final MainActivity host;
    private final ChatVault vault;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private boolean busy,queued,refreshQueued,closed;
    private long checkedOwner,lastCheck;
    VerifiedProfileSync(MainActivity h){host=h;vault=new ChatVault(h,"privateIdentity","cangku.private.v1");}
    private boolean same(JSONObject a,JSONObject b){return a!=null&&b!=null&&a.optLong("id")==b.optLong("id")&&a.optString("nickname").equals(b.optString("nickname"))&&a.optString("avatar").equals(b.optString("avatar"));}
    void request(boolean refreshSite){
        if(closed||host.account()==null)return;
        final long owner=host.account().optLong("id");final String origin=ServiceEndpoint.origin();
        final JSONObject saved=vault.load(owner,origin);if(saved==null||saved.optJSONObject("user")==null)return;
        final String token=saved.optString("token");if(!token.matches("[a-f0-9]{64}"))return;
        try{if(java.time.Instant.parse(saved.optString("expires_at")).toEpochMilli()<=System.currentTimeMillis())return;}catch(Exception e){return;}
        boolean changed=!same(host.account(),saved.optJSONObject("user"));
        if(!changed&&(!refreshSite||checkedOwner==owner&&System.currentTimeMillis()-lastCheck<60000))return;
        if(busy){queued=true;refreshQueued|=refreshSite;return;}
        busy=true;final ApiClient site=host.client();final String local=host.account().toString();
        worker.execute(()->{
            JSONObject website=null,verified=null;String error=null;
            try{
                website=refreshSite?site.get("auth/me",ApiClient.params("include","roles,permissions,meta")).getJSONObject("data"):new JSONObject(local);
                if(website.optLong("id")!=owner)throw new java.io.IOException("账号已切换");
                if(!same(website,saved.optJSONObject("user"))){
                    verified=site.syncMessagingProfile(owner,token).getJSONObject("user");
                    // Let the hub update current names and notify both channels, without a message.
                    new ChatClient(origin).request("/v1/me",null,token,false);
                }
            }catch(Exception e){error=e.getMessage()==null?"连接失败":e.getMessage();}
            final JSONObject profile=website,canonical=verified;final String failure=error;
            main.post(()->{
                if(closed)return;
                boolean retry=queued,refresh=refreshQueued;queued=refreshQueued=false;busy=false;
                JSONObject current=vault.load(owner,origin);
                if(host.account()!=null&&host.account().optLong("id")==owner&&current!=null&&token.equals(current.optString("token"))){
                    try{
                        if(canonical!=null){current.put("user",canonical);vault.save(owner,origin,current);host.chatProfileChanged(canonical);}
                        if(failure==null){checkedOwner=owner;lastCheck=System.currentTimeMillis();if(!retry&&profile!=null)host.updateAccount(profile);}
                        else if(changed)host.toast("聊天资料同步失败："+failure+"；重新进入聊天室可重试");
                    }catch(Exception e){host.toast("聊天资料未能保存，请重新进入聊天室重试");}
                }
                if(retry)request(refresh);
            });
        });
    }
    void close(){closed=true;worker.shutdownNow();main.removeCallbacksAndMessages(null);}
}
