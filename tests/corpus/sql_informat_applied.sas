/* GAP-sqlcolumnattr: CREATE TABLE's INFORMAT= was stored as metadata (it showed
   in CONTENTS) but never APPLIED — '15JAN2020' into a date9. column landed as
   missing with an invalid-data NOTE. The informat now reads VALUES/UPDATE
   character input with the INPUT() function's semantics: date9. -> the SAS day
   (rendered below via the attached FORMAT=), $upcase. case-folds; an unreadable
   field reads missing, a blank stays a benign missing. Sibling column attrs:
   FORMAT= renders (below), LABEL= shows in CONTENTS, NOT NULL is
   constraint-enforced (sql_coldef_attrs). */
proc sql;
  create table t (d num informat=date9. format=date9., c char(10) informat=$upcase.);
  insert into t values('15JAN2020', 'abc');
  insert into t values('garbage', 'de');
  insert into t values('', 'f');
  update t set d = '20JAN2020', c = 'xyz' where c = 'DE';
  select * from t;
quit;
