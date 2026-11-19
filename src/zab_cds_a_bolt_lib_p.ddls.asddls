@EndUserText.label: 'Bolt - global library upload'
define abstract entity ZAB_CDS_A_BOLT_LIB_P
{
  // logo / smartstyle / naming_standard / policy
  Category   : abap.char( 20 );
  Provenance : abap.char( 255 );
  FilesJson  : abap.string( 0 );
}
