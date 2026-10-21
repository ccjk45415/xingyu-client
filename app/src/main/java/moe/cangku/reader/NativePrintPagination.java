package moe.cangku.reader;
/** Pure pagination decisions shared by the native Android print adapter and offline checks. */
public final class NativePrintPagination {
    private NativePrintPagination(){}
    public static int count(int contentHeight,int pageHeight){if(pageHeight<=0||contentHeight<0)throw new IllegalArgumentException("打印页面尺寸无效");long pages=Math.max(1,((long)contentHeight+pageHeight-1)/pageHeight);if(pages>500)throw new IllegalArgumentException("打印超过500页，请缩小正文后再打印");return (int)pages;}
    public static boolean included(int page,int[][] ranges){for(int[] range:ranges)if(range.length==2&&page>=range[0]&&page<=range[1])return true;return false;}
}
