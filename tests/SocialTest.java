import moe.cangku.reader.SocialRules;
public class SocialTest {
    private static int count;
    private static void check(boolean ok){count++;if(!ok)throw new AssertionError("Social check "+count);}
    public static void main(String[] args){
        check(SocialRules.rootId(11,0)==11);
        check(SocialRules.rootId(15,11)==11);
        check(SocialRules.ownComment(7,7));
        check(!SocialRules.ownComment(7,8));
        check(!SocialRules.ownComment(0,0));
        check(SocialRules.notificationPostId("post",42,0)==42);
        check(SocialRules.notificationPostId("comment",11,42)==42);
        check(SocialRules.notificationPostId("user",7,42)==0);
        check(SocialRules.notificationCommentId("reply","post",42,11)==11);
        check(SocialRules.notificationCommentId("reply","comment",11,15)==15);
        check(SocialRules.notificationCommentId("vote","comment",11,0)==11);
        check(SocialRules.notificationCommentId("vote","post",42,0)==0);
        check(SocialRules.notificationCommentId("reply","user",7,15)==0);
        check(SocialRules.notificationCommentId("unknown","comment",11,15)==0);
        System.out.println("SOCIAL_RULES_PASS "+count);
    }
}
