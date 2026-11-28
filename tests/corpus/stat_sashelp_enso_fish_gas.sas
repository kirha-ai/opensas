/* STAT-SASHELP-004: SASHELP.ENSO, FISH and GAS are the published SAS 9.4
 * sample tables (Appendix B, PDF pp.10909-10912). Expected values come from
 * a SAS 9.4M9 run of this program, not from opensas. */
options nodate nonumber nocenter linesize=120 pagesize=max;
%macro desc(m);
proc contents data=sashelp.&m out=_d(keep=name type length varnum label) noprint; run;
proc sort data=_d; by varnum; run;
data _null_; set _d; put name= type= length= varnum= label=; run;
%mend;
%desc(enso) %desc(fish) %desc(gas)
proc sql;
  create table _e as select count(*) as N, sum(Pressure) as SumP, min(Pressure) as MinP,
         max(Pressure) as MaxP, max(Month) as MaxM, max(Year) as MaxY from sashelp.enso;
  create table _f as select Species as Sp, count(*) as N, count(Weight) as NW, sum(Weight) as W,
         sum(Length1) as L1, sum(Length2) as L2, sum(Length3) as L3, sum(Height) as H, sum(Width) as Wd
    from sashelp.fish group by Species order by Sp;
  create table _g as select Fuel as F, count(*) as N, count(NOx) as NN, sum(CpRatio) as Cp,
         sum(EqRatio) as Eq, sum(NOx) as NOxSum from sashelp.gas group by Fuel order by F;
quit;
data _null_; set _e; put N= SumP= MinP= MaxP= MaxM= MaxY=; run;
data _null_; set _f; put Sp= N= NW= W= L1= L2= L3= H= Wd=; run;
data _null_; set _g; put F= N= NN= Cp= Eq= NOxSum=; run;
data _null_; set sashelp.enso; if _n_ in (1, 84, 168) then put _n_= Month= Year= Pressure=; run;
data _null_; set sashelp.fish; if _n_ in (1, 14, 159) then put _n_= Species= Weight= Length1= Height= Width=; run;
data _null_; set sashelp.gas; if missing(NOx) or _n_ in (1, 171) then put _n_= Fuel= CpRatio= EqRatio= NOx=; run;
