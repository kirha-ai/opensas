/* BUG-existdisk: EXIST() must see a member that lives on disk in a libref dir
   even when the program never names it as a literal lib.ds token (the member
   below appears only inside strings / %sysfunc text, so main's preload never
   loads it into memory). */
libname l "tests/programs/sas7bdat_read/inputs";
%let se = %sysfunc(exist(l.te));
data _null_;
  s = &se;                /* the macro-text route (a real EPOCH macro's shape) -> 1 */
  e = exist('l.te');      /* on disk (te.sas7bdat), not in memory -> 1 */
  n = exist('l.nope');    /* no such member -> 0 */
  w = exist('nolib.te');  /* unassigned libref -> 0 */
  put s= e= n= w=;
run;
