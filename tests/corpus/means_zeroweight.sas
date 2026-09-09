/* BUG-meanszeroweight: PROC MEANS/SUMMARY with a WEIGHT var. SAS 9.4 DEFAULT
   (no EXCLNPWGT) COUNTS zero/negative-weight obs in N and uses their value for
   MIN/MAX; the zero weight only zeroes their contribution to weighted Sum/Mean.
   Missing-weight obs are always dropped from N.
   x={10,20,30,40} w={0,2,3,4}: Σwx=290, Σw=9, Mean=290/9=32.2222222, Sum=290.
   Default: N=4, NMiss=0, Min=10 (the w=0 row still bounds MIN), Max=40.
   EXCLNPWGT: the w=0 row is dropped entirely → N=3, Min=20. */
data d;
  input x w;
  datalines;
10 0
20 2
30 3
40 4
;
run;
proc means data=d n nmiss mean sum min max;
  weight w;
  var x;
run;
proc means data=d exclnpwgt n nmiss mean sum min max;
  weight w;
  var x;
run;
