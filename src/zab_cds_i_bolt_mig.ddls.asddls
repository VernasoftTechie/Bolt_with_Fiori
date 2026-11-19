@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form migration'
define root view entity ZAB_CDS_I_BOLT_MIG
  as select from zabt_bolt_mig

  composition [0..*] of ZAB_CDS_I_BOLT_HIST as _History
  composition [0..*] of ZAB_CDS_I_BOLT_FILE as _File
{
  key mig_uuid        as MigUuid,
      serial_no       as SerialNo,
      form_name       as FormName,
      form_descr      as FormDescr,
      dev_package     as DevPackage,
      driver_progs    as DriverProgs,
      output_types    as OutputTypes,
      run_no          as RunNo,
      reprocess_of    as ReprocessOf,
      superseded      as Superseded,
      branch_name     as BranchName,
      form_slug       as FormSlug,
      push_status     as PushStatus,
      push_msg        as PushMsg,
      push_attempts   as PushAttempts,
      pushed_at       as PushedAt,
      files_count     as FilesCount,
      commit_sha      as CommitSha,
      mig_status      as MigStatus,
      waiting_on      as WaitingOn,
      stopped         as Stopped,
      claimed_by      as ClaimedBy,
      status_updated  as StatusUpdated,
      status_sha      as StatusSha,
      last_sync_at    as LastSyncAt,
      picked_up_at    as PickedUpAt,
      stopped_at      as StoppedAt,
      completed_at    as CompletedAt,
      complexity      as Complexity,
      complexity_info as ComplexityInfo,
      source_sysid    as SourceSysid,
      source_client   as SourceClient,
      @Semantics.user.createdBy: true
      created_by      as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at      as CreatedAt,
      @Semantics.user.lastChangedBy: true
      changed_by      as ChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      changed_at      as ChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_changed   as LocalChanged,

      _History,
      _File
}
