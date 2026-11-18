@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - connection and scope setup (projection)'
define root view entity ZC_BOLT_SETUP
  provider contract transactional_query
  as projection on ZI_BOLT_SETUP
{
  key SetupId,
      CustomerName,
      GhDestination,
      GhOwner,
      GhRepo,
      GhBaseBranch,
      GhBranchPrefix,
      GhStatus,
      GhStatusText,
      GhCheckedAt,
      AiProvider,
      AiModel,
      AiDestination,
      AiBasePath,
      AiMaxTokens,
      AiKeySet,
      AiStatus,
      AiStatusText,
      AiCheckedAt,
      FormPrefix1,
      FormPrefix2,
      CountVolume,
      AdminUsers,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalLastChanged
}
