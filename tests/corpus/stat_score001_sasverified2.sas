/* STAT-SCORE-001: more PROC SCORE rules settled by a batched SAS 9.4 run
   (SAS/STAT 15.4 ch.109, pp.8908-8911): an empty SCORE= data set (NOTE, the
   output keeps only the DATA= variables); a repeated DATA= and a repeated
   SCORE= (the first is kept, "WARNING: Ignoring second data set
   reference."); _TYPE_='USCORE' coefficients without a USTD row (raw values,
   the MEAN row ignored); a missing MEAN value (that variable is not
   centred); a USTD row next to SCORE coefficients (ignored); two MEAN rows
   (a warning, the last is used); an empty SCORE= data set with BY (no
   observations); a zero USTD (warning, the variable adds nothing) and a
   missing USTD (unscaled); two STD rows (a warning, the last is used).
   Data: invented. Expected: every value equals the SAS 9.4 listing of the
   same program token for token; only the PROC PRINT spacing is opensas's. */
options nodate nonumber nocenter ls=120 ps=max nosyntaxcheck;
data d; input x1 x2 y; datalines;
1 2 3
4 6 5
2 . 7
;
data d2; set d; x1=x1*10; run;
data c1; length _type_ $8 _name_ $8; input _type_ $ _name_ $ x1 x2 y;
datalines;
MEAN  .  2 4 5
STD   .  2 2 1
SCORE s1 1 1 0
SCORE s2 1 0 -1
;
data c2; set c1; x1=x1*100; run;
title 'R1 empty score'; data ce; set c1; stop; run; proc score data=d score=ce out=r1 nostd; var x1 x2; run; proc print data=r1; run;
title 'R2 repeated data'; proc score data=d data=d2 score=c1 out=r2 nostd; var x1 x2; run; proc print data=r2; run;
title 'R3 repeated score'; proc score data=d score=c1 score=c2 out=r3 nostd; var x1 x2; run; proc print data=r3; run;
data cu; length _type_ $8 _name_ $8; input _type_ $ _name_ $ x1 x2 y;
datalines;
MEAN  .  2 4 5
USCORE s1 1 1 0
;
title 'R4 uscore no ustd'; proc score data=d score=cu out=r4; var x1 x2; run; proc print data=r4; run;
data cmm; set c1; if _type_='MEAN' then x2=.; run;
title 'R5 missing mean'; proc score data=d score=cmm out=r5; var x1 x2; run; proc print data=r5; run;
data cmix2; set c1; output; if _type_='STD' then do; _type_='USTD'; x1=4; x2=4; output; end; run;
title 'R8 score with ustd'; proc score data=d score=cmix2 out=r8; var x1 x2; run; proc print data=r8; run;
data cms; set c1; output; if _type_='MEAN' then do; x1=0; output; end; run;
title 'R9 two mean rows'; proc score data=d score=cms out=r9; var x1 x2; run; proc print data=r9; run;
data b1; set c1; g=1; output; g=2; output; g=3; output; run; proc sort data=b1; by g; run;
data dg; set d; g=1; output; g=3; output; run; proc sort data=dg; by g; run;
title 'T2 empty score by'; data ce; set b1; stop; run; proc score data=dg score=ce out=t2 nostd; by g; var x1 x2; run; /* SAS: 0 obs, 4 variables (unit test) */
data cu; length _type_ $8 _name_ $8; input _type_ $ _name_ $ x1 x2 y;
datalines;
USTD  .  2 0 1
USCORE s1 1 1 0
;
title 'T3 zero ustd'; proc score data=d score=cu out=t3; var x1 x2; run; proc print data=t3; run;
data cu2; set cu; if _type_='USTD' then x2=.; run;
title 'T4 missing ustd'; proc score data=d score=cu2 out=t4; var x1 x2; run; proc print data=t4; run;
data cs2; set c1; output; if _type_='STD' then do; x1=1; output; end; run;
title 'T6 two std rows'; proc score data=d score=cs2 out=t6; var x1 x2; run; proc print data=t6; run;
