data _null_;
  s = '2023-05-04';
  d_iso = input(s, e8601da.);
  d_w   = input('2023-05-04', e8601da10.);
  d_bas = input('20230504', b8601da8.);
  put "iso=" d_iso " w=" d_w " basic=" d_bas;
run;
