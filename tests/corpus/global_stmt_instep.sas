/* GAP-globalstmtswallow (F3): a TITLE/FOOTNOTE/OPTIONS placed INSIDE a DATA or
   PROC step is honored by SAS for that step's output (a standard TFL idiom) and
   persists to later steps. opensas used to silently swallow them (except PROC
   SQL). Here the mid-PROC title stamps THIS proc's listing, the mid-DATA-step
   footnote persists to the next proc, and the mid-step title still shows below-
   free ordering. */
data one;
  input id x;
  footnote "MID-DATA FOOT";
  datalines;
1 10
2 20
;
run;

proc print data=one noobs;
  title "IN-PROC TITLE";
  var id x;
run;
