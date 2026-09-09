data have;
  input id x;
  datalines;
1 10
2 20
;
run;

proc print data=have noobs;
  options nodate;
  title j=c "Report";
  var id x;
run;
