options nodate nonumber nosyntaxcheck;
data d; input a b w; datalines;
1 1 3
1 2 1
2 1 2
2 2 4
;
run;
title 'ALL SUPPRESSED';proc freq data=d;weight w;tables a*b / nofreq nopercent norow nocol;run;
title 'LIST TABLE LINE';proc freq data=d;weight w;tables a*b / list table line;run;
proc freq data=d noprint;weight w;tables a / out=o outcum;run;
proc contents data=o out=attrs noprint;run;proc print data=attrs;var name label;run;
proc freq data=d noprint;weight w;tables a*a*b / out=o outpct;run;
proc contents data=o out=attrs noprint;run;proc print data=attrs;var name label;run;

title 'NOFREQ';proc freq data=d;weight w;tables a*b / nofreq;run;
title 'NOFREQ NOPERCENT';proc freq data=d;weight w;tables a*b / nofreq nopercent;run;
title 'LIST TABLE LINE NW';proc freq data=d;weight w;tables a*a*b / list table line;run;
