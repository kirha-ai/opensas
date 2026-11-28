/* STAT-SCORE-001: PROC SCORE rules settled by a batched SAS 9.4 run
   (SAS/STAT 15.4 ch.109, pp.8908-8911). Each title names the case:
   DATAn naming without OUT= (DATA1 then DATA2); default TYPE= reading
   _TYPE_='USCORE' rows scaled by the USTD row without centering (a MEAN row
   is ignored) and NOSTD; a repeated TYPE= (last wins); a repeated OUT=
   (first kept, "WARNING: Ignoring second data set reference."); two VAR
   statements (accumulated); MEAN alone (centering only); STD alone (scaling
   only); a zero STD (warning, the variable adds nothing but a missing value
   still gives a missing score); a missing STD (centered, not scaled); a blank
   score name (row skipped with a warning); a score name already on the output
   (renamed y2 with a NOTE); data set options on SCORE= and OUT=; BY groups
   with different score names (union, missing where a group lacks one).
   Data: invented. Expected: every value equals the SAS 9.4 listing of the
   same program (token for token; Q4b prints O4X, which SAS created with the
   Q4 options, 3 obs and 5 variables); only the PROC PRINT spacing is
   opensas's. */
options nosyntaxcheck nodate nonumber nocenter ls=120 ps=max;
data d; input x1 x2 y; datalines;
1 2 3
4 6 5
2 . 7
;
data c1; length _type_ $8 _name_ $8; input _type_ $ _name_ $ x1 x2 y;
datalines;
MEAN  .  2 4 5
STD   .  2 2 1
SCORE s1 1 1 0
SCORE s2 1 0 -1
;
data cu; length _type_ $8 _name_ $8; input _type_ $ _name_ $ x1 x2 y;
datalines;
MEAN  .  2 4 5
USTD  .  2 2 1
USCORE s1 1 1 0
;
title 'Q1 DATAn'; proc score data=d score=c1; var x1 x2; run; proc print data=data1; run;
title 'Q1b DATAn second'; proc score data=d score=c1; var x1 x2; run; proc print data=data2; run;
title 'Q2 USCORE USTD'; proc score data=d score=cu out=o2; var x1 x2; run; proc print data=o2; run;
title 'Q2b USCORE nostd'; proc score data=d score=cu out=o2b nostd; var x1 x2; run; proc print data=o2b; run;
title 'Q4 repeated type'; proc score data=d score=c1 out=o4 type=xx type=score nostd; var x1 x2; run; proc print data=o4; run;
title 'Q4b repeated out'; proc score data=d score=c1 out=o4x out=o4b nostd; var x1 x2; run; proc print data=o4x; run;
title 'Q5 two var'; proc score data=d score=c1 out=o5 nostd; var x1; var x2; run; proc print data=o5; run;
data cm; set c1; if _type_ ne 'STD'; run;
title 'Q6 mean only'; proc score data=d score=cm out=o6; var x1 x2; run; proc print data=o6; run;
data cs; set c1; if _type_ ne 'MEAN'; run;
title 'Q6b std only'; proc score data=d score=cs out=o6b; var x1 x2; run; proc print data=o6b; run;
data cz; set c1; if _type_='STD' then x2=0; run;
title 'Q7 zero std'; proc score data=d score=cz out=o7; var x1 x2; run; proc print data=o7; run;
data cmiss; set c1; if _type_='STD' then x2=.; run;
title 'Q7b missing std'; proc score data=d score=cmiss out=o7b; var x1 x2; run; proc print data=o7b; run;
data cbl; set c1; if _name_='s2' then _name_=' '; run;
title 'Q8b blank name'; proc score data=d score=cbl out=o8b nostd; var x1 x2; run; proc print data=o8b; run;
data cy; set c1; if _name_='s2' then _name_='y'; run;
title 'Q10 name on output'; proc score data=d score=cy out=o10 nostd; var x1 x2; run; proc print data=o10; run;
title 'Q12 dsopt score'; proc score data=d score=c1(where=(_name_ ne 's2')) out=o12(keep=x1 s1) nostd; var x1 x2; run; proc print data=o12; run;
data b1; set c1; g=1; output; g=2; output; run; proc sort data=b1; by g; run;
data b2; set b1; if g=2 and _name_='s2' then _name_='s3'; run;
data dg; set d; g=1; output; g=2; output; run; proc sort data=dg; by g; run;
title 'Q14 by diff names'; proc score data=dg score=b2 out=o14 nostd; by g; var x1 x2; run; proc print data=o14; run;
