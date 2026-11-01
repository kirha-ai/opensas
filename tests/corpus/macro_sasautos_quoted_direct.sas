/* BUG-sasautosquotedpath: the direct quoted path is read before %pick. */
options sasautos='tests/autocall_quote/a''b' mautosource;
%pick
