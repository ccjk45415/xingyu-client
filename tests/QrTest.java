import moe.cangku.reader.*;
import com.google.zxing.*;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.File;
import java.util.*;

public class QrTest {
    static int count;
    static void check(boolean v){count++;if(!v)throw new AssertionError("QR/editor check "+count);}
    static int[] pixels(BitMatrix matrix,boolean inverted,int turn){
        int n=matrix.getWidth();int[] data=new int[n*n];
        for(int y=0;y<n;y++)for(int x=0;x<n;x++){
            int tx=x,ty=y;for(int t=0;t<turn;t++){int temp=tx;tx=n-1-ty;ty=temp;}
            data[ty*n+tx]=(matrix.get(x,y)^inverted)?0xff000000:0xffffffff;
        }return data;
    }
    public static void main(String[] args)throws Exception{
        String[] payloads={"https://example.com/download?a=1&b=2#qr","https://example.com/资源?名称=星屿","二维码内的普通文字","javascript:alert(1)","https://cangku.moe/archives/123"};
        for(int i=0;i<payloads.length;i++){
            Map<EncodeHintType,Object> hints=new EnumMap<>(EncodeHintType.class);hints.put(EncodeHintType.CHARACTER_SET,"UTF-8");
            BitMatrix matrix=new QRCodeWriter().encode(payloads[i],BarcodeFormat.QR_CODE,320,320,hints);
            for(int turn=0;turn<4;turn++)for(boolean inv:new boolean[]{false,true})check(payloads[i].equals(QrDecoder.decode(pixels(matrix,inv,turn),320,320)));
            if(i<2||i==4){BufferedImage image=new BufferedImage(320,320,BufferedImage.TYPE_INT_RGB);image.setRGB(0,0,320,320,pixels(matrix,false,0),0,320);File target=new File(args[0],i==0?"qr-link.png":i==1?"qr-cjk.png":"qr-internal.png");target.getParentFile().mkdirs();ImageIO.write(image,"PNG",target);}
        }
        int[] white=new int[320*320];Arrays.fill(white,0xffffffff);check(QrDecoder.decode(white,320,320)==null);
        try{QrDecoder.decode(new int[1],2048,2048);throw new AssertionError("Bad array accepted");}catch(IllegalArgumentException expected){count++;}
        String code="#include <iostream>\nint main() {\n  std::cout << \"A & B\";\n}";
        String html=EditorHints.codeBlock("cpp",code);check(html.contains("language-cpp"));check(html.contains("&lt;iostream&gt;"));check(html.contains("&amp;"));check(!html.contains("<iostream>"));check(html.contains("\n  std"));
        String display=ReaderContent.nativeCodeBlocks(html);check(display.contains("<tt>"));check(display.contains("<br>&nbsp;&nbsp;std"));check(display.contains("&lt;iostream&gt;"));
        check(!UrlPolicy.canOpen(payloads[3]));
        try{EditorHints.codeBlock("cpp\" onclick=\"bad",code);throw new AssertionError("language accepted");}catch(IllegalArgumentException expected){count++;}
        check(EditorHints.ITEMS.length>=15&&EditorHints.LANGUAGES.length==17);
        System.out.println("PASS "+count+" QR and editor checks; cross-language fixtures written");
    }
}
