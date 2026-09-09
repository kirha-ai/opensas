* BUG-attribfmttype: ATTRIB with a $ format=/informat= and NO length=;
* types the var CHARACTER at the spec width (Language Reference: Concepts p.50, Ex 4.1/4.2);
* Ex 4.1: f is Char 12 and the char value survives;
data e;
  attrib f format=$char12.;
  f = 'x';
  put "f=" f;
run;
proc contents data=e; run;

* Ex 4.2: a var already char stays Char, the $10. attaches, values intact;
data ex42;
  Flavor = "Cherry";
  attrib Flavor format=$10.;
  Flavor = "CherryPie!";
  put "Flavor=" Flavor;
run;
proc contents data=ex42; run;

* informat=$15. creates a Char 15 var;
data g15;
  attrib g informat=$15.;
  g = 'abc';
  put "g=" g;
run;
proc contents data=g15; run;

* Numeric format spec still creates a NUMERIC var (unchanged);
data n;
  attrib x format=8.2;
  x = 3.5;
  put "x=" x;
run;
proc contents data=n; run;
