/* CALL ALLCOMBI (minimal-change index combinations) + CALL STREAMINIT/STREAMREWIND/
   STREAM (RAND stream control). Phase-F-final. */
data _null_;
  i1=0; i2=0;
  do j=1 to 6; call allcombi(4, 2, i1, i2); put "allcombi" j "=" i1 i2; end;
  call streaminit(123);
  u1 = rand("uniform");
  put "streaminit=" u1 10.7;
  call streamrewind();
  u2 = rand("uniform");
  put "rewind=" u2 10.7;
  call stream(99);
  u3 = rand("uniform");
  put "stream99=" u3 10.7;
run;
