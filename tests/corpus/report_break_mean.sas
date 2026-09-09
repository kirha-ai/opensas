/* QA tick196: BREAK/RBREAK SUMMARIZE with an MEAN analysis column (d0badee) —
   VERIFIED GREEN. The existing report_break_summarize fixture covers SUM only;
   this pins the MEAN path where each subtotal and the grand total must be the
   MEAN over that scope's RAW detail rows, NOT the mean of the subtotals:
     E subtotal units = mean(1,2,3) = 2      (not mean(1.5,3)=2.25)
     grand   units = mean(1,2,3,4,5) = 3     (not mean(2,4.5)=3.25)
   revenue stays SUM. Guards the newest/most-complex report landing. */
data sales;
  input reg $ prod $ units revenue;
  datalines;
E A 1 10
E A 2 20
E B 3 30
W A 4 40
W B 5 50
;
run;

proc report data=sales nowd;
  column reg prod units revenue;
  define reg / group;
  define prod / group;
  define units / analysis mean;
  define revenue / analysis sum;
  break after reg / summarize;
  rbreak after / summarize;
run;
