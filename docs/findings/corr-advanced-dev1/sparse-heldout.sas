data d; input x y f; datalines;
1 1 10
1 2 4
2 2 8
2 3 2
3 3 7
;
data p;set d;y=-y;run;title "negative";ods exclude all;ods output PolychoricCorr=o;proc corr data=p polychoric;var x y;freq f;run;ods exclude none;proc print data=o;format _numeric_ best32.;run;
data p;set d;if x=1 then x=100; else if x=2 then x=101; else x=1000;run;title "labels";ods exclude all;ods output PolychoricCorr=o;proc corr data=p polychoric;var x y;freq f;run;ods exclude none;proc print data=o;format _numeric_ best32.;run;
data p;set d;t=x;x=y;y=t;run;title "transposed";ods exclude all;ods output PolychoricCorr=o;proc corr data=p polychoric;var x y;freq f;run;ods exclude none;proc print data=o;format _numeric_ best32.;run;
data p;input x y f;datalines;
1 1 5
1 2 7
2 2 8
2 3 3
3 3 12
;
title "heldout";ods exclude all;ods output PolychoricCorr=o;proc corr data=p polychoric;var x y;freq f;run;ods exclude none;proc print data=o;format _numeric_ best32.;run;