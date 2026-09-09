/* Fill a missing override with the base value via COALESCE over a LEFT JOIN */
data main; input USUBJID $ AVAL; datalines;
01-001 30
01-002 45
01-003 55
;
run;
data override; input USUBJID $ OVR; datalines;
01-002 99
;
run;
proc sql;
  select main.USUBJID, coalesce(override.OVR, main.AVAL) as finalval
  from main left join override on main.USUBJID = override.USUBJID
  order by main.USUBJID;
quit;
