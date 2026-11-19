"! Buffer between the actions (interaction phase) and the saver (save phase):
"! the GitHub token and the AI key are written to ZABT_BOLT_SECRT only in
"! save_modified, the RAP-sanctioned place for additional database writes.
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_secret,
        secret_id TYPE zabt_bolt_secrt-secret_id,
        value     TYPE string,
      END OF ty_secret,
      ty_t_secret TYPE SORTED TABLE OF ty_secret WITH UNIQUE KEY secret_id.

    CLASS-DATA gt_pending TYPE ty_t_secret.

    "! Blank value = remove the secret.
    CLASS-METHODS set
      IMPORTING iv_secret_id TYPE zabt_bolt_secrt-secret_id
                iv_value     TYPE string.
ENDCLASS.


CLASS lcl_buffer IMPLEMENTATION.

  METHOD set.
    DELETE gt_pending WHERE secret_id = iv_secret_id.
    gt_pending = VALUE #( BASE gt_pending ( secret_id = iv_secret_id value = iv_value ) ).
  ENDMETHOD.

ENDCLASS.


CLASS lhc_setup DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    TYPES ty_s_setup TYPE STRUCTURE FOR READ RESULT zab_cds_i_bolt_setup\\Setup.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Setup RESULT result.

    METHODS initialize FOR MODIFY
      IMPORTING keys FOR ACTION Setup~initialize RESULT result.

    METHODS connectgithub FOR MODIFY
      IMPORTING keys FOR ACTION Setup~connectGitHub RESULT result.

    METHODS disconnectgithub FOR MODIFY
      IMPORTING keys FOR ACTION Setup~disconnectGitHub RESULT result.

    METHODS checkrepo FOR MODIFY
      IMPORTING keys FOR ACTION Setup~checkRepo RESULT result.

    METHODS createrepo FOR MODIFY
      IMPORTING keys FOR ACTION Setup~createRepo RESULT result.

    METHODS saverepo FOR MODIFY
      IMPORTING keys FOR ACTION Setup~saveRepo RESULT result.

    METHODS saveai FOR MODIFY
      IMPORTING keys FOR ACTION Setup~saveAi RESULT result.

    METHODS testai FOR MODIFY
      IMPORTING keys FOR ACTION Setup~testAi RESULT result.

    METHODS checksettings FOR VALIDATE ON SAVE
      IMPORTING keys FOR Setup~checkSettings.

    "! The setup row as the database row type (for the service classes).
    METHODS to_row
      IMPORTING is_setup      TYPE ty_s_setup
      RETURNING VALUE(rs_row) TYPE zabt_bolt_setup.

    "! GitHub client for the token stored (or just pasted) and the setup's endpoint.
    METHODS github_of
      IMPORTING is_setup         TYPE ty_s_setup
                iv_token         TYPE string OPTIONAL
      RETURNING VALUE(ro_github) TYPE REF TO zcl_ab_bolt_github
      RAISING   zcx_ab_bolt.

    "! The one-line result of Check access, worded like TargetRepo.jsx.
    METHODS access_text
      IMPORTING is_info        TYPE zcl_ab_bolt_github=>ty_repo_info
      RETURNING VALUE(rv_text) TYPE string.

    METHODS cut
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS lhc_setup IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Changing the configuration is an administrator task (the web app's admin
    " password is replaced by the Administrators list; blank = first set-up,
    " everyone). Opening the page (initialize) is allowed for every app user.
    DATA(lv_admin) = COND #( WHEN zcl_ab_bolt_config=>is_admin( ) = abap_true
                             THEN if_abap_behv=>auth-allowed
                             ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %update                   = lv_admin
                      %action-initialize        = if_abap_behv=>auth-allowed
                      %action-connectGitHub     = lv_admin
                      %action-disconnectGitHub  = lv_admin
                      %action-checkRepo         = lv_admin
                      %action-createRepo        = lv_admin
                      %action-saveRepo          = lv_admin
                      %action-saveAi            = lv_admin
                      %action-testAi            = lv_admin ).
  ENDMETHOD.


  METHOD cut.
    rv_text = COND #( WHEN strlen( iv_text ) > 255 THEN substring( val = iv_text len = 255 ) ELSE iv_text ).
  ENDMETHOD.


  METHOD to_row.
    rs_row = VALUE #( setup_id      = is_setup-SetupId
                      customer_name = is_setup-CustomerName
                      admin_users   = is_setup-AdminUsers
                      gh_api_url    = is_setup-GhApiUrl
                      gh_dest       = is_setup-GhDest
                      ssl_id        = is_setup-SslId
                      gh_token_set  = is_setup-GhTokenSet
                      gh_login      = is_setup-GhLogin
                      gh_repo       = is_setup-GhRepo
                      gh_base_branch = is_setup-GhBaseBranch
                      gh_branch_pfx = is_setup-GhBranchPfx
                      status_folder = is_setup-StatusFolder
                      lib_folder    = is_setup-LibFolder
                      ai_provider   = is_setup-AiProvider
                      ai_model      = is_setup-AiModel
                      ai_base_url   = is_setup-AiBaseUrl
                      ai_dest       = is_setup-AiDest
                      ai_max_tokens = is_setup-AiMaxTokens
                      ai_key_set    = is_setup-AiKeySet
                      form_prefixes = is_setup-FormPrefixes
                      count_volume  = is_setup-CountVolume ).
  ENDMETHOD.


  METHOD github_of.
    DATA(lv_token) = COND string( WHEN iv_token IS NOT INITIAL THEN iv_token
                                  ELSE zcl_ab_bolt_config=>get_secret( zcl_ab_bolt_config=>gc_secret-github_token ) ).
    IF lv_token IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Connect a GitHub token first.` ).
    ENDIF.
    ro_github = NEW zcl_ab_bolt_github( is_endpoint = zcl_ab_bolt_github=>endpoint_of( to_row( is_setup ) )
                                        iv_token    = lv_token ).
  ENDMETHOD.


  METHOD access_text.
    rv_text = |✓ { is_info-full_name } · { COND string( WHEN is_info-private = abap_true THEN `private` ELSE `public` ) } | &&
              |· default branch { is_info-default_branch } · | &&
              |{ COND string( WHEN is_info-can_push = abap_true THEN `push access` ELSE `read-only` ) }|.
  ENDMETHOD.


  METHOD initialize.
    " Creates the setup row with the defaults the first time the app opens;
    " afterwards it only returns the existing row.
    DATA(ls_key) = keys[ 1 ].
    DATA(lv_id) = zcl_ab_bolt_config=>gc_setup_id.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH VALUE #( ( SetupId = lv_id ) )
      RESULT DATA(lt_existing).

    IF lt_existing IS INITIAL.
      DATA(ls_default) = zcl_ab_bolt_config=>default_setup( ).
      MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
        ENTITY Setup
          CREATE FIELDS ( SetupId GhApiUrl SslId GhBranchPfx StatusFolder LibFolder AiProvider AiMaxTokens
                          FormPrefixes CountVolume )
          WITH VALUE #( ( %cid         = 'SETUP'
                          SetupId      = lv_id
                          GhApiUrl     = ls_default-gh_api_url
                          SslId        = ls_default-ssl_id
                          GhBranchPfx  = ls_default-gh_branch_pfx
                          StatusFolder = ls_default-status_folder
                          LibFolder    = ls_default-lib_folder
                          AiProvider   = ls_default-ai_provider
                          AiMaxTokens  = ls_default-ai_max_tokens
                          FormPrefixes = ls_default-form_prefixes
                          CountVolume  = ls_default-count_volume ) ).
    ENDIF.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH VALUE #( ( SetupId = lv_id ) )
      RESULT DATA(lt_setup).
    result = VALUE #( FOR ls_setup IN lt_setup ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_setup ) ) ).
  ENDMETHOD.


  METHOD connectgithub.
    " Same as PUT /api/github/connection: validate against GitHub, then store.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(lv_token) = condense( ls_key-%param-Token ).
      TRY.
          IF lv_token IS INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Paste a GitHub token to connect.` ).
          ENDIF.
          DATA(ls_user) = github_of( is_setup = ls_setup iv_token = lv_token )->verify_token( ).
          lcl_buffer=>set( iv_secret_id = zcl_ab_bolt_config=>gc_secret-github_token
                           iv_value     = zcl_ab_bolt_config=>encode_secret( lv_token ) ).
          MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
            ENTITY Setup
              UPDATE FIELDS ( GhTokenSet GhLogin GhUserName GhScopes GhConnectedAt )
              WITH VALUE #( ( %tky          = ls_setup-%tky
                              GhTokenSet    = abap_true
                              GhLogin       = ls_user-login
                              GhUserName    = ls_user-name
                              GhScopes      = cut( ls_user-scopes )
                              GhConnectedAt = zcl_ab_bolt_config=>now( ) ) ).
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                        text     = |Connected as { ls_user-login } ({ ls_user-name }).| ) )
            TO reported-setup.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-setup.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD disconnectgithub.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      lcl_buffer=>set( iv_secret_id = zcl_ab_bolt_config=>gc_secret-github_token iv_value = `` ).
      MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( GhTokenSet GhLogin GhUserName GhScopes GhConnectedAt GhCanPush GhCheckRes GhCheckMsg )
          WITH VALUE #( ( %tky          = ls_setup-%tky
                          GhTokenSet    = abap_false
                          GhLogin       = ``
                          GhUserName    = ``
                          GhScopes      = ``
                          GhConnectedAt = 0
                          GhCanPush     = abap_false
                          GhCheckRes    = ``
                          GhCheckMsg    = `` ) ).
      APPEND VALUE #( %tky = ls_setup-%tky
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                    text     = `GitHub disconnected - the token was removed from this system.` ) )
        TO reported-setup.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD checkrepo.
    " Same as POST /api/github/check-repo: a check only - Save repository
    " settings stores the repository. The result is kept for the status chip.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(lv_repo) = COND string( WHEN ls_key-%param-Repo IS NOT INITIAL THEN CONV #( ls_key-%param-Repo )
                                   ELSE CONV #( ls_setup-GhRepo ) ).
      TRY.
          DATA(ls_info) = github_of( ls_setup )->check_repo( lv_repo ).
          DATA(lv_text) = access_text( ls_info ).
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text(
                                   severity = COND #( WHEN ls_info-can_push = abap_true
                                                      THEN if_abap_behv_message=>severity-success
                                                      ELSE if_abap_behv_message=>severity-warning )
                                   text     = lv_text ) ) TO reported-setup.
          " Keep the check result only for the repository that is saved.
          IF zcl_ab_bolt_github=>parse_repo( ls_setup-GhRepo )-full_name = ls_info-full_name.
            MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
              ENTITY Setup
                UPDATE FIELDS ( GhPrivate GhCanPush GhBaseBranch GhCheckRes GhCheckMsg GhCheckedAt )
                WITH VALUE #( ( %tky         = ls_setup-%tky
                                GhPrivate    = ls_info-private
                                GhCanPush    = ls_info-can_push
                                GhBaseBranch = ls_info-default_branch
                                GhCheckRes   = COND #( WHEN ls_info-can_push = abap_true THEN zcl_ab_bolt_config=>gc_check-ok
                                                       ELSE zcl_ab_bolt_config=>gc_check-error )
                                GhCheckMsg   = cut( lv_text )
                                GhCheckedAt  = zcl_ab_bolt_config=>now( ) ) ).
          ENDIF.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          " A check that fails is an answer, not an error: shown, nothing changed.
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                        text     = lx_error->get_text( ) ) ) TO reported-setup.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD createrepo.
    " Same as POST /api/github/create-repo: private, in the connected account,
    " with an initial commit. The new repository becomes the target repository.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      TRY.
          DATA(ls_info) = github_of( ls_setup )->create_repo( iv_name  = ls_key-%param-Repo
                                                              iv_login = ls_setup-GhLogin ).
          DATA(lv_text) = |Created { ls_info-full_name } (private, default branch { ls_info-default_branch }) - it is now the target repository.|.
          MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
            ENTITY Setup
              UPDATE FIELDS ( GhRepo GhPrivate GhCanPush GhBaseBranch GhCheckRes GhCheckMsg GhCheckedAt )
              WITH VALUE #( ( %tky         = ls_setup-%tky
                              GhRepo       = ls_info-full_name
                              GhPrivate    = ls_info-private
                              GhCanPush    = abap_true
                              GhBaseBranch = ls_info-default_branch
                              GhCheckRes   = zcl_ab_bolt_config=>gc_check-ok
                              GhCheckMsg   = cut( access_text( ls_info ) )
                              GhCheckedAt  = zcl_ab_bolt_config=>now( ) ) ).
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                        text     = lv_text ) ) TO reported-setup.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-setup.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD saverepo.
    " "Save repository settings": the repository must be reachable with push
    " access before it is stored, so a typo can never break the next Commit.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(lv_prefix) = to_lower( condense( CONV string( ls_key-%param-BranchPrefix ) ) ).
      TRY.
          DATA(ls_info) = github_of( ls_setup )->check_repo( ls_key-%param-Repo ).
          IF ls_info-can_push = abap_false.
            RAISE EXCEPTION NEW zcx_ab_bolt(
              iv_text = |{ access_text( ls_info ) } - the token cannot push to this repository, so it was not saved.| ).
          ENDIF.
          FIND REGEX '^[a-z0-9._-]*$' IN lv_prefix.
          IF sy-subrc <> 0.
            RAISE EXCEPTION NEW zcx_ab_bolt(
              iv_text = `Use only lower-case letters, numbers, dots, dashes and underscores in the branch prefix.` ).
          ENDIF.
          MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
            ENTITY Setup
              UPDATE FIELDS ( GhRepo GhBranchPfx GhPrivate GhCanPush GhBaseBranch GhCheckRes GhCheckMsg GhCheckedAt )
              WITH VALUE #( ( %tky         = ls_setup-%tky
                              GhRepo       = ls_info-full_name
                              GhBranchPfx  = lv_prefix
                              GhPrivate    = ls_info-private
                              GhCanPush    = ls_info-can_push
                              GhBaseBranch = ls_info-default_branch
                              GhCheckRes   = zcl_ab_bolt_config=>gc_check-ok
                              GhCheckMsg   = cut( access_text( ls_info ) )
                              GhCheckedAt  = zcl_ab_bolt_config=>now( ) ) ).
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                        text     = `Repository settings saved.` ) ) TO reported-setup.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
          APPEND VALUE #( %tky = ls_setup-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-setup.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD saveai.
    " The AI card's Save (PUT /api/ai/settings): provider, model, base URL, max
    " tokens and - when typed - the key. A provider that needs a key cannot be
    " saved without one.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(lv_provider) = CONV zabt_bolt_setup-ai_provider( to_lower( condense( CONV string( ls_key-%param-Provider ) ) ) ).
      IF lv_provider IS INITIAL.
        lv_provider = zcl_ab_bolt_config=>gc_provider-mock.
      ENDIF.
      DATA(lv_key) = condense( ls_key-%param-ApiKey ).
      DATA(lv_needs_key) = xsdbool( lv_provider <> zcl_ab_bolt_config=>gc_provider-mock ).
      " A stored key belongs to the provider it was saved for (keyIsSaved in AiSettings.jsx).
      DATA(lv_key_saved) = xsdbool( ls_setup-AiKeySet = abap_true AND ls_setup-AiProvider = lv_provider ).

      IF lv_provider <> zcl_ab_bolt_config=>gc_provider-mock
         AND lv_provider <> zcl_ab_bolt_config=>gc_provider-openai
         AND lv_provider <> zcl_ab_bolt_config=>gc_provider-anthropic.
        APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
        APPEND VALUE #( %tky = ls_setup-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Unknown AI provider "{ lv_provider }".| ) ) TO reported-setup.
        CONTINUE.
      ENDIF.
      IF lv_needs_key = abap_true AND lv_key IS INITIAL AND lv_key_saved = abap_false.
        APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
        APPEND VALUE #( %tky = ls_setup-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Enter an API key for this provider to save or test.` ) ) TO reported-setup.
        CONTINUE.
      ENDIF.

      DATA(lv_key_set) = ls_setup-AiKeySet.
      IF lv_key IS NOT INITIAL.
        lcl_buffer=>set( iv_secret_id = zcl_ab_bolt_config=>gc_secret-ai_key
                         iv_value     = zcl_ab_bolt_config=>encode_secret( lv_key ) ).
        lv_key_set = abap_true.
      ELSEIF lv_needs_key = abap_false.
        lcl_buffer=>set( iv_secret_id = zcl_ab_bolt_config=>gc_secret-ai_key iv_value = `` ).
        lv_key_set = abap_false.
      ENDIF.

      MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( AiProvider AiModel AiBaseUrl AiMaxTokens AiKeySet )
          WITH VALUE #( ( %tky        = ls_setup-%tky
                          AiProvider  = lv_provider
                          AiModel     = ls_key-%param-Model
                          AiBaseUrl   = ls_key-%param-BaseUrl
                          AiMaxTokens = COND #( WHEN ls_key-%param-MaxTokens > 0 THEN ls_key-%param-MaxTokens
                                                ELSE zcl_ab_bolt_config=>gc_default_tokens )
                          AiKeySet    = lv_key_set ) ).
      APPEND VALUE #( %tky = ls_setup-%tky
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                    text     = |AI provider saved - { zcl_ab_bolt_ai=>label_of( lv_provider ) }.| ) )
        TO reported-setup.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD testai.
    " Test connection with the values on the screen (saved or not), like
    " POST /api/ai/test. The result is kept for the AI chip.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(ls_row) = to_row( ls_setup ).
      ls_row-ai_provider   = to_lower( condense( CONV string( ls_key-%param-Provider ) ) ).
      ls_row-ai_model      = ls_key-%param-Model.
      ls_row-ai_base_url   = ls_key-%param-BaseUrl.
      ls_row-ai_max_tokens = ls_key-%param-MaxTokens.
      DATA lv_res  TYPE zabt_bolt_setup-ai_check_res.
      DATA lv_text TYPE string.
      TRY.
          lv_text = zcl_ab_bolt_ai=>test( is_setup = ls_row iv_key = condense( ls_key-%param-ApiKey ) ).
          lv_res  = zcl_ab_bolt_config=>gc_check-ok.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          lv_text = lx_error->get_text( ).
          lv_res  = zcl_ab_bolt_config=>gc_check-error.
      ENDTRY.
      MODIFY ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( AiCheckRes AiCheckMsg AiCheckedAt )
          WITH VALUE #( ( %tky        = ls_setup-%tky
                          AiCheckRes  = lv_res
                          AiCheckMsg  = cut( lv_text )
                          AiCheckedAt = zcl_ab_bolt_config=>now( ) ) ).
      APPEND VALUE #( %tky = ls_setup-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN lv_res = zcl_ab_bolt_config=>gc_check-ok
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-warning )
                               text     = lv_text ) ) TO reported-setup.
      CLEAR: lv_res, lv_text.
    ENDLOOP.

    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD checksettings.
    READ ENTITIES OF zab_cds_i_bolt_setup IN LOCAL MODE
      ENTITY Setup FIELDS ( AdminUsers FormPrefixes StatusFolder LibFolder ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      DATA lt_problems TYPE string_table.
      CLEAR lt_problems.

      " Never lock yourself out: whoever fills the list must be on it.
      DATA(lv_admins) = condense( to_upper( CONV string( ls_setup-AdminUsers ) ) ).
      IF lv_admins IS NOT INITIAL.
        SPLIT lv_admins AT ',' INTO TABLE DATA(lt_admins).
        DATA(lv_me) = to_upper( CONV string( sy-uname ) ).
        DATA(lv_found) = abap_false.
        LOOP AT lt_admins INTO DATA(lv_admin).
          IF condense( lv_admin ) = lv_me.
            lv_found = abap_true.
          ENDIF.
        ENDLOOP.
        IF lv_found = abap_false.
          APPEND |Add your own user ID ({ sy-uname }) to the administrators, or you lose access to this page.| TO lt_problems.
        ENDIF.
      ENDIF.

      DATA(lv_prefixes) = to_upper( condense( CONV string( ls_setup-FormPrefixes ) ) ).
      FIND REGEX '^[A-Z0-9/]+(\s*,\s*[A-Z0-9/]+)?$' IN lv_prefixes.
      IF sy-subrc <> 0.
        APPEND `Smart Form name prefixes: one or two prefixes, comma separated (for example Z,Y).` TO lt_problems.
      ENDIF.

      DATA(lt_folders) = VALUE string_table( ( condense( CONV string( ls_setup-StatusFolder ) ) )
                                             ( condense( CONV string( ls_setup-LibFolder ) ) ) ).
      LOOP AT lt_folders INTO DATA(lv_folder).
        FIND REGEX '^[A-Za-z0-9._/-]*$' IN lv_folder.
        IF sy-subrc <> 0 OR find( val = lv_folder sub = `..` ) >= 0.
          APPEND |Folder "{ lv_folder }": use letters, numbers, . _ - and / only.| TO lt_problems.
        ENDIF.
      ENDLOOP.

      LOOP AT lt_problems INTO DATA(lv_problem).
        APPEND VALUE #( %tky = ls_setup-%tky ) TO failed-setup.
        APPEND VALUE #( %tky = ls_setup-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = lv_problem ) ) TO reported-setup.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


CLASS lsc_zab_cds_i_bolt_setup DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.


CLASS lsc_zab_cds_i_bolt_setup IMPLEMENTATION.

  METHOD save_modified.
    DATA lt_upsert TYPE STANDARD TABLE OF zabt_bolt_secrt WITH EMPTY KEY.
    DATA lt_remove TYPE RANGE OF zabt_bolt_secrt-secret_id.

    LOOP AT lcl_buffer=>gt_pending INTO DATA(ls_pending).
      IF ls_pending-value IS INITIAL.
        lt_remove = VALUE #( BASE lt_remove ( sign = 'I' option = 'EQ' low = ls_pending-secret_id ) ).
      ELSE.
        APPEND VALUE #( secret_id    = ls_pending-secret_id
                        secret_value = ls_pending-value
                        changed_by   = sy-uname
                        changed_at   = zcl_ab_bolt_config=>now( ) ) TO lt_upsert.
      ENDIF.
    ENDLOOP.
    IF lt_remove IS NOT INITIAL.
      DELETE FROM zabt_bolt_secrt WHERE secret_id IN @lt_remove.
    ENDIF.
    IF lt_upsert IS NOT INITIAL.
      MODIFY zabt_bolt_secrt FROM TABLE @lt_upsert.
    ENDIF.
    CLEAR lcl_buffer=>gt_pending.
  ENDMETHOD.


  METHOD cleanup_finalize.
    CLEAR lcl_buffer=>gt_pending.
  ENDMETHOD.

ENDCLASS.
