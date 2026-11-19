@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bolt - reference library (projection)'
define root view entity ZAB_CDS_C_BOLT_LIB
  provider contract transactional_query
  as projection on ZAB_CDS_I_BOLT_LIB
{
  key LibUuid,
      LibCategory,
      FileName,
      FilePath,
      SizeBytes,
      Provenance,
      Pushed,
      PushMsg,
      CommitSha,
      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      LocalChanged
}
