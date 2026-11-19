@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - client setup'
define root view entity ZAB_CDS_I_BOLT_SETUP
  as select from zabt_bolt_setup
{
  key setup_id        as SetupId,
      customer_name   as CustomerName,
      admin_users     as AdminUsers,
      gh_api_url      as GhApiUrl,
      gh_dest         as GhDest,
      ssl_id          as SslId,
      gh_token_set    as GhTokenSet,
      gh_login        as GhLogin,
      gh_user_name    as GhUserName,
      gh_scopes       as GhScopes,
      gh_connected_at as GhConnectedAt,
      gh_repo         as GhRepo,
      gh_base_branch  as GhBaseBranch,
      gh_branch_pfx   as GhBranchPfx,
      gh_private      as GhPrivate,
      gh_can_push     as GhCanPush,
      gh_check_res    as GhCheckRes,
      gh_check_msg    as GhCheckMsg,
      gh_checked_at   as GhCheckedAt,
      status_folder   as StatusFolder,
      lib_folder      as LibFolder,
      ai_provider     as AiProvider,
      ai_model        as AiModel,
      ai_base_url     as AiBaseUrl,
      ai_dest         as AiDest,
      ai_max_tokens   as AiMaxTokens,
      ai_key_set      as AiKeySet,
      ai_check_res    as AiCheckRes,
      ai_check_msg    as AiCheckMsg,
      ai_checked_at   as AiCheckedAt,
      form_prefixes   as FormPrefixes,
      count_volume    as CountVolume,
      @Semantics.user.createdBy: true
      created_by      as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at      as CreatedAt,
      @Semantics.user.lastChangedBy: true
      changed_by      as ChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      changed_at      as ChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_changed   as LocalChanged
}
