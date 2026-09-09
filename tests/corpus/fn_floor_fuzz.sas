data _null_;
  a = floor(0.3/0.1);
  b = ceil(0.3/0.1);
  c = int(0.3/0.1);
  d = floor(-0.3/0.1);
  az = floorz(0.3/0.1);
  bz = ceilz(0.3/0.1);
  put "a=" a " b=" b " c=" c " d=" d " az=" az " bz=" bz;
run;
