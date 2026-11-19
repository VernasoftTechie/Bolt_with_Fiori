@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - client setup (projection)'
define root view entity ZAB_CDS_C_BOLT_SETUP
  provider contract transactional_query
  as projection on ZAB_CDS_I_BOLT_SETUP
{
  key SetupId,
      CustomerName,
      AdminUsers,
      GhApiUrl,
      GhDest,
      SslId,
      GhTokenSet,
      GhLogin,
      GhUserName,
      GhScopes,
      GhConnectedAt,
      GhRepo,
      GhBaseBranch,
      GhBranchPfx,
      GhPrivate,
      GhCanPush,
      GhCheckRes,
      GhCheckMsg,
      GhCheckedAt,
      StatusFolder,
      LibFolder,
      AiProvider,
      AiModel,
      AiBaseUrl,
      AiDest,
      AiMaxTokens,
      AiKeySet,
      AiCheckRes,
      AiCheckMsg,
      AiCheckedAt,
      FormPrefixes,
      CountVolume,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalChanged
}
