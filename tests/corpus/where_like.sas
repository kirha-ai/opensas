data a;
  input id name $;
  datalines;
1 ADDENDUM
2 ADD
3 xyz
4 bob
;
run;
data pct;
  set a;
  where name like "ADD%";
run;
proc print data=pct noobs; run;
data uscore;
  set a;
  where name like 'A_D';
run;
proc print data=uscore noobs; run;
data notlike;
  set a;
  where name not like "ADD%";
run;
proc print data=notlike noobs; run;
