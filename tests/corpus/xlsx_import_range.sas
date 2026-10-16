/* BUG-procimport: the legacy Excel engine shape — DBMS=EXCEL with
   RANGE="Sheet$" — must read the NAMED sheet.

   THE SHAPE that motivates it (D-011: describe the shape, never the source): a
   multi-sheet workbook delivered as a data transfer, where the sheet holding
   the data is NOT the first one, imported by a program that still uses the
   legacy engine name rather than DBMS=XLSX.

   Two defects, both fixed: RANGE was IGNORED, so the first sheet was read
   instead — silent wrong data, the worst failure class, since the import
   "succeeds" and every downstream step runs on the wrong rows — and DBMS=EXCEL
   was rejected outright. The workbook below is invented sample data. */
proc import out=d datafile="tests/corpus/includes/import_sample.xlsx" dbms=excel replace;
  range="Data$";
  getnames=yes;
run;
proc print data=d noobs; run;
