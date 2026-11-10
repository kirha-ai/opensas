options nodate nonumber;
data d; input g h r c w; datalines;
1 1 10 2 3
1 1 10 4 1
1 1 20 2 2
2 2 20 4 4
2 2 30 6 0
2 2 . 2 2
;
run;
title 'LIST default'; proc freq data=d; weight w; tables g*h*r*c / list out=ol outpct outexpect; run; proc print data=ol; run;
title 'LIST zeros'; proc freq data=d; weight w / zeros; tables r*c / list out=oz; run; proc print data=oz; run;
title 'LIST zeros nosparse'; proc freq data=d; weight w / zeros; tables r*c / list nosparse out=onz; run; proc print data=onz; run;
title 'CROSSLIST'; proc freq data=d; weight w; tables g*r*c / crosslist(pearsonres stdres) expected deviation cellchi2 totpct missprint; run;
title 'GRID'; proc freq data=d; weight w; tables g*r*c / expected deviation cellchi2 cumcol totpct missprint out=og outpct outexpect; run; proc print data=og; run;
title 'EMPTY STRATA'; proc freq data=d; weight w; tables g*h*r*c; run;
title 'NL'; proc freq data=d nlevels; weight w / zeros; tables r; run;
title 'DEFAULT TABLES'; proc freq data=d noprint; run;
title 'MAX'; proc freq data=d; weight w; tables r / missprint maxlevels=1 out=om outcum; run; proc print data=om; run;
title 'SCORES'; proc freq data=d; weight w; tables r*c / scores=rank scorout chisq; tables r*c / scores=ridit scorout chisq; tables r*c / scores=modridit scorout chisq; run;
data neg; input r c w; datalines;
1 1 5
1 2 -1
2 1 3
2 2 2
3 1 1
3 1 -1
;
run;
title 'NEGATIVE'; proc freq data=neg; weight w; tables r / out=on outcum; tables r*c / expected deviation cellchi2 out=onc outpct outexpect; tables r*c / list; tables r*c / crosslist; run; proc print data=on; run; proc print data=onc; run;
title 'FORMCHAR'; proc freq data=neg formchar(1,2,7)='!=#'; tables r*c / format=6.1; run;
title 'CARTESIAN'; proc freq data=d; tables (g h)*(r c) / out=last; run; proc print data=last; run;
