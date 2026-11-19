@EndUserText.label: 'Bolt - repository settings'
define abstract entity ZAB_CDS_A_BOLT_REPO_P
{
  // owner/name or https://github.com/owner/name (create: the new name)
  Repo         : abap.char( 140 );
  BranchPrefix : abap.char( 60 );
}
