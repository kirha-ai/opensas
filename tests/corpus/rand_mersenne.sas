/* RAND uniforms after CALL STREAMINIT. Expected text: a SAS 9.4 run of this
   program (STAT-RAND-001). SAS ignores the second and third STREAMINIT of the
   step, so r1 is the 3rd draw and v1 the 4th draw of the seed-1 stream. */
data _null_;
  call streaminit(1);
  u1 = rand("uniform");
  u2 = rand("uniform");
  put "seed1_draw1=" u1 12.10;
  put "seed1_draw2=" u2 12.10;
  call streaminit(1);
  r1 = rand("uniform");
  same = (r1 = u1);
  put "reseed_reproducible=" same;
  call streaminit(123);
  v1 = rand("uniform");
  put "seed123_draw1=" v1 12.10;
run;
