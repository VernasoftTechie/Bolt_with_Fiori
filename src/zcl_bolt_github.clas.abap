"! <p class="shorttext synchronized">Bolt with Fiori - GitHub REST client</p>
"! Talks to api.github.com through the SM59 destination of the setup. The
"! destination holds host, TLS and the token (Basic logon: any user name,
"! password = a fine-grained personal access token limited to the client's
"! repository with Contents read/write) - nothing secret is in this code.
"!
"! A new migration branch is created as ONE commit holding every reference
"! file and the status file, and the branch reference is written last - so
"! a branch never exists half-made (same guarantee Bolt Console gave with
"! its retry loop). Status writes send the file's blob SHA, so GitHub itself
"! rejects a write based on a stale copy (409) instead of losing an update.
CLASS zcl_bolt_github DEFINITION
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

    TYPES ty_t_name TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    METHODS constructor
      IMPORTING iv_destination TYPE rfcdest
                iv_owner       TYPE string
                iv_repo        TYPE string.

    "! Client for the repository configured in the setup row.
    CLASS-METHODS from_setup
      RETURNING VALUE(ro_github) TYPE REF TO zcl_bolt_github
      RAISING   zcx_bolt.

    CLASS-METHODS to_utf8
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_data) TYPE xstring.

    "! Checks the token and the repository; returns a one-line summary.
    METHODS test_access
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_bolt.

    "! Head commit SHA of a branch, or initial if the branch does not exist.
    METHODS get_branch_sha
      IMPORTING iv_branch     TYPE string
      RETURNING VALUE(rv_sha) TYPE string
      RAISING   zcx_bolt.

    METHODS create_branch_with_files
      IMPORTING iv_base_branch       TYPE string
                iv_branch            TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_bolt.

    "! Adds/replaces files on an existing branch in one commit.
    METHODS add_files
      IMPORTING iv_branch            TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_bolt.

    "! Reads one text file (UTF-8). found = false when it does not exist.
    METHODS get_file
      IMPORTING iv_branch         TYPE string
                iv_path           TYPE string
      RETURNING VALUE(rs_content) TYPE ty_content
      RAISING   zcx_bolt.

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
      RAISING   zcx_bolt.

    METHODS delete_branch
      IMPORTING iv_branch TYPE string
      RAISING   zcx_bolt.

    "! Names of all branches starting with the prefix.
    METHODS list_branches
      IMPORTING iv_prefix          TYPE string
      RETURNING VALUE(rt_branches) TYPE ty_t_name
      RAISING   zcx_bolt.

    METHODS web_url
      IMPORTING iv_branch     TYPE string
      RETURNING VALUE(rv_url) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_sha,
        sha TYPE string,
      END OF ty_sha.

    DATA gv_destination TYPE rfcdest.
    DATA gv_owner       TYPE string.
    DATA gv_repo        TYPE string.

    METHODS request
      IMPORTING iv_method          TYPE string
                iv_path            TYPE string
                iv_body            TYPE string OPTIONAL
      RETURNING VALUE(rs_response) TYPE zcl_bolt_http=>ty_response
      RAISING   zcx_bolt.

    METHODS repo_path
      IMPORTING iv_suffix      TYPE string
      RETURNING VALUE(rv_path) TYPE string.

    "! Raises with GitHub's own error message for an unexpected status.
    METHODS fail
      IMPORTING is_response TYPE zcl_bolt_http=>ty_response
                iv_action   TYPE string
      RAISING   zcx_bolt.

    METHODS build_commit
      IMPORTING iv_parent_sha        TYPE string
                it_files             TYPE ty_t_file
                iv_message           TYPE string
      RETURNING VALUE(rv_commit_sha) TYPE string
      RAISING   zcx_bolt.

    METHODS read_sha
      IMPORTING iv_json       TYPE string
      RETURNING VALUE(rv_sha) TYPE string.
ENDCLASS.



CLASS zcl_bolt_github IMPLEMENTATION.

  METHOD constructor.
    gv_destination = iv_destination.
    gv_owner       = condense( iv_owner ).
    gv_repo        = condense( iv_repo ).
  ENDMETHOD.


  METHOD from_setup.
    DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
    IF ls_setup-gh_destination IS INITIAL OR ls_setup-gh_owner IS INITIAL OR ls_setup-gh_repo IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = `GitHub is not configured - set the SM59 destination, owner and repository in Configuration.` ).
    ENDIF.
    ro_github = NEW zcl_bolt_github( iv_destination = ls_setup-gh_destination
                                     iv_owner       = CONV string( ls_setup-gh_owner )
                                     iv_repo        = CONV string( ls_setup-gh_repo ) ).
  ENDMETHOD.


  METHOD to_utf8.
    rv_data = cl_abap_codepage=>convert_to( source = iv_text codepage = `UTF-8` ).
  ENDMETHOD.


  METHOD repo_path.
    rv_path = |/repos/{ gv_owner }/{ gv_repo }{ iv_suffix }|.
  ENDMETHOD.


  METHOD web_url.
    rv_url = |https://github.com/{ gv_owner }/{ gv_repo }/tree/{ iv_branch }|.
  ENDMETHOD.


  METHOD request.
    DATA(lt_headers) = VALUE zcl_bolt_http=>ty_t_header(
      ( name = `Accept`               value = `application/vnd.github+json` )
      ( name = `X-GitHub-Api-Version` value = `2022-11-28` )
      ( name = `User-Agent`           value = `Bolt-with-Fiori` ) ).
    IF iv_body IS NOT INITIAL.
      APPEND VALUE #( name = `Content-Type` value = `application/json; charset=utf-8` ) TO lt_headers.
    ENDIF.
    rs_response = zcl_bolt_http=>call( iv_destination = gv_destination
                                       iv_method      = iv_method
                                       iv_uri         = iv_path
                                       iv_body        = iv_body
                                       it_headers     = lt_headers ).
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
      WHEN 401 THEN ` The token in the SM59 destination is wrong or expired.`
      WHEN 403 THEN ` The token is not allowed to do this (it needs Contents read/write on this repository).`
      WHEN 404 THEN ` The repository or branch was not found, or the token cannot see it.`
      ELSE `` ).
    RAISE EXCEPTION NEW zcx_bolt(
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


  METHOD test_access.
    TYPES:
      BEGIN OF ty_user,
        login TYPE string,
      END OF ty_user,
      BEGIN OF ty_permissions,
        admin TYPE abap_bool,
        push  TYPE abap_bool,
        pull  TYPE abap_bool,
      END OF ty_permissions,
      BEGIN OF ty_repo,
        full_name      TYPE string,
        default_branch TYPE string,
        permissions    TYPE ty_permissions,
      END OF ty_repo.
    DATA ls_user TYPE ty_user.
    DATA ls_repo TYPE ty_repo.

    DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( `` ) ).
    IF ls_resp-code <> 200.
      fail( is_response = ls_resp iv_action = |open repository { gv_owner }/{ gv_repo }| ).
    ENDIF.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_repo ).

    DATA(ls_user_resp) = request( iv_method = `GET` iv_path = `/user` ).
    IF ls_user_resp-code = 200.
      /ui2/cl_json=>deserialize( EXPORTING json        = ls_user_resp-body
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                 CHANGING  data        = ls_user ).
    ENDIF.

    " A fine-grained token returns no permissions block - only a classic one does.
    DATA(lv_write) = COND string( WHEN ls_repo-permissions IS INITIAL THEN `write access not reported by this token type`
                                  WHEN ls_repo-permissions-push = abap_true THEN `write access confirmed`
                                  ELSE `READ-ONLY - the token cannot push` ).
    rv_text = |Connected{ COND string( WHEN ls_user-login IS NOT INITIAL THEN ` as ` && ls_user-login ) }: | &&
              |{ ls_repo-full_name } (default branch { ls_repo-default_branch }), { lv_write }.|.
    IF ls_repo-permissions IS NOT INITIAL AND ls_repo-permissions-push = abap_false.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = rv_text ).
    ENDIF.
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

    " 2. one blob per file (base64 - exact bytes, any size GitHub accepts)
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
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |Base branch { iv_base_branch } does not exist in { gv_owner }/{ gv_repo }.| ).
    ENDIF.

    rv_commit_sha = build_commit( iv_parent_sha = lv_base_sha it_files = it_files iv_message = iv_message ).

    DATA(ls_resp) = request( iv_method = `POST`
                             iv_path   = repo_path( `/git/refs` )
                             iv_body   = /ui2/cl_json=>serialize(
                                           data        = VALUE ty_ref_req( ref = |refs/heads/{ iv_branch }| sha = rv_commit_sha )
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case ) ).
    IF ls_resp-code = 422.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |A branch named { iv_branch } already exists in { gv_owner }/{ gv_repo } - it was not overwritten.| ).
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
        RAISE EXCEPTION NEW zcx_bolt( iv_text = |Branch { iv_branch } does not exist any more in { gv_owner }/{ gv_repo }.| ).
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


  METHOD delete_branch.
    DATA(ls_resp) = request( iv_method = `DELETE` iv_path = repo_path( |/git/refs/heads/{ iv_branch }| ) ).
    IF ls_resp-code <> 204 AND ls_resp-code <> 404 AND ls_resp-code <> 422.
      fail( is_response = ls_resp iv_action = |delete branch { iv_branch }| ).
    ENDIF.
  ENDMETHOD.


  METHOD list_branches.
    TYPES:
      BEGIN OF ty_branch,
        name TYPE string,
      END OF ty_branch,
      ty_t_branch TYPE STANDARD TABLE OF ty_branch WITH EMPTY KEY.
    DATA lt_page TYPE ty_t_branch.

    DATA(lv_page) = 1.
    DO 50 TIMES.
      CLEAR lt_page.
      DATA(ls_resp) = request( iv_method = `GET` iv_path = repo_path( |/branches?per_page=100&page={ lv_page }| ) ).
      IF ls_resp-code <> 200.
        fail( is_response = ls_resp iv_action = `list branches` ).
      ENDIF.
      /ui2/cl_json=>deserialize( EXPORTING json        = ls_resp-body
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                 CHANGING  data        = lt_page ).
      LOOP AT lt_page INTO DATA(ls_branch).
        IF iv_prefix IS INITIAL OR find( val = ls_branch-name sub = iv_prefix ) = 0.
          APPEND ls_branch-name TO rt_branches.
        ENDIF.
      ENDLOOP.
      IF lines( lt_page ) < 100.
        EXIT.
      ENDIF.
      lv_page += 1.
    ENDDO.
    SORT rt_branches.
  ENDMETHOD.

ENDCLASS.
