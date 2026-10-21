package moe.cangku.reader;

import com.google.zxing.*;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import java.util.*;

/** Offline QR only: no camera, network, navigation or account access. */
public final class QrDecoder {
    private QrDecoder(){}
    public static String decode(int[] pixels,int width,int height){
        if(width<1||height<1||(long)width*height>4194304||pixels==null||pixels.length!=(long)width*height)
            throw new IllegalArgumentException("图片尺寸不支持");
        LuminanceSource source=new RGBLuminanceSource(width,height,pixels);
        Map<DecodeHintType,Object> hints=new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.TRY_HARDER,Boolean.TRUE);
        hints.put(DecodeHintType.CHARACTER_SET,"UTF-8");
        for(int turn=0;turn<4;turn++){
            for(int inverted=0;inverted<2;inverted++){
                try{
                    String value=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(inverted==0?source:source.invert())),hints).getText();
                    if(value!=null&&!value.trim().isEmpty()&&value.length()<=8192)return value.trim();
                }catch(ReaderException ignored){}
            }
            source=source.rotateCounterClockwise();
        }
        return null;
    }
}
