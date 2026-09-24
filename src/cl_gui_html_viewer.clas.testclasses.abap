CLASS ltcl_html_viewer_history DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT FINAL.

  PRIVATE SECTION.
    METHODS keeps_document_history FOR TESTING.

ENDCLASS.

CLASS ltcl_html_viewer_history IMPLEMENTATION.

  METHOD keeps_document_history.
    DATA lt_document TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
    DATA lv_url TYPE c LENGTH 255.
    DATA lv_html TYPE string.
    DATA(lo_container) = NEW cl_gui_custom_container( container_name = 'HTML_HISTORY' ).
    DATA(lo_viewer) = NEW cl_gui_html_viewer( parent = lo_container ).

    APPEND '<h1>Loaded splitter document</h1>' TO lt_document.
    lo_viewer->load_data(
      IMPORTING
        assigned_url = lv_url
      CHANGING
        data_table   = lt_document ).
    lo_viewer->show_url( url = lv_url ).
    lv_html = cl_gui_control=>render_html( iv_document = abap_false ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'Loaded splitter document' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'srcdoc=' ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_html CS 'src=""' ) ).

    CLEAR lt_document.
    APPEND '<h1>First</h1>' TO lt_document.
    lo_viewer->load_data(
      EXPORTING
        url        = 'about:first'
      CHANGING
        data_table = lt_document ).
    CLEAR lt_document.
    APPEND '<h1>Second</h1>' TO lt_document.
    lo_viewer->load_data(
      EXPORTING
        url        = 'about:second'
      CHANGING
        data_table = lt_document ).
    lo_viewer->go_back( ).
    lo_viewer->get_current_url( IMPORTING url = lv_url ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_url
      exp = 'about:first' ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( cl_gui_control=>render_html( ) CS 'First' ) ).

    lo_viewer->go_forward( ).
    lo_viewer->get_current_url( IMPORTING url = lv_url ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_url
      exp = 'about:second' ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( cl_gui_control=>render_html( ) CS 'Second' ) ).

    lo_viewer->close_document( ).
    lo_viewer->get_current_url( IMPORTING url = lv_url ).
    cl_abap_unit_assert=>assert_initial( lv_url ).

    lo_viewer->show_url( url = 'https://example.invalid/viewer' ).
    DATA(lv_external_html) = cl_gui_control=>render_html( iv_document = abap_false ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_external_html CS 'src="https://example.invalid/viewer"' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_external_html CS 'sandbox=""' ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_external_html CS 'srcdoc=' ) ).

    lo_viewer->show_url( url = 'javascript:alert(1)' ).
    DATA(lv_unsafe_html) = cl_gui_control=>render_html( iv_document = abap_false ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_unsafe_html CS 'src="javascript:' ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_unsafe_html CS 'javascript:alert(1)' ) ).
  ENDMETHOD.

ENDCLASS.

* What a program registers on the viewer: a handler with the signature of the
* SAP event, keeping what it was given.
CLASS lcl_listener DEFINITION FINAL.
  PUBLIC SECTION.
    DATA mv_raised      TYPE i.
    DATA mv_action      TYPE string.
    DATA mv_frame       TYPE string.
    DATA mv_getdata     TYPE string.
    DATA mt_postdata    TYPE cnht_post_data_tab.
    DATA mt_query_table TYPE cnht_query_table.

    METHODS on_sapevent FOR EVENT sapevent OF cl_gui_html_viewer
      IMPORTING action frame getdata postdata query_table.
ENDCLASS.

CLASS lcl_listener IMPLEMENTATION.
  METHOD on_sapevent.
    mv_raised = mv_raised + 1.
    mv_action = action.
    mv_frame = frame.
    mv_getdata = getdata.
    mt_postdata = postdata.
    mt_query_table = query_table.
  ENDMETHOD.
ENDCLASS.

* The round trip of a sapevent: a document is rendered with a transport, the
* browser posts one of the forms the rendering made of it, the post is handed
* back, and the event reaches the handler with the parameters filled the way
* SAP GUI fills them. The browser is played by hand here: the bodies below
* are what a browser sends for the forms the rendering is asserted to hold.
CLASS ltcl_sapevent DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT FINAL.

  PRIVATE SECTION.
    DATA mo_container TYPE REF TO cl_gui_custom_container.
    DATA mo_viewer    TYPE REF TO cl_gui_html_viewer.
    DATA mo_listener  TYPE REF TO lcl_listener.
    DATA ms_transport TYPE cl_gui_control=>ty_sapevent.

    METHODS setup.
    METHODS teardown.
    METHODS load
      IMPORTING
        iv_document TYPE string.
    METHODS render
      RETURNING
        VALUE(rv_html) TYPE string.

    METHODS anchor_click_comes_back FOR TESTING.
    METHODS form_submit_comes_back FOR TESTING.
    METHODS long_post_data_fills_lines FOR TESTING.
    METHODS unknown_control_is_not_taken FOR TESTING.
    METHODS foreign_form_is_left_alone FOR TESTING.

ENDCLASS.

CLASS ltcl_sapevent IMPLEMENTATION.

  METHOD setup.
    DATA ls_field TYPE cl_gui_control=>ty_field.

    cl_gui_control=>clear( ).
    mo_container = NEW cl_gui_custom_container( container_name = 'SAPEVENT' ).
    mo_listener = NEW lcl_listener( ).

    ms_transport-url = '/dispatch'.
    ms_transport-action_field = 'ucomm'.
    ls_field-name = 'session_id'.
    ls_field-value = 'S1'.
    APPEND ls_field TO ms_transport-fields.
    ls_field-name = 'page_id'.
    ls_field-value = 'P1'.
    APPEND ls_field TO ms_transport-fields.
  ENDMETHOD.

  METHOD teardown.
    cl_gui_control=>clear( ).
  ENDMETHOD.

  METHOD load.
    DATA lt_document TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    APPEND iv_document TO lt_document.
    mo_viewer->set_registered_events( VALUE cntl_simple_events( ) ).
    mo_viewer->load_data(
      EXPORTING
        url        = 'about:test'
      CHANGING
        data_table = lt_document ).
    SET HANDLER mo_listener->on_sapevent FOR mo_viewer.
  ENDMETHOD.

  METHOD render.
    rv_html = cl_gui_control=>render_html( iv_document = abap_false
                                           is_sapevent = ms_transport ).
  ENDMETHOD.

  METHOD anchor_click_comes_back.
    DATA lv_html TYPE string.
    DATA lv_body TYPE string.
    DATA ls_query TYPE cnht_query_struct.

    mo_viewer = NEW cl_gui_html_viewer( parent = mo_container ).
    load( '<p><a href="sapevent:go_repo?key=1&amp;path=%2Fsrc" class="x">Repo</a></p>' ).

    lv_html = render( ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'gg-sapevent' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS |name=&quot;gg_control&quot; value=&quot;{ mo_viewer->control_id }&quot;| ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'name=&quot;ucomm&quot; value=&quot;go_repo?key=1&amp;amp;path=%2Fsrc&quot;' ) ).

* the browser undoes the entities of the attribute and encodes the form
    lv_body = |session_id=S1&page_id=P1&gg_control={ mo_viewer->control_id }| &&
      |&ucomm=go_repo%3Fkey%3D1%26path%3D%252Fsrc|.
    cl_abap_unit_assert=>assert_true( act = cl_gui_html_viewer=>dispatch_sapevent(
      iv_body     = lv_body
      is_sapevent = ms_transport ) ).

    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_raised
                                        exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_action
                                        exp = 'go_repo' ).
    cl_abap_unit_assert=>assert_initial( mo_listener->mv_frame ).
* getdata as the document wrote it, escapes and all
    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_getdata
                                        exp = 'key=1&path=%2Fsrc' ).
* no form of the document, so no postdata; and the transport's fields are not
* the document's
    cl_abap_unit_assert=>assert_initial( mo_listener->mt_postdata ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_listener->mt_query_table )
                                        exp = 2 ).
    READ TABLE mo_listener->mt_query_table INTO ls_query INDEX 2.
    cl_abap_unit_assert=>assert_equals( act = ls_query-name
                                        exp = 'path' ).
    cl_abap_unit_assert=>assert_equals( act = ls_query-value
                                        exp = '/src' ).
  ENDMETHOD.

  METHOD form_submit_comes_back.
    DATA lv_html TYPE string.
    DATA lv_body TYPE string.
    DATA lv_line TYPE cnht_post_data_line.

* the shape of a form abapGit writes (zcl_abapgit_html_form=>render): the main
* command is the form's action and a hidden submit, a side action is a submit
* with a formaction of its own; the viewer is constructed as abapGit does
    mo_viewer = NEW cl_gui_html_viewer( parent               = mo_container
                                        query_table_disabled = abap_true ).
    load( `<div class="dialog"><form method="post" id="add-repo-online-form" action="sapevent:add-repo-online">` &&
      `<button type="submit" formaction="sapevent:add-repo-online" class="hidden-submit" aria-hidden="true" tabindex="-1"></button>` &&
      `<input name="url" value="https://github.com/x/y"><input name="display_name" value="My repo &amp; more">` &&
      `<input type="submit" value="Choose" formaction="sapevent:choose-package"></form></div>` ).

    lv_html = render( ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_html CS 'sapevent:' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'action=&quot;/dispatch?ucomm=add-repo-online&quot; target=&quot;_top&quot;' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'formaction=&quot;/dispatch?ucomm=choose-package&quot;' ) ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS |name=&quot;gg_control&quot; value=&quot;{ mo_viewer->control_id }&quot;| ) ).

* the browser posts to the action's url, query string and all, the fields in
* document order: the hidden ones first, then the document's own
    lv_body = |session_id=S1&page_id=P1&gg_control={ mo_viewer->control_id }| &&
      |&url=https%3A%2F%2Fgithub.com%2Fx%2Fy&display_name=My+repo+%26+more|.
    cl_abap_unit_assert=>assert_true( act = cl_gui_html_viewer=>dispatch_sapevent(
      iv_query    = 'ucomm=add-repo-online'
      iv_body     = lv_body
      is_sapevent = ms_transport ) ).

    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_raised
                                        exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_action
                                        exp = 'add-repo-online' ).
    cl_abap_unit_assert=>assert_initial( mo_listener->mv_getdata ).
* postdata: the document's fields only, as typed, with the pair delimiters
* escaped the way the consumer undoes them
    cl_abap_unit_assert=>assert_equals( act = lines( mo_listener->mt_postdata )
                                        exp = 1 ).
    READ TABLE mo_listener->mt_postdata INTO lv_line INDEX 1.
    cl_abap_unit_assert=>assert_equals( act = lv_line
                                        exp = 'url=https://github.com/x/y&display_name=My repo %26 more' ).
    cl_abap_unit_assert=>assert_initial( mo_listener->mt_query_table ).
  ENDMETHOD.

  METHOD long_post_data_fills_lines.
    DATA lv_value TYPE string.
    DATA lv_body  TYPE string.
    DATA lv_first TYPE cnht_post_data_line.
    DATA lv_last  TYPE cnht_post_data_line.

    mo_viewer = NEW cl_gui_html_viewer( parent = mo_container ).
    load( '<form method="post" action="sapevent:commit"><textarea name="message"></textarea></form>' ).
    render( ).

    lv_value = repeat( val = 'x'
                       occ = 300 ).
    lv_body = |gg_control={ mo_viewer->control_id }&message={ lv_value }|.
    cl_abap_unit_assert=>assert_true( act = cl_gui_html_viewer=>dispatch_sapevent(
      iv_query    = 'ucomm=commit'
      iv_body     = lv_body
      is_sapevent = ms_transport ) ).

* the lines are filled to their width and the last one carries the rest, so
* that joining them respecting blanks gives the fields back
    cl_abap_unit_assert=>assert_equals( act = lines( mo_listener->mt_postdata )
                                        exp = 2 ).
    READ TABLE mo_listener->mt_postdata INTO lv_first INDEX 1.
    READ TABLE mo_listener->mt_postdata INTO lv_last INDEX 2.
    cl_abap_unit_assert=>assert_equals( act = strlen( lv_first )
                                        exp = 256 ).
    cl_abap_unit_assert=>assert_equals( act = lv_first(256) && lv_last
                                        exp = |message={ lv_value }| ).
  ENDMETHOD.

  METHOD unknown_control_is_not_taken.
    mo_viewer = NEW cl_gui_html_viewer( parent = mo_container ).
    load( '<a href="sapevent:stage">Stage</a>' ).
    render( ).

* a post naming no viewer of this process, and one naming no action
    cl_abap_unit_assert=>assert_false( act = cl_gui_html_viewer=>dispatch_sapevent(
      iv_body     = 'gg_control=GUI-99&ucomm=stage'
      is_sapevent = ms_transport ) ).
    cl_abap_unit_assert=>assert_false( act = cl_gui_html_viewer=>dispatch_sapevent(
      iv_body     = |gg_control={ mo_viewer->control_id }&session_id=S1|
      is_sapevent = ms_transport ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_listener->mv_raised
                                        exp = 0 ).
  ENDMETHOD.

  METHOD foreign_form_is_left_alone.
    DATA lv_html TYPE string.

    mo_viewer = NEW cl_gui_html_viewer( parent = mo_container ).
    load( '<form method="get" action="https://example.org/search"><input name="q"></form>' ).
    lv_html = render( ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_html CS 'action=&quot;https://example.org/search&quot;&gt;' ) ).
    cl_abap_unit_assert=>assert_false( act = xsdbool( lv_html CS 'gg_control' ) ).
  ENDMETHOD.

ENDCLASS.
