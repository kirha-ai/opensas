/* GAP-macroautofeatures (tick234 F5/F6/F7): documented automatic macro vars
   seeded (&SYSSCPL/&SYSCC/&SYSRC/&SYSLAST/&SYSNOBS), %SYSGET reads the host
   environment, %PUT _USER_ dumps the user globals to the log. The %PUT dump
   itself goes to the SAS log (stderr); stdout pins the seeded/read values. */
%let home = %sysget(HOME);
%global g;
%let g = 42;
%put _user_;
data _null_;
  if length(trim("&sysscpl")) > 0 then put 'SYSSCPL-OK';
  if length(trim("&home")) > 0 then put 'SYSGET-OK';
  if "&syscc" = "0" and "&sysrc" = "0" then put 'CODES-OK';
  put "g=&g";
run;
