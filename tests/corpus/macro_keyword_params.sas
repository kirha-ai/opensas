/* Keyword macro parameters + defaults — the core SDTM report-macro pattern:
   %macro rpt(dom, lib=work, keep=usubjid). Synthetic. macro-params. */
%macro rpt(dom, lib=work, keep=usubjid);
  data _null_; put "RPT dom=&dom lib=&lib keep=&keep"; run;
%mend;
%rpt(AE)
%rpt(CM, keep=usubjid aeterm)
%rpt(VS, lib=raw)
%rpt(LB, lib=raw, keep=lbtest)
