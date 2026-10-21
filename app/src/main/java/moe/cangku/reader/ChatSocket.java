package moe.cangku.reader;

import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.charset.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.net.ssl.*;

/** Small RFC 6455 text transport. TLS hostname verification and the upgrade proof are mandatory. */
public final class ChatSocket implements Closeable {
    public static final class Failure extends IOException {
        public final int status;
        Failure(int status,String message){super(message);this.status=status;}
    }
    private final Socket socket;
    private final InputStream in;
    private final OutputStream out;
    private final SecureRandom random=new SecureRandom();
    // SSLSocket.close may send TLS close_notify. A tab click must never perform
    // that network write on Android's main thread, or wait behind a blocked read.
    private static final ExecutorService CLOSING=Executors.newCachedThreadPool(task->{Thread thread=new Thread(task,"chat-network-close");thread.setDaemon(true);return thread;});
    private final AtomicBoolean closeRequested=new AtomicBoolean();
    private volatile boolean closed;
    public ChatSocket(String origin,String channel,String token)throws Exception{
        this(origin,chatPath(channel,token),"Authorization: Bearer "+token+"\r\n",true);
    }
    private static String chatPath(String channel,String token)throws IOException{
        if(!ChatRules.channel(channel)||token==null||!token.matches("[a-f0-9]{64}"))throw new IOException("聊天身份无效");
        return "/ws?channel="+channel;
    }
    static ChatSocket announcements(String origin)throws Exception{return new ChatSocket(origin,"/announcements/live","",true);}
    private ChatSocket(String origin,String path,String authorization,boolean internal)throws Exception{
        URI uri=URI.create(ChatRules.server(origin));String host=uri.getHost();if(host==null)throw new IOException("聊天室地址无效");
        boolean tls="https".equals(uri.getScheme());int port=uri.getPort()>0?uri.getPort():tls?443:80;
        socket=tls?SSLSocketFactory.getDefault().createSocket():new Socket();
        try{
            socket.connect(new InetSocketAddress(host,port),12000);socket.setSoTimeout(75000);socket.setTcpNoDelay(true);
            if(tls){SSLSocket s=(SSLSocket)socket;SSLParameters p=s.getSSLParameters();p.setEndpointIdentificationAlgorithm("HTTPS");s.setSSLParameters(p);s.startHandshake();}
            in=socket.getInputStream();out=socket.getOutputStream();byte[] nonce=new byte[16];random.nextBytes(nonce);String key=Base64.getEncoder().encodeToString(nonce);
            String authority=host+((tls&&port==443)||(!tls&&port==80)?"":":"+port);
            String request="GET "+path+" HTTP/1.1\r\nHost: "+authority+"\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: "+key+"\r\n"+authorization+"User-Agent: XingyuChat/2\r\n\r\n";
            out.write(request.getBytes(StandardCharsets.US_ASCII));out.flush();
            ByteArrayOutputStream headers=new ByteArrayOutputStream();int end=0;
            while(end!=0x0d0a0d0a){int b=in.read();if(b<0)throw new EOFException("聊天室连接提前关闭");headers.write(b);if(headers.size()>16384)throw new IOException("服务器响应过大");end=(end<<8)|b;}
            String[] lines=headers.toString("US-ASCII").split("\r\n");
            if(!lines[0].matches("HTTP/1\\.[01] 101(?: .*)?")){if(lines[0].contains(" 503 "))throw new Failure(503,"聊天室已满或暂时不可用，请稍后再试");if(lines[0].contains(" 401 "))throw new Failure(401,"聊天身份已过期，请重新输入昵称");if(lines[0].contains(" 403 "))throw new Failure(403,"此聊天身份暂时不可用");throw new IOException("聊天室连接失败："+lines[0]);}
            Map<String,String> map=new HashMap<>();for(int i=1;i<lines.length;i++){int colon=lines[i].indexOf(':');if(colon>0)map.put(lines[i].substring(0,colon).toLowerCase(Locale.ROOT),lines[i].substring(colon+1).trim());}
            String proof=Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").getBytes(StandardCharsets.US_ASCII)));
            if(!proof.equals(map.get("sec-websocket-accept"))||!"websocket".equalsIgnoreCase(map.get("upgrade"))||!Arrays.asList(map.getOrDefault("connection","").toLowerCase(Locale.ROOT).split("\\s*,\\s*")).contains("upgrade")||map.containsKey("sec-websocket-extensions"))throw new IOException("聊天室连接校验失败");
        }catch(Exception e){try{socket.close();}catch(Exception ignored){}throw e;}
    }
    private int one()throws IOException{int b=in.read();if(b<0)throw new EOFException("聊天室连接已断开");return b;}
    public String read()throws IOException{
        ByteArrayOutputStream fragments=null;
        while(!closed){
            int first=one(),second=one(),op=first&15;boolean fin=(first&128)!=0;
            if((first&112)!=0||(second&128)!=0)throw new IOException("聊天室帧格式无效");
            long length=second&127;if(length==126)length=(one()<<8)|one();else if(length==127){length=0;for(int i=0;i<8;i++){int b=one();if(i==0&&b>0)throw new IOException("聊天室消息过大");length=(length<<8)|b;}}
            if(length>262144||length<0||(op>=8&&(!fin||length>125)))throw new IOException("聊天室消息过大");
            byte[] bytes=new byte[(int)length];int received=0;while(received<bytes.length){int n=in.read(bytes,received,bytes.length-received);if(n<0)throw new EOFException("聊天室消息不完整");received+=n;}
            if(op==8){int code=bytes.length>=2?((bytes[0]&255)<<8)|(bytes[1]&255):1000;if(code==4003)throw new Failure(401,"聊天身份已失效，请重新输入昵称");if(code==4001)throw new Failure(409,"聊天身份已在另一个连接进入");throw new EOFException("聊天室连接已关闭，请重新连接");}
            if(op==9){frame(10,bytes);continue;}if(op==10)continue;
            if(op==1){if(fragments!=null)throw new IOException("聊天室消息顺序异常");fragments=new ByteArrayOutputStream();}
            else if(op!=0||fragments==null)throw new IOException("聊天室消息类型不支持");
            if(fragments.size()+bytes.length>262144)throw new IOException("聊天室消息过大");fragments.write(bytes,0,bytes.length);
            if(fin){try{return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(fragments.toByteArray())).toString();}catch(CharacterCodingException e){throw new IOException("聊天室消息编码无效");}}
        }throw new EOFException("聊天室连接已关闭");
    }
    public void send(String text)throws IOException{byte[] bytes=text.getBytes(StandardCharsets.UTF_8);if(bytes.length>4096)throw new IOException("消息过大");frame(1,bytes);}
    private synchronized void frame(int opcode,byte[] bytes)throws IOException{
        if(closed)throw new IOException("连接已断开，请等待重连");out.write(128|opcode);int n=bytes.length;
        if(n<126)out.write(128|n);else{out.write(128|126);out.write(n>>>8);out.write(n);}
        byte[] mask=new byte[4];random.nextBytes(mask);out.write(mask);byte[] payload=bytes.clone();for(int i=0;i<n;i++)payload[i]^=mask[i%4];out.write(payload);out.flush();
    }
    static void closeTransport(Closeable transport){
        CLOSING.execute(()->{try{transport.close();}catch(IOException|RuntimeException ignored){}});
    }
    @Override public void close(){
        if(!closeRequested.compareAndSet(false,true))return;
        closed=true; // Invalidate immediately; physical TLS/socket cleanup is asynchronous.
        closeTransport(socket);
    }
}
