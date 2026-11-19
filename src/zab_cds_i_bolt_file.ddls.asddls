@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - files on a migration branch'
define view entity ZAB_CDS_I_BOLT_FILE
  as select from zabt_bolt_file

  association to parent ZAB_CDS_I_BOLT_MIG as _Migration on $projection.MigUuid = _Migration.MigUuid
{
  key mig_uuid   as MigUuid,
  key file_uuid  as FileUuid,
      file_kind  as FileKind,
      file_name  as FileName,
      file_path  as FilePath,
      size_bytes as SizeBytes,
      commit_sha as CommitSha,
      pushed_at  as PushedAt,
      pushed_by  as PushedBy,
      removed    as Removed,
      removed_at as RemovedAt,
      removed_by as RemovedBy,

      _Migration
}
