data have;
  input name $ age dept $;
  datalines;
Alice 30 X
Bob 25 Y
;
run;

proc print data=have noobs;
  var name age;
run;
