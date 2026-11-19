@EndUserText.label: 'Bolt - system the app runs in'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_AB_BOLT_Q_SYSINFO'

// One row: the logged-on system and user, and whether everything the app
// needs is connected (the header chips and the LIVE indicator).

define custom entity ZAB_CDS_CE_BOLT_SYSINFO
{
      @EndUserText.label: 'System'
  key SystemId      : sysysid;
      @EndUserText.label: 'Client'
      Client        : symandt;
      @EndUserText.label: 'Host'
      HostName      : abap.char( 64 );
      @EndUserText.label: 'User'
      UserName      : syuname;
      @EndUserText.label: 'Client name'
      CustomerName  : abap.char( 80 );
      @EndUserText.label: 'Setup exists'
      SetupExists   : abap_boolean;
      @EndUserText.label: 'Administrator'
      IsAdmin       : abap_boolean;
      @EndUserText.label: 'Administrators defined'
      AdminsDefined : abap_boolean;
      @EndUserText.label: 'GitHub connected'
      GitHubReady   : abap_boolean;
      @EndUserText.label: 'Repository ready'
      RepoReady     : abap_boolean;
      @EndUserText.label: 'AI ready'
      AiReady       : abap_boolean;
      @EndUserText.label: 'Live'
      Live          : abap_boolean;
      @EndUserText.label: 'Repository URL'
      RepoUrl       : abap.char( 255 );
      @EndUserText.label: 'Driver index built'
      IndexBuilt    : abap_boolean;
      @EndUserText.label: 'App version'
      AppVersion    : abap.char( 20 );
}
