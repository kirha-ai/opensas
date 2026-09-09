/* GAP-vtabledisk: SASHELP.VTABLE must list a libref's DISK-ONLY members —
   te.sas7bdat below is never SET/loaded, yet the XPT-creation idiom
   (vtable scan -> CALL SYMPUT count -> %do) must find it. */
libname l "tests/programs/sas7bdat_read/inputs";
data _null_;
  set sashelp.vtable end=last;
  where libname = "L";
  i + 1;
  call symput('m'||strip(put(i,best.)), strip(memname));
  if last then call symput('nb', i);
run;
%macro listing;
  %do i=1 %to &nb.;
    %put member&i=&&m&i;
  %end;
%mend;
%listing;
data _null_;
  n = symget('nb') + 0;
  m1 = symget('m1');
  put n= m1=;
run;
