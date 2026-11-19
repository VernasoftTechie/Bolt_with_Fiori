@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - global reference library'
define root view entity ZAB_CDS_I_BOLT_LIB
  as select from zabt_bolt_lib
{
  key lib_uuid      as LibUuid,
      lib_category  as LibCategory,
      file_name     as FileName,
      file_path     as FilePath,
      size_bytes    as SizeBytes,
      provenance    as Provenance,
      pushed        as Pushed,
      push_msg      as PushMsg,
      commit_sha    as CommitSha,
      @Semantics.user.createdBy: true
      created_by    as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at    as CreatedAt,
      @Semantics.user.lastChangedBy: true
      changed_by    as ChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      changed_at    as ChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_changed as LocalChanged
}
