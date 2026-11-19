"! <p class="shorttext synchronized">Bolt - AI provider client</p>
"! Same three choices as Bolt Console's AI settings: mock (built-in, works
"! offline, no key), openai (ChatGPT or any OpenAI-compatible endpoint - Azure,
"! GitHub Models, a company gateway, Ollama - via the base URL) and anthropic.
"! The API key is stored by the Setup business object in ZABT_BOLT_SECRT and is
"! never returned to the UI. Used for "Test connection" and the plain-language
"! "AI summary" of a migration's legacy grab.
CLASS zcl_ab_bolt_ai DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      gc_model_openai    TYPE string VALUE `gpt-4o-mini`,
      gc_model_anthropic TYPE string VALUE `claude-sonnet-5-5`,
      gc_url_openai      TYPE string VALUE `https://api.openai.com/v1`,
      gc_url_anthropic   TYPE string VALUE `https://api.anthropic.com/v1`.

    "! Ready = built-in provider, or a key is stored (aiStatus().ready).
    CLASS-METHODS is_ready
      IMPORTING is_setup        TYPE zabt_bolt_setup
      RETURNING VALUE(rv_ready) TYPE abap_bool.

    CLASS-METHODS complete
      IMPORTING is_setup       TYPE zabt_bolt_setup
                iv_prompt      TYPE string
                iv_max_tokens  TYPE i OPTIONAL
                iv_key         TYPE string OPTIONAL
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_ab_bolt.

    "! iv_key: a key typed but not saved yet (Test before Save), else the stored one.
    CLASS-METHODS test
      IMPORTING is_setup       TYPE zabt_bolt_setup
                iv_key         TYPE string OPTIONAL
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_ab_bolt.

    CLASS-METHODS model_of
      IMPORTING is_setup        TYPE zabt_bolt_setup
      RETURNING VALUE(rv_model) TYPE string.

    CLASS-METHODS label_of
      IMPORTING iv_provider     TYPE zabt_bolt_setup-ai_provider
      RETURNING VALUE(rv_label) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_message,
        role    TYPE string,
        content TYPE string,
      END OF ty_message,
      ty_t_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY.

    CLASS-METHODS endpoint_of
      IMPORTING is_setup           TYPE zabt_bolt_setup
      EXPORTING es_endpoint        TYPE zcl_ab_bolt_http=>ty_endpoint
                ev_path_prefix     TYPE string.

    CLASS-METHODS error_text
      IMPORTING iv_body        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    "! The built-in provider: a short, deterministic digest of the prompt's
    "! snapshot headings - no network, so it always works (like mock.js).
    CLASS-METHODS builtin
      IMPORTING iv_prompt      TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.



CLASS zcl_ab_bolt_ai IMPLEMENTATION.

  METHOD label_of.
    rv_label = SWITCH #( iv_provider
                         WHEN zcl_ab_bolt_config=>gc_provider-openai    THEN `OpenAI`
                         WHEN zcl_ab_bolt_config=>gc_provider-anthropic THEN `Anthropic`
                         ELSE `Built-in (offline)` ).
  ENDMETHOD.


  METHOD is_ready.
    rv_ready = xsdbool( is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-mock
                        OR is_setup-ai_provider IS INITIAL
                        OR is_setup-ai_key_set = abap_true ).
  ENDMETHOD.


  METHOD model_of.
    rv_model = condense( CONV string( is_setup-ai_model ) ).
    IF rv_model IS INITIAL.
      rv_model = SWITCH #( is_setup-ai_provider
                           WHEN zcl_ab_bolt_config=>gc_provider-openai    THEN gc_model_openai
                           WHEN zcl_ab_bolt_config=>gc_provider-anthropic THEN gc_model_anthropic
                           ELSE `built-in` ).
    ENDIF.
  ENDMETHOD.


  METHOD endpoint_of.
    DATA(lv_url) = condense( CONV string( is_setup-ai_base_url ) ).
    IF lv_url IS INITIAL.
      lv_url = COND #( WHEN is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-anthropic
                       THEN gc_url_anthropic ELSE gc_url_openai ).
    ENDIF.
    WHILE strlen( lv_url ) > 1 AND substring( val = lv_url off = strlen( lv_url ) - 1 len = 1 ) = `/`.
      lv_url = substring( val = lv_url len = strlen( lv_url ) - 1 ).
    ENDWHILE.
    es_endpoint = VALUE #( base_url = lv_url destination = is_setup-ai_dest ssl_id = is_setup-ssl_id ).
    CLEAR ev_path_prefix.
    IF is_setup-ai_dest IS NOT INITIAL.
      " With a destination the host comes from SM59; keep only the URL's path (e.g. /v1).
      FIND FIRST OCCURRENCE OF REGEX '^https?://[^/]+(/.*)?$' IN lv_url SUBMATCHES ev_path_prefix.
      IF sy-subrc <> 0.
        ev_path_prefix = `/v1`.
      ENDIF.
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


  METHOD builtin.
    DATA lt_points TYPE string_table.
    SPLIT iv_prompt AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
    LOOP AT lt_lines INTO DATA(lv_line).
      IF strlen( lv_line ) > 3 AND substring( val = lv_line len = 3 ) = `## `.
        APPEND |- { substring( val = lv_line off = 3 ) }| TO lt_points.
      ENDIF.
      IF lines( lt_points ) >= 8.
        EXIT.
      ENDIF.
    ENDLOOP.
    rv_text = COND #( WHEN lt_points IS INITIAL
                      THEN `Built-in provider: no AI model is connected, so no summary was written. The legacy grab on the branch has the full detail.`
                      ELSE |Built-in provider (no AI model connected) - sections of the legacy grab:{ cl_abap_char_utilities=>newline }| &&
                           concat_lines_of( table = lt_points sep = cl_abap_char_utilities=>newline ) ).
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

    IF is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-mock OR is_setup-ai_provider IS INITIAL.
      rv_text = builtin( iv_prompt ).
      RETURN.
    ENDIF.
    DATA(lv_key) = COND string( WHEN iv_key IS NOT INITIAL THEN iv_key
                                ELSE zcl_ab_bolt_config=>get_secret( zcl_ab_bolt_config=>gc_secret-ai_key ) ).
    IF lv_key IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Enter an API key for this provider to save or test.` ).
    ENDIF.

    DATA(lv_max) = COND i( WHEN iv_max_tokens > 0 THEN iv_max_tokens
                           WHEN is_setup-ai_max_tokens > 0 THEN is_setup-ai_max_tokens
                           ELSE 2000 ).
    DATA(lv_body) = /ui2/cl_json=>serialize(
      data        = VALUE ty_request( model      = model_of( is_setup )
                                      max_tokens = lv_max
                                      messages   = VALUE #( ( role = `user` content = iv_prompt ) ) )
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    endpoint_of( EXPORTING is_setup       = is_setup
                 IMPORTING es_endpoint    = DATA(ls_endpoint)
                           ev_path_prefix = DATA(lv_prefix) ).
    DATA(lt_headers) = VALUE zcl_ab_bolt_http=>ty_t_header( ( name = `Content-Type` value = `application/json` ) ).
    DATA lv_path TYPE string.
    IF is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-anthropic.
      lv_path = lv_prefix && `/messages`.
      APPEND VALUE #( name = `x-api-key`         value = lv_key ) TO lt_headers.
      APPEND VALUE #( name = `anthropic-version` value = `2023-06-01` ) TO lt_headers.
    ELSE.
      lv_path = lv_prefix && `/chat/completions`.
      APPEND VALUE #( name = `Authorization` value = |Bearer { lv_key }| ) TO lt_headers.
      " Azure OpenAI accepts this header instead of a bearer token.
      APPEND VALUE #( name = `api-key` value = lv_key ) TO lt_headers.
    ENDIF.

    DATA(ls_resp) = zcl_ab_bolt_http=>call( is_endpoint = ls_endpoint
                                            iv_method   = `POST`
                                            iv_path     = lv_path
                                            iv_body     = lv_body
                                            it_headers  = lt_headers
                                            iv_timeout  = 180 ).
    IF ls_resp-code <> 200.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |The AI provider answered HTTP { ls_resp-code }: { error_text( ls_resp-body ) }| ).
    ENDIF.

    IF is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-anthropic.
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
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `The AI provider answered, but with no text.` ).
    ENDIF.
  ENDMETHOD.


  METHOD test.
    IF is_setup-ai_provider = zcl_ab_bolt_config=>gc_provider-mock OR is_setup-ai_provider IS INITIAL.
      rv_text = `Connection OK - Built-in (offline) (built-in) responded.`.
      RETURN.
    ENDIF.
    complete( is_setup      = is_setup
              iv_prompt     = `Reply with the single word OK to confirm the connection works.`
              iv_max_tokens = 16
              iv_key        = iv_key ).
    rv_text = |Connection OK - { label_of( is_setup-ai_provider ) } ({ model_of( is_setup ) }) responded.|.
  ENDMETHOD.

ENDCLASS.
