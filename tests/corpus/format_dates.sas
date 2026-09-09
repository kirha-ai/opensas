data _null_;
  d = 23735;       /* 25DEC2024, a Wednesday */
  dt = 2050741800; /* 25DEC2024:10:30:00 */
  tm = 37800;      /* 10:30:00 */
  put d monyy7.;
  put d monname.;
  put d downame.;
  put d year4.;
  put dt datetime20.;
  put tm timeampm11.;
  put dt tod8.;
run;
