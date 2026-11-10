options nodate nonumber nosyntaxcheck;
proc format; value grp 1-2='Z' 3-4='A'; run;
data d; length b 8 x 8 c $12; label x='Numeric category' c='Character category'; format x grp.; input b x c $ w; datalines;
1 3 red 1
1 1 blue 3
1 . green 2
2 4 blue 2
2 2 red 1
;
run;
title 'METADATA';proc freq data=d nlevels; by b; weight w; tables x*c / out=o outpct outexpect; run;
proc contents data=o out=attrs noprint;run;
proc print data=attrs;var name type length label format informat;run;
title 'ALIAS';proc freq data=d; weight w; tables x*c / crosslist(pearsonresid stdresid) score=rank;run;
title 'TABLE';proc freq data=d; tables x*c / table;run;
title 'LINE';proc freq data=d; tables x*c / line;run;
title 'EMPTY TABLES';proc freq data=d;by b;weight w;tables;run;
title 'MAX MISSING';proc freq data=d;tables x / missing maxlevels=1;run;
title 'LIST ONE';proc freq data=d;tables x / list nofreq;run;
