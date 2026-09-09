/* GAP-sysrcmacro (tick284 F4): the %SYSRC autocall macro expands the
   doc-sourced _IORC_ return codes (Language Reference: Concepts Table 23.4 p.599 + worked logs:
   _SOK=0, _DSENOM=1230011, _DSENMR=1230015), and the %DATATYP/%VERIFY
   autocall companions work. SELECT-group shape per Language Reference: Concepts p.601. Synthetic. */
data _null_;
  put "SOK=%sysrc(_sok) NOM=%sysrc(_dsenom) NMR=%sysrc(_dsenmr)";
  _iorc_ = %sysrc(_sok); /* real programs get _IORC_ from MODIFY/SET KEY= */
  select(_iorc_);
    when(%sysrc(_sok)) put 'SELECT-MATCH';
    when(%sysrc(_dsenom)) put 'SELECT-NOMATCH';
    otherwise put 'SELECT-UNEXPECTED';
  end;
  put "TYP=[%datatyp(123)][%datatyp(abc)] VER=[%verify(abc,abcdef)][%verify(abz,ab)]";
run;
