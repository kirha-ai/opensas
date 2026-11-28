/* STAT-SASHELP-001: SASHELP.BASEBALL is the published SAS 9.4 sample table
 * (322 rows, Appendix B Figure B.1 descriptor). Expected values come from a
 * SAS 9.4M9 run of this program, not from opensas. */
options nodate nonumber nocenter linesize=120 pagesize=max;
proc contents data=sashelp.baseball out=_d(keep=name type length varnum label) noprint; run;
proc sort data=_d; by varnum; run;
proc print data=_d noobs; run;
proc sql;
  create table _tot as select count(*) as N, count(Salary) as NSalary, sum(Salary) as SumSal,
         sum(nHits) as SumHits, sum(CrAtBat) as SumCrAtBat, sum(nOuts) as SumOuts,
         sum(nAssts) as SumAssts, sum(nError) as SumError, mean(logSalary) as MeanLog
    from sashelp.baseball;
  create table _div as select Div as DivCode, count(*) as N, sum(nHome) as Home, sum(Salary) as Sal
    from sashelp.baseball group by Div order by DivCode;
  create table _team as select Team as TeamName, count(*) as N, sum(nRBI) as RBI, sum(CrHits) as CrHits
    from sashelp.baseball group by Team order by TeamName;
  create table _pos as select Position as Pos, count(*) as N, sum(YrMajor) as Yrs
    from sashelp.baseball group by Position order by Pos;
quit;
data _null_; set _tot; put N= NSalary= SumSal= SumHits= SumCrAtBat= SumOuts= SumAssts= SumError=; put MeanLog=; run;
data _null_; set _div; put DivCode= N= Home= Sal=; run;
data _null_; set _team; put TeamName= N= RBI= CrHits=; run;
data _null_; set _pos; put Pos= N= Yrs=; run;
data _null_; set sashelp.baseball end=e; length who $ 18; retain mx 0 who;
  if Salary > mx then do; mx = Salary; who = Name; end;
  if _n_ = 322 then put 'LAST ' Name= Team= Position= logSalary=;
  if e then put 'MAXSAL ' who= mx=;
run;
