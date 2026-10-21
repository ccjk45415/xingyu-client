package moe.cangku.reader;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Regression tests for navigation while network reads and TLS cleanup are active. */
public final class ChatLifecycleTest {
    private static int checks;
    private static void check(boolean ok,String reason){checks++;if(!ok)throw new AssertionError(reason);}
    public static void main(String[] args)throws Exception{
        Thread uiThread=Thread.currentThread();
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),finished=new CountDownLatch(1);
        AtomicReference<Thread> closerThread=new AtomicReference<>();
        // A TLS provider may perform close_notify I/O or block inside close().
        // Simulate both without disabling certificates or touching the public service.
        long start=System.nanoTime();
        ChatSocket.closeTransport(()->{
            closerThread.set(Thread.currentThread());entered.countDown();
            try{release.await(3,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}
            finished.countDown();
            throw new IllegalStateException("Simulated TLS provider close failure");
        });
        check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start)<500,"Navigation blocked on TLS shutdown");
        check(entered.await(2,TimeUnit.SECONDS),"Cleanup did not start");
        check(closerThread.get()!=uiThread,"TLS close ran on the UI caller");
        // One blocked TLS shutdown must not prevent a newly detached connection
        // from closing (e.g. rapid channel one -> two -> home navigation).
        CountDownLatch independent=new CountDownLatch(1);ChatSocket.closeTransport(independent::countDown);
        check(independent.await(2,TimeUnit.SECONDS),"Cleanup blocked behind another TLS close");
        release.countDown();check(finished.await(2,TimeUnit.SECONDS),"Cleanup did not finish");

        AtomicReference<Throwable> serverFailure=new AtomicReference<>();
        CountDownLatch eof=new CountDownLatch(1);
        try(ServerSocket server=new ServerSocket(0,1,InetAddress.getLoopbackAddress())){
            Thread peer=new Thread(()->{
                try(Socket accepted=server.accept()){
                    accepted.setSoTimeout(4000);ByteArrayOutputStream request=new ByteArrayOutputStream();int end=0;
                    while(end!=0x0d0a0d0a){int b=accepted.getInputStream().read();if(b<0)throw new EOFException();request.write(b);end=(end<<8)|b;}
                    String key=null;for(String line:request.toString("US-ASCII").split("\r\n"))if(line.startsWith("Sec-WebSocket-Key: "))key=line.substring(19).trim();
                    if(key==null)throw new IOException("No client handshake key");
                    String proof=Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").getBytes(StandardCharsets.US_ASCII)));
                    accepted.getOutputStream().write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+proof+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));accepted.getOutputStream().flush();
                    if(accepted.getInputStream().read()!=-1)throw new IOException("Unexpected data after close");
                    eof.countDown();
                }catch(Throwable failure){serverFailure.set(failure);}
            },"local-chat-peer");peer.setDaemon(true);peer.start();
            ChatSocket chat=new ChatSocket("http://127.0.0.1:"+server.getLocalPort(),"1","a".repeat(64));
            CountDownLatch readStarted=new CountDownLatch(1),readStopped=new CountDownLatch(1);
            Thread reader=new Thread(()->{readStarted.countDown();try{chat.read();serverFailure.set(new AssertionError("Read returned after shutdown"));}catch(IOException expected){}finally{readStopped.countDown();}},"old-room-reader");reader.setDaemon(true);reader.start();
            check(readStarted.await(1,TimeUnit.SECONDS),"Read did not start");
            check(!readStopped.await(100,TimeUnit.MILLISECONDS),"Read was not waiting for network data before navigation");
            start=System.nanoTime();chat.close();chat.close();
            check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start)<500,"Socket close blocked the navigation caller");
            boolean sendDenied=false;try{chat.send("stale message");}catch(IOException expected){sendDenied=true;}
            check(sendDenied,"Detached socket still accepted a message");
            check(readStopped.await(3,TimeUnit.SECONDS),"Old room read did not stop");
            check(eof.await(3,TimeUnit.SECONDS),"Peer did not observe socket cleanup");
            peer.join(3000);check(serverFailure.get()==null,"Local transport failed: "+serverFailure.get());
        }
        check(!ChatRules.current(1,2,"1","1"),"Old same-room callbacks survived reconnect");
        check(!ChatRules.current(1,1,"1","2"),"Old channel callbacks survived switch");
        System.out.println("PASS chat navigation lifecycle: "+checks+" checks; background TLS cleanup, rapid detach, blocked read interruption, stale sends/callbacks rejected");
    }
}
