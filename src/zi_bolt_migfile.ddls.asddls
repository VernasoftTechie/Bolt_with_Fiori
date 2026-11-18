@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - file pushed for a migration'
define view entity ZI_BOLT_MIGFILE
  as select from zbolt_migfile

  association to parent ZI_BOLT_MIGRATION as _Migration
    on $projection.MigUuid = _Migration.MigUuid
{
  key mig_uuid   as MigUuid,
  key file_uuid  as FileUuid,
      file_path  as FilePath,
      file_name  as FileName,
      kind       as Kind,
      size_bytes as SizeBytes,
      pushed_at  as PushedAt,
      created_by as CreatedBy,

      _Migration
}
