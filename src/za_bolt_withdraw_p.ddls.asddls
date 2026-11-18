@EndUserText.label: 'Bolt - withdraw parameters'
define abstract entity ZA_BOLT_WITHDRAW_P
{
  DeleteBranch : abap_boolean;
  Reason       : abap.string( 0 );
}
