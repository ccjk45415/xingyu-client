package moe.cangku.reader;
import android.content.Context;import android.graphics.drawable.GradientDrawable;import android.view.*;import android.widget.*;

/** Shared native cards and labeled icon controls for the AI workflow. */
final class AiPanelUi {
    final Context context;final Ui ui;
    AiPanelUi(Context context,Ui ui){this.context=context;this.ui=ui;}
    LinearLayout section(LinearLayout parent,String title,String subtitle,String glyph,String step){
        LinearLayout card=ui.column();ui.pad(card,16,17,16,17);GradientDrawable shape=ui.round(ui.surface,20);shape.setStroke(ui.dp(1),ui.line);card.setBackground(shape);parent.addView(card,new LinearLayout.LayoutParams(-1,-2));ui.space(parent,14);
        LinearLayout head=ui.row();head.setGravity(Gravity.TOP);FrameLayout tile=new FrameLayout(context);tile.setBackground(ui.round(ui.soft,12));tile.addView(new EditorToolIcon(context,glyph,ui.accent),new FrameLayout.LayoutParams(ui.dp(21),ui.dp(21),Gravity.CENTER));head.addView(tile,new LinearLayout.LayoutParams(ui.dp(38),ui.dp(38)));
        LinearLayout words=ui.column();ui.pad(words,11,0,4,0);words.addView(ui.text(title,17,ui.text,true));TextView description=ui.text(subtitle,12,ui.muted,false);description.setLineSpacing(ui.dp(3),1f);words.addView(description);head.addView(words,new LinearLayout.LayoutParams(0,-2,1));if(!step.isEmpty())head.addView(ui.text(step,12,ui.accent,true));card.addView(head);ui.space(card,16);return card;
    }
    TextView note(LinearLayout parent,String value){TextView t=ui.text(value,12,ui.muted,false);t.setLineSpacing(ui.dp(4),1f);ui.pad(t,12,11,12,11);t.setBackground(ui.round(ui.soft,12));parent.addView(t,new LinearLayout.LayoutParams(-1,-2));ui.space(parent,10);return t;}
    TextView action(String label,String glyph,boolean filled,Runnable run){
        TextView b=ui.button(label,filled,run);EditorToolIcon icon=new EditorToolIcon(context,glyph,filled?android.graphics.Color.WHITE:ui.accent);icon.measure(View.MeasureSpec.makeMeasureSpec(ui.dp(19),View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(ui.dp(19),View.MeasureSpec.EXACTLY));icon.layout(0,0,ui.dp(19),ui.dp(19));android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(ui.dp(19),ui.dp(19),android.graphics.Bitmap.Config.ARGB_8888);icon.draw(new android.graphics.Canvas(bitmap));android.graphics.drawable.BitmapDrawable drawable=new android.graphics.drawable.BitmapDrawable(context.getResources(),bitmap);drawable.setBounds(0,0,ui.dp(19),ui.dp(19));b.setCompoundDrawablesRelative(drawable,null,null,null);b.setCompoundDrawablePadding(ui.dp(8));b.setGravity(Gravity.CENTER_VERTICAL|Gravity.CENTER_HORIZONTAL);b.setContentDescription(label);b.setTooltipText(label);return b;
    }
    EditText field(LinearLayout parent,String label,int lines){
        TextView name=ui.text(label,12,ui.muted,true);parent.addView(name);ui.space(parent,7);EditText e=new EditText(context,null,0,R.style.ScrollableEditor);e.setTextSize(14);e.setTextColor(ui.text);e.setHintTextColor(ui.muted);e.setHint(lines>1?"在这里粘贴内容":"在这里填写");e.setContentDescription(label);e.setMinLines(lines);e.setMaxLines(Math.max(3,lines+2));e.setGravity(Gravity.TOP);e.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);GradientDrawable bg=ui.round(ui.bg,12);bg.setStroke(ui.dp(1),ui.line);e.setBackground(bg);ui.pad(e,12,11,12,11);e.setSaveEnabled(false);e.setVerticalScrollBarEnabled(true);e.setOnTouchListener((v,event)->{if(e.canScrollVertically(-1)||e.canScrollVertically(1)){int a=event.getActionMasked();if(a==android.view.MotionEvent.ACTION_DOWN)e.getParent().requestDisallowInterceptTouchEvent(true);if(a==android.view.MotionEvent.ACTION_UP||a==android.view.MotionEvent.ACTION_CANCEL)e.getParent().requestDisallowInterceptTouchEvent(false);}return false;});parent.addView(e,new LinearLayout.LayoutParams(-1,-2));ui.space(parent,13);return e;
    }
}
