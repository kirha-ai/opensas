/* NOTE-reportgroupblank: PROC REPORT blanks a repeated GROUP value like an
   ORDER value — Procedures Guide 7th ed printed p.2094: "PROC REPORT does not
   repeat the values of a group variable from one row to the next if the value
   does not change, unless a group variable to its left changes values."
   Report 1: left group ARM repeats across SEX rows -> blanked; PLAC prints
   because it changed. Report 2: the "unless" clause — prod B repeats across the
   reg boundary E->W but PRINTS, because a group variable to its left (reg)
   changed. */
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

data s2; input reg $ prod $ units; datalines;
E A 1
E B 2
W B 3
W C 4
;
run;
proc report data=s2 nowd;
  column reg prod units;
  define reg / group;
  define prod / group;
  define units / analysis sum;
run;
