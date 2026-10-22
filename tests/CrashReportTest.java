package moe.cangku.reader;

public final class CrashReportTest {
    public static void main(String[] args){
        Throwable inner=new IllegalArgumentException("secret-token and draft body");Throwable outer=new IllegalStateException("private URL",inner);
        String report=CrashReport.frames(outer);
        if(!report.contains("IllegalStateException")||!report.contains("IllegalArgumentException")||!report.contains("CrashReportTest"))throw new AssertionError("missing frames or cause");
        if(report.contains("secret-token")||report.contains("draft body")||report.contains("private URL"))throw new AssertionError("exception message leaked");
        Throwable a=new RuntimeException(),b=new RuntimeException(a);a.initCause(b);if(CrashReport.frames(a).length()>16000)throw new AssertionError("cause cycle not bounded");
        System.out.println("PASS diagnostic cause/frame preservation, message privacy, cause-cycle bound");
    }
}
