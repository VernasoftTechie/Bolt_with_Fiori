"! <p class="shorttext synchronized">Bolt with Fiori - AI provider client</p>
"! Same three choices as Bolt Console's AI settings: NONE (built-in, nothing
"! to connect), OPENAI (ChatGPT or any OpenAI-compatible endpoint - Azure,
"! GitHub Models, a company AI gateway, Ollama) and ANTHROPIC (Claude).
"! Host/TLS/proxy come from the SM59 destination; the API key is stored by
"! the Setup business object in ZBOLT_SECRET (never returned to the UI).
"! Used for the "AI summary" of a migration's legacy grab.
CLASS zcl_bolt_ai DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      gc_model_openai TYPE string VALUE `gpt-4o-mini`,
      gc_model_claude TYPE string VALUE `claude-sonnet-5-5`.

    CLASS-METHODS complete
      IMPORTING is_setup      TYPE zbolt_setup
                iv_prompt     TYPE string
                iv_max_tokens TYPE i OPTIONAL
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_bolt.

    CLASS-METHODS test
      IMPORTING is_setup      TYPE zbolt_setup
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_bolt.

    CLASS-METHODS model_of
      IMPORTING is_setup       TYPE zbolt_setup
      RETURNING VALUE(rv_model) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_message,
        role    TYPE string,
        content TYPE string,
      END OF ty_message,
      ty_t_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY.

    CLASS-METHODS base_path
      IMPORTING is_setup       TYPE zbolt_setup
      RETURNING VALUE(rv_path) TYPE string.

    CLASS-METHODS error_text
      IMPORTING iv_body        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.



CLASS zcl_bolt_ai IMPLEMENTATION.

  METHOD model_of.
    rv_model = condense( CONV string( is_setup-ai_model ) ).
    IF rv_model IS INITIAL.
      rv_model = SWITCH #( is_setup-ai_provider
                           WHEN zcl_bolt_config=>gc_provider_openai THEN gc_model_openai
                           WHEN zcl_bolt_config=>gc_provider_claude THEN gc_model_claude
                           ELSE `built-in` ).
    ENDIF.
  ENDMETHOD.


  METHOD base_path.
    rv_path = condense( CONV string( is_setup-ai_base_path ) ).
    IF rv_path IS INITIAL.
      rv_path = `/v1`.
    ENDIF.
    IF substring( val = rv_path off = strlen( rv_path ) - 1 len = 1 ) = `/`.
      rv_path = substring( val = rv_path len = strlen( rv_path ) - 1 ).
    ENDIF.
  ENDMETHOD.


  METHOD error_text.
    TYPES:
      BEGIN OF ty_err,
        message TYPE string,
        type    TYPE string,
      END OF ty_err,
      BEGIN OF ty_err_res,
        error TYPE ty_err,
      END OF ty_err_res.
    DATA ls_err TYPE ty_err_res.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = iv_body
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                   CHANGING  data        = ls_err ).
      CATCH cx_root ##CATCH_ALL.
        CLEAR ls_err.
    ENDTRY.
    rv_text = ls_err-error-message.
    IF rv_text IS INITIAL.
      rv_text = substring( val = iv_body len = nmin( val1 = 200 val2 = strlen( iv_body ) ) ).
    ENDIF.
  ENDMETHOD.


  METHOD complete.
    TYPES:
      BEGIN OF ty_request,
        model      TYPE string,
        max_tokens TYPE i,
        messages   TYPE ty_t_message,
      END OF ty_request,
      BEGIN OF ty_choice,
        message TYPE ty_message,
      END OF ty_choice,
      ty_t_choice TYPE STANDARD TABLE OF ty_choice WITH EMPTY KEY,
      BEGIN OF ty_openai_res,
        choices TYPE ty_t_choice,
      END OF ty_openai_res,
      BEGIN OF ty_block,
        type TYPE string,
        text TYPE string,
      END OF ty_block,
      ty_t_block TYPE STANDARD TABLE OF ty_block WITH EMPTY KEY,
      BEGIN OF ty_claude_res,
        content TYPE ty_t_block,
      END OF ty_claude_res.
    DATA ls_openai TYPE ty_openai_res.
    DATA ls_claude TYPE ty_claude_res.

    IF is_setup-ai_provider = zcl_bolt_config=>gc_provider_none OR is_setup-ai_provider IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `No AI provider is configured - choose one in Configuration > AI provider.` ).
    ENDIF.
    DATA(lv_key) = zcl_bolt_config=>get_secret( zcl_bolt_config=>gc_secret_ai_key ).
    IF lv_key IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `The AI provider needs an API key - add it in Configuration > AI provider.` ).
    ENDIF.

    DATA(lv_max) = COND i( WHEN iv_max_tokens > 0 THEN iv_max_tokens
                           WHEN is_setup-ai_max_tokens > 0 THEN is_setup-ai_max_tokens
                           ELSE 2000 ).
    DATA(lv_body) = /ui2/cl_json=>serialize(
      data        = VALUE ty_request( model      = model_of( is_setup )
                                      max_tokens = lv_max
                                      messages   = VALUE #( ( role = `user` content = iv_prompt ) ) )
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    DATA(lt_headers) = VALUE zcl_bolt_http=>ty_t_header(
      ( name = `Content-Type` value = `application/json` ) ).
    DATA lv_uri TYPE string.
    IF is_setup-ai_provider = zcl_bolt_config=>gc_provider_claude.
      lv_uri = base_path( is_setup ) && `/messages`.
      APPEND VALUE #( name = `x-api-key`         value = lv_key ) TO lt_headers.
      APPEND VALUE #( name = `anthropic-version` value = `2023-06-01` ) TO lt_headers.
    ELSE.
      lv_uri = base_path( is_setup ) && `/chat/completions`.
      APPEND VALUE #( name = `Authorization` value = |Bearer { lv_key }| ) TO lt_headers.
      " Azure OpenAI accepts this header instead of a bearer token.
      APPEND VALUE #( name = `api-key` value = lv_key ) TO lt_headers.
    ENDIF.

    DATA(ls_resp) = zcl_bolt_http=>call( iv_destination = is_setup-ai_destination
                                         iv_method      = `POST`
                                         iv_uri         = lv_uri
                                         iv_body        = lv_body
                                         it_headers     = lt_headers
                                         iv_timeout     = 180 ).
    IF ls_resp-code <> 200.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |The AI provider answered HTTP { ls_resp-code }: { error_text( ls_resp-body ) }| ).
    ENDIF.

    IF is_setup-ai_provider = zcl_bolt_config=>gc_provider_claude.
      /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                 CHANGING  data        = ls_claude ).
      LOOP AT ls_claude-content INTO DATA(ls_block) WHERE type = `text`.
        rv_text = rv_text && ls_block-text.
      ENDLOOP.
    ELSE.
      /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                 CHANGING  data        = ls_openai ).
      IF ls_openai-choices IS NOT INITIAL.
        rv_text = ls_openai-choices[ 1 ]-message-content.
      ENDIF.
    ENDIF.
    IF rv_text IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `The AI provider answered, but with no text.` ).
    ENDIF.
  ENDMETHOD.


  METHOD test.
    IF is_setup-ai_provider = zcl_bolt_config=>gc_provider_none OR is_setup-ai_provider IS INITIAL.
      rv_text = `Built-in (no AI provider) - nothing to connect. AI summaries are switched off.`.
      RETURN.
    ENDIF.
    DATA(lv_answer) = complete( is_setup      = is_setup
                                iv_prompt     = `Reply with the single word OK to confirm the connection works.`
                                iv_max_tokens = 16 ).
    rv_text = |Connection OK - { is_setup-ai_provider } ({ model_of( is_setup ) }) responded: { condense( lv_answer ) }|.
  ENDMETHOD.

ENDCLASS.
