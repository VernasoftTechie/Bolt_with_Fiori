@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form migration (projection)'
define root view entity ZAB_CDS_C_BOLT_MIG
  provider contract transactional_query
  as projection on ZAB_CDS_I_BOLT_MIG
{
  key MigUuid,
      SerialNo,
      FormName,
      FormDescr,
      DevPackage,
      DriverProgs,
      OutputTypes,
      RunNo,
      ReprocessOf,
      Superseded,
      BranchName,
      FormSlug,
      PushStatus,
      PushMsg,
      PushAttempts,
      PushedAt,
      FilesCount,
      CommitSha,
      MigStatus,
      WaitingOn,
      Stopped,
      ClaimedBy,
      StatusUpdated,
      StatusSha,
      LastSyncAt,
      PickedUpAt,
      StoppedAt,
      CompletedAt,
      Complexity,
      ComplexityInfo,
      SourceSysid,
      SourceClient,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalChanged,

      _History : redirected to composition child ZAB_CDS_C_BOLT_HIST,
      _File : redirected to composition child ZAB_CDS_C_BOLT_FILE
}
