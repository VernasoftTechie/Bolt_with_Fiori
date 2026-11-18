@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - migration log entry'
define view entity ZI_BOLT_MIGLOG
  as select from zbolt_miglog

  association to parent ZI_BOLT_MIGRATION as _Migration
    on $projection.MigUuid = _Migration.MigUuid
{
  key mig_uuid   as MigUuid,
  key log_uuid   as LogUuid,
      log_source as LogSource,
      seq_no     as SeqNo,
      entry_at   as EntryAt,
      heading    as Heading,
      actor      as Actor,
      log_text   as LogText,
      created_at as CreatedAt,

      _Migration
}
