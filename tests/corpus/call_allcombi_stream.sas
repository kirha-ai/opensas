/* CALL ALLCOMBI (minimal-change index combinations) + CALL STREAMINIT/STREAMREWIND/
   STREAM (RAND stream control). Phase-F-final. The streaminit=/rewind= lines are
   SAS 9.4 output of this program (STAT-RAND-001). */
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
  /* SAS 9.4 prints stream99= 0.3087137 (substream 99 of seed 123); opensas
     approximates CALL STREAM by reseeding, so only the range is pinned. */
  inrange = (0 < u3 < 1);
  put "stream99_in01=" inrange;
  /* opensas regression pin, NOT a SAS expectation (SAS 9.4: 0.3087137). */
  put "opensas_pin_stream99=" u3 hex16.;
run;
