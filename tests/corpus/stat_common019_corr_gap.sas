/* expect-rc: 2
 * STAT-COMMON-019: a TYPE=CORR member is not dissimilarity input to PROC
 * CLUSTER (p.2489); without a TYPE= data set option the member type decides,
 * so it must fail visibly (D-009 gap), never be clustered as coordinates or
 * as distances. Invented correlation matrix.
 */
options nodate nonumber nocenter;
title; footnote;
data c(type=corr);
   input _type_ $ _name_ $ a b c;
   datalines;
CORR a 1.0 0.5 0.2
CORR b 0.5 1.0 0.3
CORR c 0.2 0.3 1.0
;
run;
proc cluster data=c method=single;
   var a b c;
run;
