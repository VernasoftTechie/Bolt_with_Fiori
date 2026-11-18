@EndUserText.label: 'Bolt - concern parameters'
define abstract entity ZA_BOLT_CONCERN_P
{
  Kind        : abap.char( 20 );
  Text        : abap.string( 0 );
  FileName    : abap.char( 120 );
  FileContent : abap.string( 0 );
}
