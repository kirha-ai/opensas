data flags;
  input id nd;
  datalines;
1 .
2 .
3 1
4 .
5 1
;
run;
data a; set flags(where=(nd is null));     run;
proc print data=a noobs; run;
data b; set flags(where=(nd is not null)); run;
proc print data=b noobs; run;
data e; set flags(where=(id between 2 and 4)); run;
proc print data=e noobs; run;
