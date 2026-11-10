options nodate nonumber;
data d; input r c w; datalines;
1 1 3
1 2 -3
2 1 2
3 1 0
4 1 1
4 1 -1
;
run;
title 'SIGNED CROSS NOSPARSE';proc freq data=d;weight w / zeros;tables r*c / crosslist nosparse out=result;run;proc print data=result;run;
title 'ONE NOSPARSE';proc freq data=d;weight w / zeros;tables r / nosparse out=result outcum;run;proc print data=result;run;
