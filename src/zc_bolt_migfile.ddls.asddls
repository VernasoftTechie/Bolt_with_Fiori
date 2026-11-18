@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - file pushed (projection)'
define view entity ZC_BOLT_MIGFILE
  as projection on ZI_BOLT_MIGFILE
{
  key MigUuid,
  key FileUuid,
      FilePath,
      FileName,
      Kind,
      SizeBytes,
      PushedAt,
      CreatedBy,

      _Migration : redirected to parent ZC_BOLT_MIGRATION
}
