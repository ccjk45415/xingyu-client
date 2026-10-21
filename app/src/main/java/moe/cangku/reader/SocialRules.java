package moe.cangku.reader;

/** Pure routing and ownership rules shared by native website social screens. */
public final class SocialRules {
    private SocialRules(){}
    public static long rootId(long id,long parent){return parent>0?parent:id;}
    public static boolean ownComment(long current,long author){return current>0&&current==author;}
    public static long notificationPostId(String subjectType,long subject,long post){return "post".equals(subjectType)?subject:"comment".equals(subjectType)?post:0;}
    public static long notificationCommentId(String action,String subjectType,long subject,long causer){
        if("reply".equals(action))return ("post".equals(subjectType)||"comment".equals(subjectType))?causer:0;
        return "vote".equals(action)&&"comment".equals(subjectType)?subject:0;
    }
}
