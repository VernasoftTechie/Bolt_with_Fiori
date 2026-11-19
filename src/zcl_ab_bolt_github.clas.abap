"! <p class="shorttext synchronized">Bolt - GitHub REST client</p>
"! Same calls and the same messages as Bolt Console's server/src/github.js:
"! verify a pasted token (GET /user + X-OAuth-Scopes), check repository access,
"! create a private repository, and the branch/file operations of a migration.
"! The token is the one pasted on the Configuration tab (ZABT_BOLT_SECRT),
"! sent as "Authorization: Bearer"; it is never returned by the service.
"!
"! A new migration branch is created as ONE commit holding every reference
"! file and the status file, and the branch reference is written last - so a
"! branch never exists half-made. Status writes send the file's blob SHA, so
"! GitHub itself rejects a write based on a stale copy (409) instead of losing
"! an update.
CLASS zcl_ab_bolt_github DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_file,
        path    TYPE string,
        content TYPE xstring,
      END OF ty_file,
      ty_t_file TYPE STANDARD TABLE OF ty_file WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_content,
        found TYPE abap_bool,
        sha   TYPE string,
        text  TYPE string,
      END OF ty_content.

    TYPES:
      BEGIN OF ty_user,
        login  TYPE string,
        name   TYPE string,
        scopes TYPE string,
      END OF ty_user.

    TYPES:
      BEGIN OF ty_repo_ref,
        owner     TYPE string,
        repo      TYPE string,
        full_name TYPE string,
      END OF ty_repo_ref.

    TYPES:
      BEGIN OF ty_repo_info,
        full_name      TYPE string,
        private        TYPE abap_bool,
        default_branch TYPE string,
        can_push       TYPE abap_bool,
        html_url       TYPE string,
      END OF ty_repo_info.

    METHODS constructor
      IMPORTING is_endpoint TYPE zcl_ab_bolt_http=>ty_endpoint
                iv_token    TYPE string
                iv_repo     TYPE string OPTIONAL.

    "! Client for the repository of the setup, with the stored token.
    CLASS-METHODS from_setup
      RETURNING VALUE(ro_github) TYPE REF TO zcl_ab_bolt_github
      RAISING   zcx_ab_bolt.

    "! Client with the stored token but no repository yet (Check access / Create).
    CLASS-METHODS for_stored_token
      RETURNING VALUE(ro_github) TYPE REF TO zcl_ab_bolt_github
      RAISING   zcx_ab_bolt.

    "! Endpoint (API URL / SM59 / SSL client) of the setup.
    CLASS-METHODS endpoint_of
      IMPORTING is_setup           TYPE zabt_bolt_setup
      RETURNING VALUE(rs_endpoint) TYPE zcl_ab_bolt_http=>ty_endpoint.

    "! Accepts "owner/repo", https://github.com/owner/repo[.git] or
    "! git@github.com:owner/repo.git (parseRepo in github.js). Initial when invalid.
    CLASS-METHODS parse_repo
      IMPORTING iv_input      TYPE csequence
      RETURNING VALUE(rs_ref) TYPE ty_repo_ref.

    CLASS-METHODS to_utf8
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_data) TYPE xstring.

    "! GET /user with the token; raises with the web app's wording when refused.
    METHODS verify_token
      RETURNING VALUE(rs_user) TYPE ty_user
      RAISING   zcx_ab_bolt.

    METHODS check_repo
      IMPORTING iv_repo        TYPE csequence
      RETURNING VALUE(rs_info) TYPE ty_repo_info
      RAISING   zcx_ab_bolt.

    "! Private repository in the connected account, with an initial commit
    "! (auto_init) so it already has a default branch.
    METHODS create_repo
      IMPORTING iv_name        TYPE csequence
                iv_login       TYPE csequence OPTIONAL
      RETURNING VALUE(rs_info) TYPE ty_repo_info
      RAISING   zcx_ab_bolt.

    "! Head commit SHA of a branch, or initial if the branch does not exist.
    METHODS get_branch_sha
      IMPORTING iv_branch     TYPE string
      RETURNING VALUE(rv_sha) TYPE string
      RAISING   zcx_ab_bolt.

    METHODS default_branch
      RETURNING VALUE(rv_branch) TYPE string
      RAISING   zcx_ab_bolt.

    METHODS create_branch_with_files
      IMPORTING iv_base_branch       TYPE string
                iv_branch            TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_ab_bolt.

    "! Adds/replaces files on an existing branch in one commit.
    METHODS add_files
      IMPORTING iv_branch            TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_ab_bolt.

    "! Reads one text file (UTF-8). found = false when it does not exist.
    METHODS get_file
      IMPORTING iv_branch         TYPE string
                iv_path           TYPE string
      RETURNING VALUE(rs_content) TYPE ty_content
      RAISING   zcx_ab_bolt.

    "! Writes one text file. iv_sha = SHA of the copy that was read (initial for
    "! a new file). Returns true when GitHub refused because the file changed
    "! meanwhile - the caller re-reads and re-applies.
    METHODS put_file
      IMPORTING iv_branch          TYPE string
                iv_path            TYPE string
                iv_text            TYPE string
                iv_sha             TYPE string
                iv_message         TYPE string
      RETURNING VALUE(rv_conflict) TYPE abap_bool
      RAISING   zcx_ab_bolt.

    METHODS web_url
      IMPORTING iv_branch     TYPE string OPTIONAL
      RETURNING VALUE(rv_url) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_sha,
        sha TYPE string,
      END OF ty_sha.

    DATA gs_endpoint TYPE zcl_ab_bolt_http=>ty_endpoint.
    DATA gv_token    TYPE string.
    DATA gs_repo     TYPE ty_repo_ref.

    METHODS request
      IMPORTING iv_method          TYPE string
                iv_path            TYPE string
                iv_body            TYPE string OPTIONAL
      RETURNING VALUE(rs_response) TYPE zcl_ab_bolt_http=>ty_response
      RAISING   zcx_ab_bolt.

    METHODS repo_path
      IMPORTING iv_suffix      TYPE string
      RETURNING VALUE(rv_path) TYPE string
      RAISING   zcx_ab_bolt.

    "! Raises with GitHub's own error message for an unexpected status.
    METHODS fail
      IMPORTING is_response TYPE zcl_ab_bolt_http=>ty_response
                iv_action   TYPE string
      RAISING   zcx_ab_bolt.

    "! Message for a 403 (rate limit, SSO, missing permission) - forbiddenMessage in github.js.
    METHODS forbidden_text
      IMPORTING is_response   TYPE zcl_ab_bolt_http=>ty_response
      RETURNING VALUE(rv_text) TYPE string.

    METHODS server_text
      IMPORTING is_response   TYPE zcl_ab_bolt_http=>ty_response
      RETURNING VALUE(rv_text) TYPE string.

    METHODS build_commit
      IMPORTING iv_parent_sha        TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_ab_bolt.

    METHODS read_sha
      IMPORTING iv_json       TYPE string
      RETURNING VALUE(rv_sha) TYPE string.

    METHODS to_info
      IMPORTING iv_json        TYPE string
      RETURNING VALUE(rs_info) TYPE ty_repo_info.
ENDCLASS.



CLASS zcl_ab_bolt_github IMPLEMENTATION.

  METHOD constructor.
    gs_endpoint = is_endpoint.
    gv_token    = condense( iv_token ).
    IF iv_repo IS SUPPLIED AND iv_repo IS NOT INITIAL.
      gs_repo = parse_repo( iv_repo ).
    ENDIF.
  ENDMETHOD.


  METHOD endpoint_of.
    rs_endpoint = VALUE #( base_url    = condense( CONV string( is_setup-gh_api_url ) )
                           destination = is_setup-gh_dest
                           ssl_id      = is_setup-ssl_id ).
    IF rs_endpoint-base_url IS INITIAL.
      rs_endpoint-base_url = zcl_ab_bolt_config=>gc_default_api.
    ENDIF.
  ENDMETHOD.


  METHOD for_stored_token.
    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    DATA(lv_token) = zcl_ab_bolt_config=>get_secret( zcl_ab_bolt_config=>gc_secret-github_token ).
    IF lv_token IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Connect a GitHub token first (Configuration > 1. Connections > GitHub).` ).
    ENDIF.
    ro_github = NEW zcl_ab_bolt_github( is_endpoint = endpoint_of( ls_setup )
                                        iv_token    = lv_token ).
  ENDMETHOD.


  METHOD from_setup.
    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    DATA(lv_token) = zcl_ab_bolt_config=>get_secret( zcl_ab_bolt_config=>gc_secret-github_token ).
    IF lv_token IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `GitHub is not connected - paste a token on the Configuration tab.` ).
    ENDIF.
    IF parse_repo( ls_setup-gh_repo ) IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `No target repository is set - enter it on the Configuration tab (2. Repository).` ).
    ENDIF.
    ro_github = NEW zcl_ab_bolt_github( is_endpoint = endpoint_of( ls_setup )
                                        iv_token    = lv_token
                                        iv_repo     = CONV string( ls_setup-gh_repo ) ).
  ENDMETHOD.


  METHOD parse_repo.
    DATA(lv_text) = condense( CONV string( iv_input ) ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.
    REPLACE FIRST OCCURRENCE OF REGEX '^git@[^:]+:' IN lv_text WITH `` IGNORING CASE.
    REPLACE FIRST OCCURRENCE OF REGEX '^https?://[^/]+/' IN lv_text WITH `` IGNORING CASE.
    REPLACE FIRST OCCURRENCE OF REGEX '\.git$' IN lv_text WITH `` IGNORING CASE.
    SPLIT lv_text AT `/` INTO TABLE DATA(lt_parts).
    DELETE lt_parts WHERE table_line IS INITIAL.
    IF lines( lt_parts ) < 2.
      RETURN.
    ENDIF.
    rs_ref = VALUE #( owner     = lt_parts[ 1 ]
                      repo      = lt_parts[ 2 ]
                      full_name = |{ lt_parts[ 1 ] }/{ lt_parts[ 2 ] }| ).
  ENDMETHOD.


  METHOD to_utf8.
    rv_data = cl_abap_codepage=>convert_to( source = iv_text codepage = `UTF-8` ).
  ENDMETHOD.


  METHOD repo_path.
    IF gs_repo IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `No target repository is set - enter it on the Configuration tab (2. Repository).` ).
    ENDIF.
    rv_path = |/repos/{ gs_repo-owner }/{ gs_repo-repo }{ iv_suffix }|.
  ENDMETHOD.


  METHOD web_url.
    rv_url = COND #( WHEN iv_branch IS INITIAL
                     THEN |https://github.com/{ gs_repo-full_name }|
                     ELSE |https://github.com/{ gs_repo-full_name }/tree/{ iv_branch }| ).
  ENDMETHOD.


  METHOD request.
    DATA(lt_headers) = VALUE zcl_ab_bolt_http=>ty_t_header(
      ( name = `Accept`               value = `application/vnd.github+json` )
      ( name = `X-GitHub-Api-Version` value = `2022-11-28` )
      ( name = `User-Agent`           value = `Bolt-with-Fiori` )
      ( name = `Authorization`        value = |Bearer { gv_token }| ) ).
    IF iv_body IS NOT INITIAL.
      APPEND VALUE #( name = `Content-Type` value = `application/json; charset=utf-8` ) TO lt_headers.
    ENDIF.
    rs_response = zcl_ab_bolt_http=>call( is_endpoint = gs_endpoint
                                          iv_method   = iv_method
                                          iv_path     = iv_path
                                          iv_body     = iv_body
                                          it_headers  = lt_headers ).
  ENDMETHOD.


  METHOD forbidden_text.
    IF zcl_ab_bolt_http=>header_value( is_response = is_response iv_name = `x-ratelimit-remaining` ) = `0`.
      rv_text = `GitHub's rate limit for this token is used up. Wait a few minutes and try again.`.
    ELSEIF zcl_ab_bolt_http=>header_value( is_response = is_response iv_name = `x-github-sso` ) IS NOT INITIAL.
      rv_text = `Your organization requires single sign-on for this token. Authorize the token for the organization on GitHub (Settings > Tokens > Configure SSO), then try again.`.
    ELSE.
      rv_text = `GitHub refused the request - the token does not have permission for this. Check the token's repository access and permissions.`.
    ENDIF.
  ENDMETHOD.


  METHOD server_text.
    rv_text = COND #( WHEN is_response-code >= 500
                      THEN `GitHub is having problems right now (server error). Please try again in a little while.`
                      ELSE |GitHub couldn't complete the request (error { is_response-code }). Please try again.| ).
  ENDMETHOD.


  METHOD fail.
    TYPES:
      BEGIN OF ty_error,
        message TYPE string,
      END OF ty_error.
    DATA ls_error TYPE ty_error.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = is_response-body
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                   CHANGING  data        = ls_error ).
      CATCH cx_root ##CATCH_ALL.
        CLEAR ls_error.
    ENDTRY.
    DATA(lv_hint) = SWITCH string( is_response-code
      WHEN 401 THEN ` The GitHub token was not accepted - reconnect with a fresh token on the Configuration tab.`
      WHEN 403 THEN | { forbidden_text( is_response ) }|
      WHEN 404 THEN ` The repository or branch was not found, or the token cannot see it.`
      ELSE `` ).
    RAISE EXCEPTION NEW zcx_ab_bolt(
      iv_text = |GitHub refused to { iv_action } (HTTP { is_response-code }{ COND string( WHEN ls_error-message IS NOT INITIAL THEN `: ` && ls_error-message ) }).{ lv_hint }| ).
  ENDMETHOD.


  METHOD read_sha.
    DATA ls_sha TYPE ty_sha.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                   CHANGING  data        = ls_sha ).
      CATCH cx_root ##CATCH_ALL.
        CLEAR ls_sha.
    ENDTRY.
    rv_sha = ls_sha-sha.
  ENDMETHOD.


  METHOD to_info.
    TYPES:
      BEGIN OF ty_permissions,
        push TYPE abap_bool,
      END OF ty_permissions,
      BEGIN OF ty_repo,
        full_name      TYPE string,
        private        TYPE abap_bool,
        default_branch TYPE string,
        html_url       TYPE string,
        permissions    TYPE ty_permissions,
      END OF ty_repo.
    DATA ls_repo TYPE ty_repo.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                   CHANGING  data        = ls_repo ).
      CATCH cx_root ##CATCH_ALL.
        CLEAR ls_repo.
    ENDTRY.
    rs_info = VALUE #( full_name      = ls_repo-full_name
                       private        = ls_repo-private
                       default_branch = ls_repo-default_branch
                       can_push       = ls_repo-permissions-push
                       html_url       = ls_repo-html_url ).
  ENDMETHOD.


  METHOD verify_token.
    TYPES:
      BEGIN OF ty_user_json,
        login TYPE string,
        name  TYPE string,
      END OF ty_user_json.
    DATA ls_json TYPE ty_user_json.

    IF gv_token IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Paste a GitHub token to connect.` ).
    ENDIF.
    DATA(ls_resp) = request( iv_method = `GET` iv_path = `/user` ).
    CASE ls_resp-code.
      WHEN 200.
      WHEN 401.
        RAISE EXCEPTION NEW zcx_ab_bolt(
          iv_text = `That token wasn't accepted by GitHub. Copy a fresh token - it may be wrong, expired, or missing a character - and paste it again.` ).
      WHEN 403.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = forbidden_text( ls_resp ) ).
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = server_text( ls_resp ) ).
    ENDCASE.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_json ).
    rs_user = VALUE #( login  = ls_json-login
                       name   = COND #( WHEN ls_json-name IS NOT INITIAL THEN ls_json-name ELSE ls_json-login )
                       scopes = condense( zcl_ab_bolt_http=>header_value( is_response = ls_resp iv_name = `x-oauth-scopes` ) ) ).
  ENDMETHOD.


  METHOD check_repo.
    DATA(ls_ref) = parse_repo( iv_repo ).
    IF ls_ref IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = `That doesn't look like a repository address. Use owner/name (like octocat/Hello-World) or the full https://github.com/... URL.` ).
    ENDIF.
    DATA(ls_resp) = request( iv_method = `GET` iv_path = |/repos/{ ls_ref-owner }/{ ls_ref-repo }| ).
    CASE ls_resp-code.
      WHEN 200.
      WHEN 404.
        RAISE EXCEPTION NEW zcx_ab_bolt(
          iv_text = |Couldn't find "{ ls_ref-full_name }", or your token can't access it. Check the repository owner/name and that your token has access.| ).
      WHEN 401.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `That token wasn't accepted by GitHub. Reconnect with a fresh token on this page.` ).
      WHEN 403.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = forbidden_text( ls_resp ) ).
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = server_text( ls_resp ) ).
    ENDCASE.
    rs_info = to_info( ls_resp-body ).
    gs_repo = parse_repo( rs_info-full_name ).
  ENDMETHOD.


  METHOD create_repo.
    TYPES:
      BEGIN OF ty_create,
        name        TYPE string,
        private     TYPE abap_bool,
        auto_init   TYPE abap_bool,
        description TYPE string,
      END OF ty_create.

    DATA(lv_name) = condense( CONV string( iv_name ) ).
    " A full owner/name may be typed - the repository is always created in the connected account.
    DATA(ls_ref) = parse_repo( lv_name ).
    IF ls_ref IS NOT INITIAL.
      lv_name = ls_ref-repo.
    ENDIF.
    FIND REGEX '^[A-Za-z0-9._-]{1,100}$' IN lv_name.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = `Use only letters, numbers, dots, dashes and underscores in the repository name (no spaces).` ).
    ENDIF.

    DATA(lv_body) = /ui2/cl_json=>serialize(
      data        = VALUE ty_create( name        = lv_name
                                     private     = abap_true
                                     auto_init   = abap_true
                                     description = `Bolt migration repository` )
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
    DATA(ls_resp) = request( iv_method = `POST` iv_path = `/user/repos` iv_body = lv_body ).
    CASE ls_resp-code.
      WHEN 201.
      WHEN 422.
        RAISE EXCEPTION NEW zcx_ab_bolt(
          iv_text = |A repository named "{ lv_name }" already exists{ COND string( WHEN iv_login IS NOT INITIAL THEN | under { iv_login }| ) }. Choose a different name.| ).
      WHEN 401.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `That token wasn't accepted by GitHub. Reconnect with a fresh token on this page.` ).
      WHEN 403 OR 404.
        RAISE EXCEPTION NEW zcx_ab_bolt(
          iv_text = `This token isn't allowed to create repositories. Use a token with permission to create repos (classic: 'repo' scope; ` &&
                    `fine-grained: Administration - read & write on all repositories), or create the repository on GitHub yourself and enter it below.` ).
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = server_text( ls_resp ) ).
    ENDCASE.
    rs_info = to_info( ls_resp-body ).
    rs_info-can_push = abap_true.
    gs_repo = parse_repo( rs_info-full_name ).
  ENDMETHOD.


  METHOD default_branch.
    DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( `` ) ).
    IF ls_resp-code <> 200.
      fail( is_response = ls_resp iv_action = |open repository { gs_repo-full_name }| ).
    ENDIF.
    rv_branch = to_info( ls_resp-body )-default_branch.
  ENDMETHOD.


  METHOD get_branch_sha.
    TYPES:
      BEGIN OF ty_ref,
        ref    TYPE string,
        object TYPE ty_sha,
      END OF ty_ref.
    DATA ls_ref TYPE ty_ref.

    DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( |/git/ref/heads/{ iv_branch }| ) ).
    IF ls_resp-code = 404.
      CLEAR rv_sha.
      RETURN.
    ENDIF.
    IF ls_resp-code <> 200.
      fail( is_response = ls_resp iv_action = |read branch { iv_branch }| ).
    ENDIF.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_ref ).
    rv_sha = ls_ref-object-sha.
  ENDMETHOD.


  METHOD build_commit.
    TYPES:
      BEGIN OF ty_commit_res,
        sha  TYPE string,
        tree TYPE ty_sha,
      END OF ty_commit_res,
      BEGIN OF ty_blob_req,
        content  TYPE string,
        encoding TYPE string,
      END OF ty_blob_req,
      BEGIN OF ty_tree_item,
        path TYPE string,
        mode TYPE string,
        type TYPE string,
        sha  TYPE string,
      END OF ty_tree_item,
      ty_t_tree_item TYPE STANDARD TABLE OF ty_tree_item WITH EMPTY KEY,
      BEGIN OF ty_tree_req,
        base_tree TYPE string,
        tree      TYPE ty_t_tree_item,
      END OF ty_tree_req,
      BEGIN OF ty_commit_req,
        message TYPE string,
        tree    TYPE string,
        parents TYPE string_table,
      END OF ty_commit_req.

    DATA ls_parent   TYPE ty_commit_res.
    DATA ls_tree_req TYPE ty_tree_req.

    " 1. the tree of the parent commit
    DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( |/git/commits/{ iv_parent_sha }| ) ).
    IF ls_resp-code <> 200.
      fail( is_response = ls_resp iv_action = |read commit { iv_parent_sha }| ).
    ENDIF.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_parent ).

    " 2. one blob per file (base64 - exact bytes)
    LOOP AT it_files INTO DATA(ls_file).
      DATA(lv_blob_json) = /ui2/cl_json=>serialize(
        data        = VALUE ty_blob_req( content  = cl_http_utility=>encode_x_base64( ls_file-content )
                                         encoding = `base64` )
        pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
      ls_resp = request( iv_method = `POST` iv_path = repo_path( `/git/blobs` ) iv_body = lv_blob_json ).
      IF ls_resp-code <> 201.
        fail( is_response = ls_resp iv_action = |upload { ls_file-path }| ).
      ENDIF.
      APPEND VALUE #( path = ls_file-path mode = `100644` type = `blob` sha = read_sha( ls_resp-body ) )
        TO ls_tree_req-tree.
    ENDLOOP.

    " 3. new tree on top of the parent's tree
    ls_tree_req-base_tree = ls_parent-tree-sha.
    ls_resp = request( iv_method = `POST`
                       iv_path   = repo_path( `/git/trees` )
                       iv_body   = /ui2/cl_json=>serialize( data        = ls_tree_req
                                                            pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).
    IF ls_resp-code <> 201.
      fail( is_response = ls_resp iv_action = `create the file tree` ).
    ENDIF.
    DATA(lv_tree_sha) = read_sha( ls_resp-body ).

    " 4. the commit
    ls_resp = request( iv_method = `POST`
                       iv_path   = repo_path( `/git/commits` )
                       iv_body   = /ui2/cl_json=>serialize(
                                     data        = VALUE ty_commit_req( message = iv_message
                                                                        tree    = lv_tree_sha
                                                                        parents = VALUE #( ( iv_parent_sha ) ) )
                                     pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).
    IF ls_resp-code <> 201.
      fail( is_response = ls_resp iv_action = `create the commit` ).
    ENDIF.
    rv_commit_sha = read_sha( ls_resp-body ).
  ENDMETHOD.


  METHOD create_branch_with_files.
    TYPES:
      BEGIN OF ty_ref_req,
        ref TYPE string,
        sha TYPE string,
      END OF ty_ref_req.

    DATA(lv_base_sha) = get_branch_sha( iv_base_branch ).
    IF lv_base_sha IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |Base branch { iv_base_branch } does not exist in { gs_repo-full_name }.| ).
    ENDIF.

    rv_commit_sha = build_commit( iv_parent_sha = lv_base_sha it_files = it_files iv_message = iv_message ).

    DATA(ls_resp) = request( iv_method = `POST`
                             iv_path   = repo_path( `/git/refs` )
                             iv_body   = /ui2/cl_json=>serialize(
                                           data        = VALUE ty_ref_req( ref = |refs/heads/{ iv_branch }| sha = rv_commit_sha )
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).
    IF ls_resp-code = 422.
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = |A branch named { iv_branch } already exists in { gs_repo-full_name } - it was not overwritten.| ).
    ENDIF.
    IF ls_resp-code <> 201.
      fail( is_response = ls_resp iv_action = |create branch { iv_branch }| ).
    ENDIF.
  ENDMETHOD.


  METHOD add_files.
    TYPES:
      BEGIN OF ty_ref_upd,
        sha   TYPE string,
        force TYPE abap_bool,
      END OF ty_ref_upd.

    " Two attempts: if someone else committed between our read and our write,
    " GitHub refuses the fast-forward (422) and we rebuild on the new head.
    DATA lv_attempt TYPE i.
    DO 2 TIMES.
      lv_attempt += 1.
      DATA(lv_head) = get_branch_sha( iv_branch ).
      IF lv_head IS INITIAL.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |Branch { iv_branch } does not exist any more in { gs_repo-full_name }.| ).
      ENDIF.
      rv_commit_sha = build_commit( iv_parent_sha = lv_head it_files = it_files iv_message = iv_message ).
      DATA(ls_resp) = request( iv_method = `PATCH`
                               iv_path   = repo_path( |/git/refs/heads/{ iv_branch }| )
                               iv_body   = /ui2/cl_json=>serialize(
                                             data        = VALUE ty_ref_upd( sha = rv_commit_sha force = abap_false )
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).
      IF ls_resp-code = 200.
        RETURN.
      ENDIF.
      IF ls_resp-code <> 422 OR lv_attempt = 2.
        fail( is_response = ls_resp iv_action = |update branch { iv_branch }| ).
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD get_file.
    TYPES:
      BEGIN OF ty_content_res,
        sha      TYPE string,
        content  TYPE string,
        encoding TYPE string,
      END OF ty_content_res.
    DATA ls_res TYPE ty_content_res.

    DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( |/contents/{ iv_path }?ref={ iv_branch }| ) ).
    IF ls_resp-code = 404.
      rs_content-found = abap_false.
      RETURN.
    ENDIF.
    IF ls_resp-code <> 200.
      fail( is_response = ls_resp iv_action = |read { iv_path }| ).
    ENDIF.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_res ).

    DATA(lv_b64) = ls_res-content.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_b64 WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN lv_b64 WITH ``.
    rs_content-found = abap_true.
    rs_content-sha   = ls_res-sha.
    rs_content-text  = cl_abap_codepage=>convert_from( source   = cl_http_utility=>decode_x_base64( lv_b64 )
                                                       codepage = `UTF-8` ).
  ENDMETHOD.


  METHOD put_file.
    TYPES:
      BEGIN OF ty_put_new,
        message TYPE string,
        content TYPE string,
        branch  TYPE string,
      END OF ty_put_new,
      BEGIN OF ty_put_upd,
        message TYPE string,
        content TYPE string,
        sha     TYPE string,
        branch  TYPE string,
      END OF ty_put_upd.

    DATA(lv_b64) = cl_http_utility=>encode_x_base64( to_utf8( iv_text ) ).
    DATA(lv_body) = COND string(
      WHEN iv_sha IS INITIAL
      THEN /ui2/cl_json=>serialize( data        = VALUE ty_put_new( message = iv_message content = lv_b64 branch = iv_branch )
                                    pretty_name = /ui2/cl_json=>pretty_mode-low_case )
      ELSE /ui2/cl_json=>serialize( data        = VALUE ty_put_upd( message = iv_message content = lv_b64
                                                                    sha     = iv_sha     branch  = iv_branch )
                                    pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).

    DATA(ls_resp) = request( iv_method = `PUT` iv_path = repo_path( |/contents/{ iv_path }| ) iv_body = lv_body ).
    CASE ls_resp-code.
      WHEN 200 OR 201.
        rv_conflict = abap_false.
      WHEN 409 OR 422.
        " 409: the file changed since it was read. 422 with a stale/missing sha means the same.
        rv_conflict = abap_true.
      WHEN OTHERS.
        fail( is_response = ls_resp iv_action = |write { iv_path }| ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
