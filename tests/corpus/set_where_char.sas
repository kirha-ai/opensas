data a;
  input id sev $;
  datalines;
1 SEVERE
2 MILD
3 MODERATE
4 MILD
;
run;
data b;
  set a(where=(sev in ("SEVERE","MODERATE")));
run;
proc print data=b noobs; run;
