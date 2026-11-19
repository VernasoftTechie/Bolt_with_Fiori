@EndUserText.label: 'Bolt - AI provider settings'
define abstract entity ZAB_CDS_A_BOLT_AI_P
{
  Provider  : abap.char( 20 );
  Model     : abap.char( 80 );
  BaseUrl   : abap.char( 255 );
  MaxTokens : abap.int4;
  // blank = keep the stored key
  ApiKey    : abap.string( 0 );
}
