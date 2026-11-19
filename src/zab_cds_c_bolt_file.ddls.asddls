@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - branch files (projection)'
define view entity ZAB_CDS_C_BOLT_FILE
  as projection on ZAB_CDS_I_BOLT_FILE
{
  key MigUuid,
  key FileUuid,
      FileKind,
      FileName,
      FilePath,
      SizeBytes,
      CommitSha,
      PushedAt,
      PushedBy,
      Removed,
      RemovedAt,
      RemovedBy,

      _Migration : redirected to parent ZAB_CDS_C_BOLT_MIG
}
