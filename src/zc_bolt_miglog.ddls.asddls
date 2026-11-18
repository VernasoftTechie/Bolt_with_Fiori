@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - migration log entry (projection)'
define view entity ZC_BOLT_MIGLOG
  as projection on ZI_BOLT_MIGLOG
{
  key MigUuid,
  key LogUuid,
      LogSource,
      SeqNo,
      EntryAt,
      Heading,
      Actor,
      LogText,
      CreatedAt,

      _Migration : redirected to parent ZC_BOLT_MIGRATION
}
