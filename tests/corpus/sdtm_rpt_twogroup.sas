/* Two grouping vars, summed (PROC REPORT two group columns) */
data ex; input ARM $ SEX $ EXDOSE; datalines;
DRUG M 50
DRUG F 100
DRUG M 25
PLAC M 0
;
run;
proc report data=ex nowd;
  column ARM SEX EXDOSE;
  define ARM / group;
  define SEX / group;
  define EXDOSE / analysis sum;
run;
