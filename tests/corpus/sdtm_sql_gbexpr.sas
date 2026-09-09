/* Count subjects by an age-band EXPRESSION (GROUP BY expr) */
data dm; input USUBJID $ AGE; datalines;
01-001 25
01-002 45
01-003 30
01-004 70
;
run;
proc sql;
  select case when AGE < 40 then "YOUNG" else "OLD" end as band, count(*) as n
  from dm
  group by (AGE < 40)
  order by band;
quit;
