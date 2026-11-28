/* STAT-PRINT-001: Base PROC PRINT layout rules needed by STAT originals.
 * Invented data. Expected tokens come from a SAS 9.4 run of this same program
 * (dev4 probe, 2026-11-28); spacing follows the opensas PRINT gutter.
 * (1) one fixed-decimal format per unformatted numeric column;
 * (2) unformatted numeric names split at lower-to-upper case changes. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data d1;
input a b c d e f g h;
datalines;
0.3333333333 123.456789 12345.6789 0.000012345 10000000000.5 1234567.891 -0.123456789 1
2 1 0.5 1 1 1 1 2.5
;
proc print data=d1; run;
data d3; a=0.2773500981; output; a=12.5; output; a=.; output; run;
proc print data=d3; run;
data d4; x=1/3; y=100/3; w=123456789012; v=-5; u=2.25; output;
x=3; y=1; w=1; v=0.5; u=-11.125; output; run;
proc print data=d4; run;
data h1; RunTime=1; ABC_DEF=1; LongMixedName=2; RunTimeValue=12345678.25; aB=1;
HTTPServer=1; SalesQ1Total=3; output; run;
proc print data=h1; run;
data h2; RunTime=12345.678; RT_A=1; output; run;
proc print data=h2; run;
data d5; v=42; output; v=3.14159; output; v=0.000123; output; v=123456789012; output; run;
proc print data=d5; run;
