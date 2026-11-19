@EndUserText.label: 'Bolt - response to the engineer'
define abstract entity ZAB_CDS_A_BOLT_RESP_P
{
  // confirm / problem / question / change / concern
  Kind      : abap.char( 20 );
  Text      : abap.string( 0 );
  // JSON array [{"name":"a.pdf","content":"<base64>"}]
  FilesJson : abap.string( 0 );
}
