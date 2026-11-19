@EndUserText.label: 'Bolt - branch status file (live)'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_AB_BOLT_Q_STATUS'

// The header of a migration's status file, read live from its GitHub branch
// on every request - the communication texts are not stored in SAP.
// Request with $filter=MigUuid eq <uuid>. Found = false: not on GitHub yet
// (or not readable - Message says why).

define custom entity ZAB_CDS_CE_BOLT_STATUS
{
      @EndUserText.label: 'Migration'
  key MigUuid       : sysuuid_x16;
      @EndUserText.label: 'Status file found'
      Found         : abap_boolean;
      @EndUserText.label: 'Status'
      MigStatus     : abap.char( 30 );
      @EndUserText.label: 'Status label'
      StatusLabel   : abap.char( 60 );
      @EndUserText.label: 'Updated'
      UpdatedAt     : abap.char( 30 );
      @EndUserText.label: 'Waiting on'
      WaitingOn     : abap.char( 30 );
      @EndUserText.label: 'Note'
      Note          : abap.string( 0 );
      @EndUserText.label: 'Stop requested'
      StopRequested : abap_boolean;
      @EndUserText.label: 'Picked up by'
      ClaimedBy     : abap.char( 80 );
      @EndUserText.label: 'Timeline entries'
      EntryCount    : abap.int4;
      @EndUserText.label: 'Branch on GitHub'
      BranchUrl     : abap.char( 255 );
      @EndUserText.label: 'Message'
      Message       : abap.char( 255 );
}
