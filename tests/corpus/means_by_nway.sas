/* BUG-meansbypooled regression lock (QA tick159): PROC MEANS with BY + CLASS +
   NWAY must print one CLASS table PER BY GROUP (before the fix, the CLASS path
   ignored BY and pooled all obs into a single table). NWAY keeps only the
   highest-order class combination (here the single class h), one per BY group. */
data d; input g h $ x; datalines;
1 P 10
1 Q 20
2 P 30
2 Q 40
;
run;
proc means data=d n mean nway; by g; class h; var x; run;
