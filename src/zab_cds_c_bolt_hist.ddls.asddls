@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - status history (projection)'
define view entity ZAB_CDS_C_BOLT_HIST
  as projection on ZAB_CDS_I_BOLT_HIST
{
  key MigUuid,
  key HistUuid,
      EventAt,
      HistEvent,
      Actor,
      EventUser,
      MigStatus,
      WaitingOn,
      Stopped,
      CommitSha,

      _Migration : redirected to parent ZAB_CDS_C_BOLT_MIG
}
