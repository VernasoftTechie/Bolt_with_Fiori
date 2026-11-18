@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form migration'
define root view entity ZI_BOLT_MIGRATION
  as select from zbolt_mig

  composition [0..*] of ZI_BOLT_MIGLOG  as _Log
  composition [0..*] of ZI_BOLT_MIGFILE as _File
{
  key mig_uuid           as MigUuid,
      serial_no          as SerialNo,
      form_name          as FormName,
      form_description   as FormDescription,
      system_id          as SystemId,
      sap_client         as SapClient,
      branch_name        as BranchName,
      form_slug          as FormSlug,
      push_status        as PushStatus,
      push_message       as PushMessage,
      push_attempts      as PushAttempts,
      pushed_at          as PushedAt,
      files_pushed       as FilesPushed,
      commit_sha         as CommitSha,
      status             as Status,
      status_label       as StatusLabel,
      waiting_on         as WaitingOn,
      status_note        as StatusNote,
      stop_flag          as StopFlag,
      claimed_by         as ClaimedBy,
      status_updated     as StatusUpdated,
      status_sha         as StatusSha,
      last_sync_at       as LastSyncAt,
      complexity         as Complexity,
      complexity_text    as ComplexityText,
      withdrawn          as Withdrawn,
      @Semantics.user.createdBy: true
      created_by         as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at         as CreatedAt,
      @Semantics.user.lastChangedBy: true
      changed_by         as ChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      changed_at         as ChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed as LocalLastChanged,

      _Log,
      _File
}
