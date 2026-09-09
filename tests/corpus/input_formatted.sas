data col;
  input id 3. @5 amt comma8.;
  put "id=" id " amt=" amt;
datalines;
001 1,234
002 5,678
;
run;
data ptr;
  input x #2 y / z;
  put "x=" x " y=" y " z=" z;
datalines;
1
2
3
4
5
6
;
run;
data compact;
  input v @@;
  put "v=" v;
datalines;
10 20 30
;
run;
