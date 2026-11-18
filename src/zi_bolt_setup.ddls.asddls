@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - connection and scope setup'
define root view entity ZI_BOLT_SETUP
  as select from zbolt_setup
{
  key setup_id           as SetupId,
      customer_name      as CustomerName,
      gh_destination     as GhDestination,
      gh_owner           as GhOwner,
      gh_repo            as GhRepo,
      gh_base_branch     as GhBaseBranch,
      gh_branch_prefix   as GhBranchPrefix,
      gh_status          as GhStatus,
      gh_status_text     as GhStatusText,
      gh_checked_at      as GhCheckedAt,
      ai_provider        as AiProvider,
      ai_model           as AiModel,
      ai_destination     as AiDestination,
      ai_base_path       as AiBasePath,
      ai_max_tokens      as AiMaxTokens,
      ai_key_set         as AiKeySet,
      ai_status          as AiStatus,
      ai_status_text     as AiStatusText,
      ai_checked_at      as AiCheckedAt,
      form_prefix1       as FormPrefix1,
      form_prefix2       as FormPrefix2,
      count_volume       as CountVolume,
      admin_users        as AdminUsers,
      @Semantics.user.createdBy: true
      created_by         as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at         as CreatedAt,
      @Semantics.user.lastChangedBy: true
      changed_by         as ChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      changed_at         as ChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed as LocalLastChanged
}
