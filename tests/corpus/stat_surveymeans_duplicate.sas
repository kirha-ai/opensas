/* STAT-SURVEYMEANS-001: repeated declarations. Invented data. Expected
 * listing is the SAS 9.4 (SAS/STAT 15.4) output of this exact program
 * (reference run 2026-11-28). Physical p.9934: only the first WEIGHT
 * statement is used (log WARNING "Multiple WEIGHT statements. Only the
 * first WEIGHT statement will be used."); p.9933 / p.9925: the variables of
 * several STRATA (CLUSTER) statements together define the strata
 * (clusters), the same result as one statement listing them.
 */
options nodate nonumber nocenter linesize=160;
data a;
input y z w s c;
datalines;
11 4 2 1 1
13 5 0 1 1
12 . 1 1 2
16 7 3 2 3
. 2 . 2 3
14 3 1 2 4
-9 1 1 . 4
15 6 2 2 5
;
title 'C two weight';
proc surveymeans data=a; var z; weight w; weight s; run;
title 'D two strata';
proc surveymeans data=a; var z; strata s; strata c; run;
title 'D2 one strata two vars';
proc surveymeans data=a; var z; strata s c; run;
title 'E two cluster';
proc surveymeans data=a; var z; cluster s; cluster c; run;
