@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form migration (projection)'
define root view entity ZC_BOLT_MIGRATION
  provider contract transactional_query
  as projection on ZI_BOLT_MIGRATION
{
  key MigUuid,
      SerialNo,
      FormName,
      FormDescription,
      SystemId,
      SapClient,
      BranchName,
      FormSlug,
      PushStatus,
      PushMessage,
      PushAttempts,
      PushedAt,
      FilesPushed,
      CommitSha,
      Status,
      StatusLabel,
      WaitingOn,
      StatusNote,
      StopFlag,
      ClaimedBy,
      StatusUpdated,
      StatusSha,
      LastSyncAt,
      Complexity,
      ComplexityText,
      Withdrawn,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalLastChanged,

      _Log  : redirected to composition child ZC_BOLT_MIGLOG,
      _File : redirected to composition child ZC_BOLT_MIGFILE
}
