@EndUserText.label: 'Bolt - reset connection parameters'
define abstract entity ZAB_CDS_A_BOLT_FLUSH_P
{
  // X = also clear the client name and the administrators list
  ClearIdentity : abap.char( 1 );
  // X = also clear the global reference library list (ZABT_BOLT_LIB)
  ClearLibrary  : abap.char( 1 );
}
