/* GAP-putnegptr: PUT +(-n) moves the column pointer backward and overwrites
   existing bytes, clamping before column 1 to the left edge. Oracle: real
   SAS 9.4 via saspy/ODA. */
data _null_;
  put 'ABC ' +(-1) ']';
  put 'ABCDE' +(-3) 'xy';
  put 'AB' +(-9) 'Z';
run;
