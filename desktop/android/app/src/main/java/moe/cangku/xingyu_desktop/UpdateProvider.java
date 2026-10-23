package moe.cangku.xingyu_desktop;

import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;

/** Shares exactly one verified APK with the system installer, read-only. */
public final class UpdateProvider extends ContentProvider {
    public boolean onCreate(){return true;}
    private File apk(Uri uri)throws FileNotFoundException{
        if(!"content".equals(uri.getScheme())||!(getContext().getPackageName()+".updates").equals(uri.getAuthority())||!"/apk".equals(uri.getPath())||uri.getQuery()!=null||uri.getFragment()!=null)throw new FileNotFoundException();
        File f=new File(getContext().getCacheDir(),"updates/verified.apk");if(!f.isFile())throw new FileNotFoundException();return f;
    }
    public String getType(Uri uri){return "application/vnd.android.package-archive";}
    public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{if(!"r".equals(mode))throw new FileNotFoundException();return ParcelFileDescriptor.open(apk(uri),ParcelFileDescriptor.MODE_READ_ONLY);}
    public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort){try{File f=apk(uri);String[] cols=projection==null?new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}:projection;MatrixCursor c=new MatrixCursor(cols);Object[] values=new Object[cols.length];for(int i=0;i<cols.length;i++)values[i]=cols[i].equals(OpenableColumns.DISPLAY_NAME)?"xingyu-update.apk":cols[i].equals(OpenableColumns.SIZE)?f.length():null;c.addRow(values);return c;}catch(Exception e){return null;}}
    public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException();}
    public int delete(Uri uri,String s,String[] a){throw new UnsupportedOperationException();}
    public int update(Uri uri,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
}

