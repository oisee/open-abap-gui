CLASS cl_gui_html_viewer DEFINITION PUBLIC INHERITING FROM cl_gui_control.
  PUBLIC SECTION.

    CONSTANTS uiflag_no3dborder TYPE i VALUE 4.
    CONSTANTS m_id_sapevent TYPE i VALUE 1.

    EVENTS sapevent
      EXPORTING
        VALUE(action)      TYPE c OPTIONAL
        VALUE(frame)       TYPE c OPTIONAL
        VALUE(getdata)     TYPE c OPTIONAL
        VALUE(postdata)    TYPE cnht_post_data_tab OPTIONAL
        VALUE(query_table) TYPE cnht_query_table OPTIONAL.

    METHODS constructor
      IMPORTING
        parent               TYPE REF TO cl_gui_container
        query_table_disabled TYPE c OPTIONAL.

    METHODS set_registered_events REDEFINITION.

    METHODS go_back.

    METHODS go_forward
      EXCEPTIONS
        cntl_error.

    METHODS do_refresh
      EXCEPTIONS
        cntl_error.

    METHODS close_document.

    METHODS get_current_url
      EXPORTING
        url TYPE c.

    METHODS load_data
      IMPORTING
        url          TYPE c OPTIONAL
        type         TYPE c DEFAULT 'text'
        subtype      TYPE c DEFAULT 'html'
        size         TYPE i DEFAULT 0
      EXPORTING
        assigned_url TYPE c
      CHANGING
        data_table   TYPE STANDARD TABLE
      EXCEPTIONS
        dp_invalid_parameter
        dp_error_general
        cntl_error
        html_syntax_notcorrect.

    METHODS show_url
      IMPORTING
        in_place TYPE abap_bool OPTIONAL
        url      TYPE c
      EXCEPTIONS
        cntl_error
        cnht_error_not_allowed
        cnht_error_parameter
        dp_error_general.

    METHODS set_ui_flag
      IMPORTING
        uiflag TYPE i DEFAULT 0
      EXCEPTIONS
        cntl_error.

    METHODS show_data
      IMPORTING
        url      TYPE c
        frame    TYPE c OPTIONAL
        in_place TYPE c DEFAULT 'X '
      EXCEPTIONS
        cntl_error
        cnht_error_not_allowed
        cnht_error_parameter
        dp_error_general.

* The inbound half of a sapevent. SAP GUI turns a click on a sapevent anchor,
* or the submit of a form whose action is a sapevent, into the event above.
* Here the document was rendered by cl_gui_control=>render_html with a
* transport (ty_sapevent), which rewrote those anchors and forms into forms
* that post to the transport's url. Whoever answers that url hands the request
* back here: the query string and the body as they arrived, and the same
* transport, so the transport's own fields can be told from the document's.
* The viewer the document belongs to is found by the control field the
* rewrite put into every form, and the event is raised on it.
    CLASS-METHODS dispatch_sapevent
      IMPORTING
        iv_query             TYPE string OPTIONAL
        iv_body              TYPE string OPTIONAL
        is_sapevent          TYPE cl_gui_control=>ty_sapevent
      RETURNING
        VALUE(rv_dispatched) TYPE abap_bool.

* Raises sapevent from a sapevent url and the form fields of the document,
* the way the frontend fills the parameters: the url before the "?" is the
* action, the text after it is getdata, the fields are postdata.
    METHODS raise_sapevent
      IMPORTING
        iv_action TYPE string
        it_fields TYPE cl_gui_control=>ty_fields OPTIONAL.

* Decodes application/x-www-form-urlencoded text into name/value pairs.
    CLASS-METHODS decode_form
      IMPORTING
        iv_text          TYPE string
      RETURNING
        VALUE(rt_fields) TYPE cl_gui_control=>ty_fields.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_history,
             url         TYPE string,
             payload     TYPE string,
             is_external TYPE abap_bool,
           END OF ty_history.
    TYPES ty_history_tab TYPE STANDARD TABLE OF ty_history WITH DEFAULT KEY.
    TYPES: BEGIN OF ty_viewer,
             control_id TYPE string,
             viewer     TYPE REF TO cl_gui_html_viewer,
           END OF ty_viewer.
    TYPES ty_viewers TYPE STANDARD TABLE OF ty_viewer WITH DEFAULT KEY.
    TYPES ty_action TYPE c LENGTH 255.
    TYPES ty_getdata TYPE c LENGTH 1024.

* How many characters of postdata go into one line. The line type is 1024
* wide, but abapGit, the consumer this was measured against, redeclares the
* table with 256-character lines and converts the event's table into it line
* by line, and works on every real system; so a frontend never hands it more
* than 256 characters per line, or every long form would lose its tail there.
    CONSTANTS c_post_data_chunk TYPE i VALUE 256.

    CLASS-DATA gt_viewers TYPE ty_viewers.

    DATA mv_document TYPE string.
    DATA mv_current_url TYPE string.
    DATA mv_payload TYPE string.
    DATA mv_external_url TYPE abap_bool.
    DATA mv_ui_flag TYPE i.
    DATA mt_history TYPE ty_history_tab.
    DATA mv_history_index TYPE i.
    DATA mv_query_table_disabled TYPE abap_bool.

    METHODS remember_current.
    METHODS publish_history.
    CLASS-METHODS unescape_form
      IMPORTING
        iv_text          TYPE string
      RETURNING
        VALUE(rv_result) TYPE string.
    CLASS-METHODS escape_post_data
      IMPORTING
        iv_text          TYPE string
      RETURNING
        VALUE(rv_result) TYPE string.
ENDCLASS.

CLASS cl_gui_html_viewer IMPLEMENTATION.
  METHOD set_registered_events.
* sapevent is the only event this control raises, so registering events on it
* means the loaded document wants its sapevent anchors dispatched. The generic
* events table of the base class is not inspected any further.
    cl_gui_control=>set_sapevent( control    = me
                                  registered = abap_true ).
  ENDMETHOD.

  METHOD set_ui_flag.
    mv_ui_flag = uiflag.
  ENDMETHOD.

  METHOD show_data.
    mv_current_url = url.
    mv_external_url = abap_false.
    mv_payload = mv_document.
    cl_gui_control=>set_payload( control = me
                                 payload = mv_current_url ).
    cl_gui_control=>set_html( control = me
                              html    = COND string( WHEN mv_document IS INITIAL
                                                    THEN '<!doctype html><html><body></body></html>'
                                                    ELSE mv_document ) ).
    remember_current( ).
  ENDMETHOD.

  METHOD show_url.
    IF url <> mv_current_url OR mv_external_url = abap_true.
      mv_current_url = url.
      CLEAR mv_document.
      mv_payload = url.
      mv_external_url = abap_true.
    ELSE.
      mv_payload = mv_document.
    ENDIF.
    cl_gui_control=>set_payload( control = me
                                 payload = mv_current_url ).
    cl_gui_control=>set_html( control = me
                              html    = COND string( WHEN mv_external_url = abap_false
                                                    AND mv_document IS INITIAL
                                                    THEN '<!doctype html><html><body></body></html>'
                                                    WHEN mv_external_url = abap_false
                                                    THEN mv_document
                                                    ELSE `` ) ).
    remember_current( ).
  ENDMETHOD.

  METHOD load_data.
    CLEAR mv_document.
    LOOP AT data_table ASSIGNING FIELD-SYMBOL(<line>).
      mv_document = mv_document && CONV string( <line> ).
    ENDLOOP.
    assigned_url = url.
    mv_current_url = url.
    mv_external_url = abap_false.
    mv_payload = mv_document.
    cl_gui_control=>set_payload( control = me
                                 payload = mv_current_url ).
    cl_gui_control=>set_html( control = me
                              html    = COND string( WHEN mv_document IS INITIAL
                                                    THEN '<!doctype html><html><body></body></html>'
                                                    ELSE mv_document ) ).
    remember_current( ).
  ENDMETHOD.

  METHOD get_current_url.
    url = mv_current_url.
  ENDMETHOD.

  METHOD close_document.
    CLEAR: mv_document, mv_current_url, mv_payload, mv_external_url,
           mt_history, mv_history_index.
    cl_gui_control=>set_payload( control = me
                                 payload = `` ).
    cl_gui_control=>set_html( control = me
                              html    = `` ).
  ENDMETHOD.

  METHOD go_back.
    IF mv_history_index > 1.
      mv_history_index = mv_history_index - 1.
      publish_history( ).
    ENDIF.
  ENDMETHOD.

  METHOD go_forward.
    IF mv_history_index < lines( mt_history ).
      mv_history_index = mv_history_index + 1.
      publish_history( ).
    ENDIF.
  ENDMETHOD.

  METHOD do_refresh.
    publish_history( ).
  ENDMETHOD.

  METHOD remember_current.
    DATA ls_history TYPE ty_history.

    IF mv_history_index > 0.
      WHILE lines( mt_history ) > mv_history_index.
        DELETE mt_history INDEX lines( mt_history ).
      ENDWHILE.
      READ TABLE mt_history INTO ls_history INDEX mv_history_index.
      IF sy-subrc = 0 AND ls_history-url = mv_current_url
          AND ls_history-payload = mv_payload
          AND ls_history-is_external = mv_external_url.
        RETURN.
      ENDIF.
    ENDIF.

    ls_history-url = mv_current_url.
    ls_history-payload = mv_payload.
    ls_history-is_external = mv_external_url.
    APPEND ls_history TO mt_history.
    mv_history_index = lines( mt_history ).
  ENDMETHOD.

  METHOD publish_history.
    READ TABLE mt_history INTO DATA(ls_history) INDEX mv_history_index.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    mv_current_url = ls_history-url.
    mv_payload = ls_history-payload.
    mv_external_url = ls_history-is_external.
    IF mv_external_url = abap_true.
      CLEAR mv_document.
    ELSE.
      mv_document = ls_history-payload.
    ENDIF.
    cl_gui_control=>set_payload( control = me
                                 payload = mv_current_url ).
    cl_gui_control=>set_html(
      control = me
      html    = COND string( WHEN mv_external_url = abap_false AND mv_document IS INITIAL
                              THEN '<!doctype html><html><body></body></html>'
                              WHEN mv_external_url = abap_true
                              THEN ``
                              ELSE mv_document ) ).
  ENDMETHOD.

  METHOD constructor.
    DATA ls_viewer TYPE ty_viewer.

    cl_gui_control=>initialize(
      control = me
      parent  = parent
      kind    = 'HTML_VIEWER' ).
    parent->add_child( me ).
    mv_query_table_disabled = xsdbool( query_table_disabled IS NOT INITIAL ).
* cl_gui_control=>clear( ) starts the ids over, so an id can come round again
* and the newest viewer is the one it means.
    DELETE gt_viewers WHERE control_id = control_id.
    ls_viewer-control_id = control_id.
    ls_viewer-viewer = me.
    APPEND ls_viewer TO gt_viewers.
  ENDMETHOD.

  METHOD dispatch_sapevent.
    DATA lt_fields   TYPE cl_gui_control=>ty_fields.
    DATA lt_document TYPE cl_gui_control=>ty_fields.
    DATA ls_field    TYPE cl_gui_control=>ty_field.
    DATA lv_control  TYPE string.
    DATA lv_action   TYPE string.
    DATA lv_found    TYPE abap_bool.

* The query string first: a form's action carries the transport's fields
* there, and the body is the document's own.
    lt_fields = decode_form( iv_query ).
    APPEND LINES OF decode_form( iv_body ) TO lt_fields.

    LOOP AT lt_fields INTO ls_field.
      IF ls_field-name = cl_gui_control=>c_sapevent_control.
        lv_control = ls_field-value.
      ELSEIF ls_field-name = is_sapevent-action_field.
        lv_action = ls_field-value.
        lv_found = abap_true.
      ELSEIF NOT line_exists( is_sapevent-fields[ name = ls_field-name ] ).
        APPEND ls_field TO lt_document.
      ENDIF.
    ENDLOOP.
    IF lv_found = abap_false OR lv_control IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE gt_viewers INTO DATA(ls_viewer) WITH KEY control_id = lv_control.
    IF sy-subrc <> 0 OR ls_viewer-viewer->is_alive( ) <> state_alive.
      RETURN.
    ENDIF.

    ls_viewer-viewer->raise_sapevent( iv_action = lv_action
                                      it_fields = lt_document ).
    rv_dispatched = abap_true.
  ENDMETHOD.

  METHOD raise_sapevent.
    DATA lv_action      TYPE ty_action.
    DATA lv_getdata     TYPE ty_getdata.
    DATA lv_frame       TYPE ty_action.
    DATA lv_body        TYPE string.
    DATA lv_offset      TYPE i.
    DATA lt_postdata    TYPE cnht_post_data_tab.
    DATA lv_line        TYPE cnht_post_data_line.
    DATA lt_query_table TYPE cnht_query_table.
    DATA ls_query       TYPE cnht_query_struct.
    DATA ls_field       TYPE cl_gui_control=>ty_field.

    FIND FIRST OCCURRENCE OF '?' IN iv_action MATCH OFFSET lv_offset.
    IF sy-subrc = 0.
      lv_action = substring( val = iv_action
                             len = lv_offset ).
* getdata is the text after the "?" as the document wrote it. The consumer
* undoes the escapes it expects there itself, so nothing is decoded here.
      lv_getdata = substring( val = iv_action
                              off = lv_offset + 1 ).
    ELSE.
      lv_action = iv_action.
    ENDIF.

* postdata is the form as name=value pairs joined with "&", in lines of a
* fixed width, filled to the end, so that a consumer joins them back with the
* blanks kept. The text stays as typed, spaces and all: only the three
* characters the pairs are built from are escaped, so that a value can hold
* them, and those are among the escapes every consumer of this event undoes.
    LOOP AT it_fields INTO ls_field.
      IF lv_body IS NOT INITIAL.
        lv_body = lv_body && `&`.
      ENDIF.
      lv_body = lv_body && escape_post_data( ls_field-name ) && `=` && escape_post_data( ls_field-value ).
    ENDLOOP.
    WHILE strlen( lv_body ) > c_post_data_chunk.
      lv_line = substring( val = lv_body
                           len = c_post_data_chunk ).
      APPEND lv_line TO lt_postdata.
      lv_body = substring( val = lv_body
                           off = c_post_data_chunk ).
    ENDWHILE.
    IF lv_body IS NOT INITIAL.
      lv_line = lv_body.
      APPEND lv_line TO lt_postdata.
    ENDIF.

* query_table is the same data parsed, the pairs of getdata first, unless the
* viewer was constructed with query_table_disabled, as abapGit constructs it.
    IF mv_query_table_disabled = abap_false.
      LOOP AT decode_form( CONV string( lv_getdata ) ) INTO ls_field.
        ls_query-name = ls_field-name.
        ls_query-value = ls_field-value.
        APPEND ls_query TO lt_query_table.
      ENDLOOP.
      LOOP AT it_fields INTO ls_field.
        ls_query-name = ls_field-name.
        ls_query-value = ls_field-value.
        APPEND ls_query TO lt_query_table.
      ENDLOOP.
    ENDIF.

    RAISE EVENT sapevent
      EXPORTING
        action      = lv_action
        frame       = lv_frame
        getdata     = lv_getdata
        postdata    = lt_postdata
        query_table = lt_query_table.
  ENDMETHOD.

  METHOD decode_form.
    DATA lt_pairs TYPE string_table.
    DATA lv_pair  TYPE string.
    DATA ls_field TYPE cl_gui_control=>ty_field.
    DATA lv_name  TYPE string.
    DATA lv_value TYPE string.

    SPLIT iv_text AT '&' INTO TABLE lt_pairs.
    LOOP AT lt_pairs INTO lv_pair.
      IF lv_pair IS INITIAL.
        CONTINUE.
      ENDIF.
      IF lv_pair CA '='.
        SPLIT lv_pair AT '=' INTO lv_name lv_value.
      ELSE.
        lv_name = lv_pair.
        CLEAR lv_value.
      ENDIF.
      ls_field-name = unescape_form( lv_name ).
      ls_field-value = unescape_form( lv_value ).
      APPEND ls_field TO rt_fields.
    ENDLOOP.
  ENDMETHOD.

  METHOD unescape_form.
* A browser sends a form as application/x-www-form-urlencoded: a space is a
* plus sign and everything else outside the unreserved set is percent-encoded.
    rv_result = iv_text.
    REPLACE ALL OCCURRENCES OF '+' IN rv_result WITH ` `.
    IF rv_result CA '%'.
      rv_result = cl_http_utility=>unescape_url( rv_result ).
    ENDIF.
  ENDMETHOD.

  METHOD escape_post_data.
    rv_result = iv_text.
    REPLACE ALL OCCURRENCES OF '%' IN rv_result WITH '%25'.
    REPLACE ALL OCCURRENCES OF '&' IN rv_result WITH '%26'.
    REPLACE ALL OCCURRENCES OF '=' IN rv_result WITH '%3D'.
  ENDMETHOD.

ENDCLASS.
