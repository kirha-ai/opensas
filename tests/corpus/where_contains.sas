data a;
  input id name $;
  datalines;
1 abc
2 xyz
3 bob
4 cat
;
run;
data hasb;
  set a;
  where name contains "b";
run;
proc print data=hasb noobs; run;
data hasb2;
  set a;
  where name ? "b";
run;
proc print data=hasb2 noobs; run;
data nob;
  set a;
  where name not contains "b";
run;
proc print data=nob noobs; run;
