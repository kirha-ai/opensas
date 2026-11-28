/* STAT-SASHELP-006: SASHELP.MILEAGES / MARGARIN / QUAKES / SPRINGS built-in
 * public sample data (exported from SAS 9.4M9; see src/sashelp_tsv.zig).
 * Expected listing produced by SAS 9.4M9 from this exact program (page-start
 * blank lines omitted, as in the other FILE PRINT fixtures). */
options nodate nonumber nocenter linesize=120 pagesize=max;
data _null_;
  file print;
  set sashelp.mileages nobs=nobs;
  if _n_ = 1 then put 'MILEAGES ' nobs= ;
  lc = vlength(City);
  put City= lc= Atlanta= Chicago= Denver= Seattle= WashingtonDC=;
run;
data _null_;
  file print;
  set sashelp.margarin end=e nobs=nobs;
  n + 1; sp + LogPrice; si + LogInc; sf + FamSize; sc + Choice;
  if Brand = 'PSS' then pss + 1;
  if _n_ in (1, 20430) then put HouseID= Set= Choice= Brand= LogPrice= LogInc= FamSize=;
  if e then put 'MARGARIN ' nobs= n= sc= sf= pss= sp= si=;
run;
data _null_;
  file print;
  set sashelp.quakes end=e nobs=nobs;
  if missing(dNearestStation) then md + 1;
  if missing(RootMeanSquareTime) then mr + 1;
  if Type = 'quarry' then nq + 1;
  smag + Magnitude; sdep + Depth;
  if _n_ in (1, 2, 15578) then put Latitude= Longitude= Depth= Magnitude= Type= / dNearestStation= RootMeanSquareTime=;
  if e then put 'QUAKES ' nobs= md= mr= nq= smag= sdep=;
run;
data _null_;
  file print;
  set sashelp.springs end=e nobs=nobs;
  if Farenheit = .H then nh + 1;
  if Celsius = .W then nw + 1;
  if Celsius = . then np + 1;
  if _n_ <= 3 then put Name= Area= Type= Farenheit= Celsius=;
  if e then put 'SPRINGS ' nobs= nh= nw= np=;
run;
