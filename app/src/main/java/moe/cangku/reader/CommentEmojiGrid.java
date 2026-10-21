package moe.cangku.reader;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import java.util.ArrayList;
import java.util.List;

/** Equal-width rows avoid GridLayout's conflicting weighted column constraints. */
final class CommentEmojiGrid extends LinearLayout {
    private final List<View> cells=new ArrayList<>();
    private final int minimumWidth,cellHeight,gap;
    private int columns=-1;

    CommentEmojiGrid(Context context){
        super(context);setOrientation(VERTICAL);
        float density=getResources().getDisplayMetrics().density;
        minimumWidth=Math.max(Math.round(54*density),Math.round(36*getResources().getDisplayMetrics().scaledDensity));gap=Math.round(3*density);
        cellHeight=Math.max(Math.round(64*density),Math.round(40*density+12*getResources().getDisplayMetrics().scaledDensity));
    }
    void setCells(List<View> values){cells.clear();cells.addAll(values);columns=-1;requestLayout();}
    @Override protected void onMeasure(int widthSpec,int heightSpec){
        int width=MeasureSpec.getMode(widthSpec)==MeasureSpec.UNSPECIFIED?getResources().getDisplayMetrics().widthPixels:MeasureSpec.getSize(widthSpec);
        int next=Math.max(1,Math.min(6,(width-getPaddingLeft()-getPaddingRight())/Math.max(1,minimumWidth)));
        if(next!=columns){columns=next;removeAllViews();
            for(int first=0;first<cells.size();first+=columns){
                LinearLayout row=new LinearLayout(getContext());row.setOrientation(HORIZONTAL);row.setBaselineAligned(false);row.setWeightSum(columns);
                for(int column=0;column<columns;column++){
                    View cell=first+column<cells.size()?cells.get(first+column):new View(getContext());
                    if(cell.getParent() instanceof ViewGroup)((ViewGroup)cell.getParent()).removeView(cell);
                    LayoutParams params=new LayoutParams(0,cellHeight,1);params.setMargins(gap,gap,gap,gap);row.addView(cell,params);
                }
                addView(row,new LayoutParams(LayoutParams.MATCH_PARENT,LayoutParams.WRAP_CONTENT));
            }
        }
        super.onMeasure(widthSpec,heightSpec);
    }

    /** Long sticker pages scroll independently while category tabs and paging stay visible. */
    static final class Viewport extends ScrollView {
        Viewport(Context context){super(context);setFillViewport(false);}
        @Override protected void onMeasure(int widthSpec,int heightSpec){
            int cap=Math.min(Math.round(320*getResources().getDisplayMetrics().density),Math.round(getResources().getDisplayMetrics().heightPixels*.42f));
            if(MeasureSpec.getMode(heightSpec)!=MeasureSpec.UNSPECIFIED)cap=Math.min(cap,MeasureSpec.getSize(heightSpec));
            super.onMeasure(widthSpec,MeasureSpec.makeMeasureSpec(Math.max(0,cap),MeasureSpec.AT_MOST));
        }
    }
}
