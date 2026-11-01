/* BUG-sasautosquotedpath: a doubled apostrophe belongs to the path. */
filename ac 'tests/autocall_quote/a''b';
options sasautos=ac mautosource;
%pick
