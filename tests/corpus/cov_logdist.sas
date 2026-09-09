data _null_;
  lc=logcdf('NORMAL',0); ls=logsdf('NORMAL',0); sq=squantile('NORMAL',0.025);
  lco=lcomb(5,2); lpe=lperm(5,2);
  gz=geomeanz(1,2,4); hz=harmeanz(1,2,4);
  put "logcdf_sdf=" lc ls;
  put "squantile=" sq;
  put "lcomb_lperm=" lco lpe;
  put "geomeanz_harmeanz=" gz hz;
run;
