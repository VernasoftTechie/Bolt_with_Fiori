@EndUserText.label: 'Bolt - legacy document changes'
define abstract entity ZAB_CDS_A_BOLT_DOCS_P
{
  // files to add: JSON array [{"name":"a.pdf","content":"<base64>"}]
  FilesJson : abap.string( 0 );
  // FileUuid values (32 hex characters) to remove from the list, comma separated
  RemoveIds : abap.string( 0 );
}
