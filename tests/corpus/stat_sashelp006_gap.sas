/* STAT-SASHELP-006 loud gap: SASHELP members not yet built in (here
 * SASHELP.COAL, owned by STAT-SASHELP-007) are the ordinary "does not exist"
 * error, never substitute data.
 * expect-rc: 1 */
data _null_;
  set sashelp.coal;
run;
