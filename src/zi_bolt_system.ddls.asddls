@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form source system'
define root view entity ZI_BOLT_SYSTEM
  as select from zbolt_system
{
  key system_id          as SystemId,
      description        as Description,
      sap_client         as SapClient,
      destination        as Destination,
      service_path       as ServicePath,
      base_url           as BaseUrl,
      is_local           as IsLocal,
      is_default         as IsDefault,
      sort_order         as SortOrder,
      status             as Status,
      status_text        as StatusText,
      checked_at         as CheckedAt,
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
