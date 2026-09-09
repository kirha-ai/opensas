data a; input id v; datalines;
1 10
2 20
;
run;
data b; input id w; datalines;
2 200
3 300
;
run;
data _null_;
  merge a(in=ina) b(in=inb);
  by id;
  length src $6;
  if ina and inb then src="both";
  else if ina then src="a";
  else src="b";
  put "id=" id src;
run;
