/* NOTE-putcolrewind: backward PUT @n overwrites bytes already on the current
   output line. Oracle: real SAS 9.4 via saspy/ODA. */
data _null_;
  put 'ABC..' @1 'XY';
  put '12345' @3 'ab';
  put 'abc' @2 'Z' +1 'Q';
run;
