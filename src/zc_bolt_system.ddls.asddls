@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - Smart Form source system (projection)'
define root view entity ZC_BOLT_SYSTEM
  provider contract transactional_query
  as projection on ZI_BOLT_SYSTEM
{
  key SystemId,
      Description,
      SapClient,
      Destination,
      ServicePath,
      BaseUrl,
      IsLocal,
      IsDefault,
      SortOrder,
      Status,
      StatusText,
      CheckedAt,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalLastChanged
}
