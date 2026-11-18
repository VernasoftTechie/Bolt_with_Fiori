@EndUserText.label: 'Bolt - legacy files of one Smart Form (source API)'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_BOLT_Q_SRC_FILE'

// Machine-to-machine: runs the legacy grab for one form on THIS system and
// returns its files (snapshot .md, form XML export, driver sources).
// Required filter FORM_NAME eq '<form>' ('*GLOBAL*' = SmartStyle and logo
// inventories). Optional filters PREFIXES eq 'Z,Y' and COUNT_VOLUME eq 'X'.
// MESSAGE repeats any warning of the run on every row.

define custom entity ZCE_BOLT_SRC_FILE
{
      @EndUserText.label: 'Smart Form'
  key FORM_NAME    : abap.char( 30 );
      @EndUserText.label: 'File name'
  key FILE_NAME    : abap.char( 120 );
      @EndUserText.label: 'Kind'
      KIND         : abap.char( 10 );
      @EndUserText.label: 'Size in bytes'
      SIZE_BYTES   : abap.int4;
      @EndUserText.label: 'Content'
      CONTENT      : abap.string( 0 );
      @EndUserText.label: 'Prefixes (filter only)'
      PREFIXES     : abap.char( 20 );
      @EndUserText.label: 'Count NAST usage (filter only)'
      COUNT_VOLUME : abap.char( 1 );
      @EndUserText.label: 'Warnings'
      MESSAGE      : abap.string( 0 );
}
