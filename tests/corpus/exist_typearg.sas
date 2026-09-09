/* BUG-existtypearg: EXIST(member[, type]) honors the optional member-TYPE arg.
   type defaults to DATA. opensas can only create DATA sets (CREATE VIEW/CATALOG
   fail loud), so exist(ds,'VIEW') / exist(ds,'CATALOG') on a plain data set must
   return 0, not 1 — otherwise macro guards like %if %sysfunc(exist(&ds,VIEW))
   misfire. EXIST is a boolean check and never errors on the type value. */
data have; x=1; run;
data _null_;
  a = exist('work.have');            /* no type -> data set exists -> 1 */
  b = exist('work.have', 'DATA');    /* explicit DATA -> 1 */
  c = exist('work.have', 'VIEW');    /* no views can exist yet -> 0 */
  d = exist('work.have', 'CATALOG'); /* no catalogs -> 0 */
  e = exist('work.nosuch');          /* nonexistent -> 0 */
  put a= b= c= d= e=;
run;
