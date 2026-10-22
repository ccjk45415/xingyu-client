package moe.cangku.reader;

/** Diagnostic frames only: exception messages can contain draft text or URLs. */
final class CrashReport {
    static String frames(Throwable failure){
        StringBuilder out=new StringBuilder();java.util.Set<Throwable> seen=java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<>());
        for(int depth=0;failure!=null&&depth<6&&seen.add(failure);depth++,failure=failure.getCause()){
            if(depth>0)out.append("Caused by: ");out.append(failure.getClass().getName()).append('\n');
            StackTraceElement[] frames=failure.getStackTrace();for(int i=0;i<Math.min(32,frames.length);i++)out.append("  at ").append(frames[i]).append('\n');
        }return out.toString();
    }
}
