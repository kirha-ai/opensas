/* AE: events + severe count per SOC, keep SOCs with >=2 events (SQL group/having) */
data ae;
  input USUBJID $ AESOC $ AESEV $;
  datalines;
01-001 GI MILD
01-001 GI MODERATE
01-002 CARDIAC SEVERE
01-002 GI MILD
01-003 GI MILD
01-003 CARDIAC MILD
;
run;

proc sql;
  select AESOC,
         count(*) as n_events,
         sum(case when AESEV="SEVERE" then 1 else 0 end) as n_severe
  from ae
  group by AESOC
  having count(*) >= 2
  order by AESOC;
quit;
