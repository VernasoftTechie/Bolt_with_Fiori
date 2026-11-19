@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - migration status history'
define view entity ZAB_CDS_I_BOLT_HIST
  as select from zabt_bolt_hist

  association to parent ZAB_CDS_I_BOLT_MIG as _Migration on $projection.MigUuid = _Migration.MigUuid
{
  key mig_uuid   as MigUuid,
  key hist_uuid  as HistUuid,
      event_at   as EventAt,
      hist_event as HistEvent,
      actor      as Actor,
      event_user as EventUser,
      mig_status as MigStatus,
      waiting_on as WaitingOn,
      stopped    as Stopped,
      commit_sha as CommitSha,

      _Migration
}
