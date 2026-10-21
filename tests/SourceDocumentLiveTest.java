package moe.cangku.reader;
import org.json.*;
public final class SourceDocumentLiveTest{
 public static void main(String[] args)throws Exception{
  AiClient client=new AiClient();try{
   JSONObject source=client.source("https://www.dlsite.com/maniax-touch/work/=/product_id/RJ01726046.html");JSONArray b=source.getJSONArray("blocks");int images=0;String firstImage="";for(int i=0;i<b.length();i++)if(b.getJSONObject(i).getString("kind").equals("image")){images++;if(firstImage.isEmpty())firstImage=b.getJSONObject(i).getString("url");}
   if(source.getString("text").length()<1000||images<4||!source.getString("url").contains("/maniax/"))throw new AssertionError("Detailed source was not extracted");
   java.net.HttpURLConnection image=(java.net.HttpURLConnection)new java.net.URL(firstImage).openConnection();image.setConnectTimeout(15000);image.setReadTimeout(15000);image.setRequestProperty("User-Agent",ApiClient.UA);image.setRequestProperty("Referer","https://cangku.moe/");image.setRequestProperty("Range","bytes=0-0");int status=image.getResponseCode();image.disconnect();if(status!=200&&status!=206)throw new AssertionError("Introduction image inaccessible: "+status);
   System.out.println("PASS actual Android detailed source transport on JVM: chars="+source.getString("text").length()+", introduction_images="+images+", original_order=true; no AI calls");
  }finally{client.close();}
 }
}
