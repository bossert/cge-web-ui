$(function() {
  'use strict';
  // Setting up the object for popup notifications throughout the application
  var popup = $("#popupNotification").kendoNotification({
    hideOnClick: true,
    position: {
      pinned: true,
      top: null,
      right: 20,
      bottom: 20
    },
    stacking: "up"
  }).data("kendoNotification");

  // Popup window for altering node display properties
  var alterNodesWindow = $("#alterNodesPopup").kendoWindow({
      width: "425px",
			height: "500px",
      title: "Alter Node and Edge Display Properties",
      actions: [
          "Minimize",
          "Maximize",
          "Close"
      ]
  }).data('kendoWindow');

  // Popup window for creating new databases
  var new_database_window = $('#new_database_popup').kendoWindow({
    width: '475px',
    height: '200px',
    title: 'Create New Database',
    actions: [
      'Close'
    ]
  }).data('kendoWindow');

  // Popup window to reconnect websocket connections
  var websocketReconnect = $("#websocketReconnect").kendoWindow({
    width: "300px",
    title: "Websocket Reconnect",
    actions: [
      "Close"
    ]
  }).data('kendoWindow');

  // Our fancy hamburger menu button
  $('.c-hamburger').on('click', function(e) {
    e.preventDefault();
    (this.classList.contains("is-active") === true) ? this.classList.remove("is-active") : this.classList.add("is-active");
    ($('#navigation').css('left') == '0px') ? $('#navigation').css('left','-500px') : $('#navigation').css('left','0px');
    ($('#content_area').css('left') == '0px') ? $('#content_area').css('left','500px') : $('#content_area').css('left','0px');
  });

  // Menu panel bar
  $('.ss_button').on('click', function() {
    $('.ss_content').slideUp();
    $(this).next('.ss_content').slideDown();

    if($(this).attr('id') == 'access_control') {
      userAccessControlGrid.resize();
    }
  });

  /* Maybe do this differently later, but lets trigger a click so that the menu opens
     and the first menu item is exposed on page load */
  $('.c-hamburger').trigger('click');
  setTimeout(function() {
    $('#database_management').next('.ss_content').slideDown();
  },1000);

  // Need to check if there is a running DB that "this user started" in case the app was closed and reopened
  $.get('squeue',function(res) {
    $('#current_queue > tbody').html('');
    if(res.length >= 1) {
      $.each(res,function(i,v) {
        var htmlInsert = '<tr><td>'+v.JOBID+'</td><td>'+v.USER+'</td><td>'+v.STATE+'</td><td>'+v.TIME+'</td><td>'+v.NODES+'</td></tr>';
        $('#current_queue > tbody').append(htmlInsert);

        if(localStorage.getItem('current_pid') !== null &&
           localStorage.getItem('current_pid') == v.JOBID) {
          $('#db_status').text('RUNNING');
          $('#startDB').prop('value','Stop');
          $('#db_name').html(localStorage.getItem('current_database'));
        }
      });
    }
  }).fail(function(xhr) {
    popup.show("Failed to retrieve system queue information (" + xhr.status + " " + xhr.statusText + ")" ,"error");
  });

  // N_triples file browser
  var filebrowserDS = new kendo.data.HierarchicalDataSource({
    transport: {
      read:  {
        url: 'list_NT_files',
        dataType: "json"
      }
    },
    schema: {
      model: {
        id: 'name',
        text: 'name',
        hasChildren: 'hasFiles',
        children: 'files'
      }
    }
  });

  $('#file_browser').kendoTreeView({
    dataSource: filebrowserDS,
      dataTextField: 'name',
      dataValueField: 'path',
      checkboxes: {
        checkChildren: true,
        template: '# if(!item.hasChildren) { # <input type="checkbox" name="checkedFiles[#= item.id #]" value="true" /> # } #'
      },
      dataBound: function(e) {
        InitSearch('#file_browser', '#treeViewSearchInput');
      }
  });

  // Database combobox
  var databasebrowserDS = new kendo.data.DataSource({
    transport: {
      read:  {
        url: 'list_databases',
        dataType: "json"
      }
    }
  });

  // Combobox for the database picker.  Data will be populated later
  $('#selectDB').kendoComboBox({
    dataSource: databasebrowserDS,
    filter:'contains',
    dataTextField: 'name',
    dataValueField: 'path',
    template: '<table style=\'width: 100%; border-collapse: collapse;\'>'+
              '<tr><td colspan=2 style="font-weight: bold; font-size: 1.2em; background-color: rgb(193, 193, 193); padding-left: 5px;">#: data.name #</td></tr>'+
              '<tr><td colspan=2 style="font-size: 0.9em; background-color: rgb(193, 193, 193); padding-left: 5px;">#: data.path #</td></tr>'+
              '<tr><td style="text-align: right; font-size: 0.9em;">Owner:</td>         <td style="text-align: right; font-size: 0.9em;">#: data.owner #</td></tr>'+
              '<tr><td style="text-align: right; font-size: 0.9em;">Size:</td>          <td style="text-align: right; font-size: 0.9em;">#: data.size #</td></tr>'+
              '<tr><td style="text-align: right; font-size: 0.9em;">Last Modified:</td> <td style="text-align: right; font-size: 0.9em;">#: data.last_modified #</td></tr></table>'
  });
  $('#selectDB').data('kendoComboBox').list.width(450);

  // Numeric inputs for number of instances and number of nodes
  $('#instances').kendoNumericTextBox({
    min: 1,
    max: 32,
    value: 8,
    format: 'n0'
  });
  var dbNodes = $('#nodes').kendoNumericTextBox({
    min: 1,
    format: 'n0'
  }).data('kendoNumericTextBox');

  $('#timeout').kendoNumericTextBox({
    min: 3600,
    value: 3600,
    format: 'n0'
  });

  $('#new_instances').kendoNumericTextBox({
    min: 1,
    max: 32,
    value: 8,
    format: 'n0'
  });
  var newDbNodes = $('#new_nodes').kendoNumericTextBox({
    min: 1,
    format: 'n0'
  }).data('kendoNumericTextBox');

  $('#new_timeout').kendoNumericTextBox({
    min: 3600,
    value: 3600,
    format: 'n0'
  });

  // This is for the user access control table (CRUD service)
  var userAccessControlDS = new kendo.data.DataSource({
    transport: {
      read: {
        url: 'UAC_CRUD_service',
        type: 'get',
        dataType: 'json'
      },
      update: {
        url: 'UAC_CRUD_service_update',
        type: 'post',
        dataType: 'json'
      },
      destroy: {
        url: 'UAC_CRUD_service_destroy',
        type: 'post',
        dataType: 'json'
      },
      create: {
        url: 'UAC_CRUD_service_create',
        type: 'post',
        dataType: 'json'
      },
      parameterMap: function(options,operation) {
        if(operation !== 'read' && options.models) {
          return {models: kendo.stringify(options.models)};
        }
      }
    },
    batch: true,
    pageSize: 25,
    schema: {
      model: {
        id: 'id',
        fields: {
          username:      {type: 'text'},
          database:      {type: 'text'},
          permissions:   {type: 'text', defaultValue: { permissions: 'ro'}}
        }
      }
    }
  });
  var userAccessControlGrid = $('#user_permissions_grid').kendoGrid({
    dataSource: userAccessControlDS,
    pageable: true,
    width: '380px',
    toolbar: ['create'],
    columns: [
      {field: 'username',title: 'User Name'},
      {field: 'database', title: 'Database', editor: function(container,options) {
        var textarea = $('<textarea class="k-textbox"></textarea>');
        textarea.attr('name',options.field);
        textarea.appendTo(container);
      }},
      {field: 'permissions', title: 'Permissions', nullable: true, editor: function(container,options){
        console.log(options);
        $('<input required data-text-field="permissionsString" data-value-field="permissions" data-bind="value:' + options.field + '"/>')
        .appendTo(container)
        .kendoDropDownList({
          dataTextField: 'permissionsString',
          dataValueField: 'permissions',
          autoBind: false,
          optionLabel: 'Select',
          index: 0,
          dataSource: [
            {permissionsString: 'Read-Only',permissions: 'ro'},
            {permissionsString: 'Read-Write',permissions: 'rw'}
          ]
        });
      }, template: "#= permissions.permissionsString #"},
      {command: ["edit", "destroy"], title: "&nbsp;" }
    ],
    editable: 'inline',
    groupable: true
  }).data('kendoGrid');

  // Start a database
  $('#startDB').on('click',function(e) {
    if($('#startDB').prop('value') == 'Start') {
      $('#db_name').html($('#selectDB').data('kendoComboBox').value());
      $('#db_status').html('&nbsp;');

      kendo.ui.progress($('#spinner_container'),true);
      startDB();
    }
    else if($('#startDB').prop('value') == 'Stop') {
      $('#db_status').html('&nbsp;');
      var current_database = $('#db_name').html();
      var current_port = $('#db_port').html();

      kendo.ui.progress($('#spinner_container'),true);

      $.get('stop_db?'+'current_database='+current_database+'&current_port='+current_port,function(res) {
        $('#db_name').html('None');
        $('db_port').html('-');
        $('#db_status').text('STOPPED');
        $('#startDB').prop('value','Start');
        localStorage.removeItem('current_pid');
        localStorage.removeItem('current_port');
        kendo.ui.progress($('#spinner_container'), false);
        popup.show('Stopped the current database: '+$('#db_name').html(),'success');
      }).fail(function(xhr) {
        kendo.ui.progress($('#spinner_container'), false);
        popup.show('Failed to Stop the current database: '+$('#db_name').html(),'error');
      });
    }
  });

  // Popup to show graph histograms
  var graphHistogramPopup = $("#graphHistogramsPopup").kendoWindow({
    width: "70%",
    height: "60%",
    title: "Graph Metric Histograms",
    actions: [
      "Minimize",
      "Maximize",
      "Close"
    ],
    resize: function() {
      kendo.resize($("#graphHistogramsPopup"));
    }
  }).data('kendoWindow');

  // Create the results grid for both SELECT and CONSTRUCT queries
  var resultsGrid = $("#resultsGrid").kendoGrid().data('kendoGrid');

  // Color picker, slider, and combobox for graph search highlighting
  var graphSearchColorPicker = $("#graphSearchColorPicker").kendoColorPicker({
    value: "#777ea2",
    buttons: true
  }).data('kendoColorPicker');

  var graphSearchSliderCombobox = $("#graphSearchSliderCombobox").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    suggest: true,
    index: 2
  }).data('kendoComboBox');

  $("#graphSearch").on('mouseover mouseenter', function(e) {
    $("#graphSearch").css("opacity", 1.0);
  });

  $("#graphSearch").on('mouseleave', function(e) {
    $("#graphSearch").css("opacity", 0.7);
  });

  // textarea for codemirror
  var editor = YASQE(document.getElementById("query"), {
  	createShareLink: null,
  	syntaxErrorCheck: true,
  	collapsePrefixesOnLoad: false,
  	lineWrapping: true,
  	persistent: 'YASQEpersistence'
  });


  // combobox for canned queries
  $("#querySelector").kendoComboBox({
    dataTextField: "name",
    dataValueField: "query",
    filter: "contains",
    placeholder: "Precofigured Queries",
    template: '<span class="k-state-default" data-value="#: data.query #">#:data.name#</span>',
    select: function(e) {
      var dataItem = this.dataItem(e.item.index());
      editor.setValue(dataItem.query);
    }
  });

  // Adding a tooltip for canned queries so user can see the query text
  $("#querySelector").data('kendoComboBox').ul.kendoTooltip({
    filter: "li",
    animation: {
      open: {
        effects: 'zoom:in slideIn:right',
        duration: 200
      },
      close: {
        effects: 'zoom:in slideIn:right',
        reverse: true,
        duration: 200
      }
    },
    content: function (e) {
      var target = e.target;
      var escaped = escapeHtml($(target).children().first().attr("data-value"));
      return '<pre class="hoverQuery" style="text-align: left !important; margin-left: 50px;">' + escaped + '</pre>';
    },
    width: 600,
    position: "right"
  });

  // Kendo UI widgets for the graph visual property changes.  These are used in the 'alterNodes' function
  $('#changeNodeSizeCombobox').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    placeholder: "Available numeric properties"
  });

  $('#CNCColorPicker').kendoColorPicker({
    value: $('#background-color').val(),
    buttons: true,
    change: function() {
      // Need to remove the icons if they are there
      cy.nodes().removeClass('.node_icons');

      cy.style().selector('node').style('background-color',$('#CNCColorPicker').val()).update();
    }
  });

  $('#CNCpropertyCombobox').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    placeholder: "Available numeric properties"
  });

  $('#CNClowNumber').kendoColorPicker({
    value: '#0075b8',
    buttons: true
  });

  $('#CNChighNumber').kendoColorPicker({
    value: '#dc4e4e',
    buttons: true
  });

  $('#CNCstringPropertyCombobox').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    placeholder: "Available string properties",
    change: function(event) {
      var newValue = this.value();
      var valueArray = [];
      $('.deleteMeCP').remove();

      cy.nodes().each(function(index,node) {
        valueArray.push(node.data(newValue));
      });

      var unique = [];
      sortUnique(valueArray);

      $.each(valueArray,function(index, value) {
        $('#CNCstringPropertiesTable').append("<tr class=\"deleteMe deleteMeCP\"><td class=\"deleteMeTdFirst\" id=\"PP"+index+"\">"+value+"</td><td class=\"deleteMeTdLast\"><input id=\"CP"+index+"\"</td></tr>");
        $('#CP'+index).kendoColorPicker({
          value: $('#background-color').val(),
          buttons: true
        });
      });
    }
  });

  // Maybe change this later, but for now, set up our shared data source and then read it when the combobox is actually accessed
  var imagesDataSource = new kendo.data.DataSource({
    type: 'json',
    transport: {
      read: '/graph_icon_list'
    }
  });

  $('#CNIstringPropertyCombobox').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    placeholder: "Available string properties",
    change: function(event) {
      var newValue = this.value();
      var valueArray = [];
      $('.deleteMeIP').remove();

      cy.nodes().each(function(index,node) {
        valueArray.push(node.data(newValue));
      });

      var unique = [];
      sortUnique(valueArray);

      $.each(valueArray,function(index, value) {
        $('#CNIstringPropertiesTable').append("<tr class=\"deleteMe deleteMeIP\"><td class=\"deleteMeTdFirst\" id=\"PP"+index+"\">"+value+"</td><td class=\"deleteMeTdLast\"><input id=\"IP"+index+"\"</td></tr>");
        $('#IP'+index).kendoComboBox({
          dataTextField: 'name',
          dataValueField: 'url',
          dataSource: imagesDataSource,
          autoBind: false,
          template: '<span class="k-state-default"><img src="#:data.url#" alt="#:data.name#" style="max-width: 24px;"></span>'
        });
      });
    }
  });

  $('#CNSstringPropertyCombobox').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    placeholder: "Available string properties",
    change: function(event) {
      var newValue = this.value();
      var valueArray = [];
      $('.deleteMeSP').remove();

      cy.nodes().each(function(index,node) {
        valueArray.push(node.data(newValue));
      });

      var unique = [];
      sortUnique(valueArray);

      // Need to make sure that when we set the index of the comboboxes, we dont go past the list length
      var listLength = $("#shape").data('kendoComboBox').dataSource.data().length;
      var listCounter = 0;
      $.each(valueArray,function(index, value) {
        if(listCounter >= listLength) {
          listCounter = 0;
        }
        $('#CNSstringPropertiesTable').append("<tr class=\"deleteMe deleteMeSP\"><td class=\"deleteMeTdFirst\" id=\"PP"+index+"\">"+value+"</td><td class=\"deleteMeTdLast\"><input id=\"SP"+index+"\"</td></tr>");
        $('#SP'+index).kendoComboBox({
          dataTextField: "text",
          dataValueField: "value",
          dataSource: [
            { text: "Diamond"          , value: "diamond" },
            { text: "Ellipse"          , value: "ellipse" },
            { text: "Hexagon"          , value: "hexagon" },
            { text: "Heptagon"         , value: "heptagon" },
            { text: "Octagon"          , value: "octagon" },
            { text: "Pentagon"         , value: "pentagon" },
            { text: "Rectangle"        , value: "rectangle" },
            { text: "Rhomboid"         , value: "rhomboid" },
            { text: "Rounded rectangle", value: "roundrectangle" },
            { text: "Star"             , value: "star" },
            { text: "Triangle"         , value: "triangle" },
            { text: "Vee"              , value: "vee" }
          ],
          filter: "contains",
          suggest: true,
          index: listCounter
        });
        listCounter++;
      });
    }
  });

  $('#CNSShapePicker').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Diamond"          , value: "diamond" },
      { text: "Ellipse"          , value: "ellipse" },
      { text: "Hexagon"          , value: "hexagon" },
      { text: "Heptagon"         , value: "heptagon" },
      { text: "Octagon"          , value: "octagon" },
      { text: "Pentagon"         , value: "pentagon" },
      { text: "Rectangle"        , value: "rectangle" },
      { text: "Rhomboid"         , value: "rhomboid" },
      { text: "Rounded rectangle", value: "roundrectangle" },
      { text: "Star"             , value: "star" },
      { text: "Triangle"         , value: "triangle" },
      { text: "Vee"              , value: "vee" }
    ],
    filter: "contains",
    suggest: true,
    index: 1,
    change: function() {
      // Need to remove the icons if they are there
      cy.nodes().removeClass('.node_icons');
      cy.style().selector('node').style('shape',$('#CNSShapePicker').val()).update();
    }
  });

  // combobox for query history
  var queryHistory = $("#queryHistory").kendoComboBox({
    dataTextField: "name",
    dataValueField: "query",
    filter: "contains",
    placeholder: "Query History",
    template: '<span class="k-state-default" data-value="#: data.query #">#:data.name#</span>',
    select: function(e) {
      var dataItem = this.dataItem(e.item.index());
      editor.setValue(dataItem.query);
    }
  }).data("kendoComboBox");

  // If we have a query history, load it
  if (localStorage.getItem("queryHistory") !== null) {
    var qh = JSON.parse(localStorage.getItem('queryHistory'));
    var queriesDS = new kendo.data.DataSource({
        data: qh
    });
    queryHistory.setDataSource(queriesDS);
  }

  // Adding a tooltip for the query history so user can see the query text
  queryHistory.ul.kendoTooltip({
    filter: "li",
    animation: {
      open: {
        effects: 'zoom:in slideIn:right',
        duration: 200
      },
      close: {
        effects: 'zoom:in slideIn:right',
        reverse: true,
        duration: 200
      }
    },
    content: function (e) {
      var target = e.target; // element for which the tooltip is shown
      var escaped = escapeHtml($(target).children().first().attr("data-value"));
      return '<pre class="hoverQuery" style="text-align: left !important; margin-left: 50px; white-space: pre-wrap;">' + escaped + '</pre>';
    },
    width: 600,
    position: "right"
  });

  // Clear the query history
  $("#clearHistory").on('click', function() {
    localStorage.removeItem('queryHistory');
    queryHistory.setDataSource();
    popup.show("Query history has been deleted from local storage.","success");
  });

  // Save query form popup
  var queryPopup = $("#QuerySavePopup").kendoWindow({
    width: "290px",
    title: "Save Query",
    actions: [
        "Close"
    ]
  }).data('kendoWindow');

  // Save the query in the text editor
  $("#querySave").on('click', function() {
    queryPopup.center().open();
  });

  $("#querySaveForm").submit(function(event) {
    var queryTitle = $("#queryName").val();
    var q = editor.getValue();
    var priv = $('input[name=privateQuery]:checked').val();
    $.post('saveQuery', { title: queryTitle, query: q, private: priv }, function() {
      queryPopup.close();
      popup.show("Saved " + queryTitle,"success");
    }).fail(function(xhr) {
      queryPopup.close();
      popup.show("Save failed (" + xhr.status + " " + xhr.statusText + ")" ,"error");
    });
    event.preventDefault();
  });

  // Accordion menu for various settings
  // First menu item is graph settings (cytoscape.js)
  // But first, initialize all the settings widgets
  // Graph (cytoscape.js) settings
  // Iterate over sliders
  $('.kslider').each(function(index,obj) {
  	var value = Number($('#'+$(this).attr('id')+'Box').attr('value'));
  	var min = Number($('#'+$(this).attr('id')+'Box').attr('min'));
  	var max = Number($('#'+$(this).attr('id')+'Box').attr('max'));
  	var ss;
  	var ls;
  	if(max <= 1) {
  		ss = 0.01;
  		ls = 0.1;
  	}
  	else if(max <= 100) {
  		ss = 1;
  		ls = 10;
  	}
  	else if(max <= 1000) {
  		ss = 10;
  		ls = 100;
  	}
  	else {
  		ss = 100;
  		ls = 1000;
  	}

  	$(this).kendoSlider({
	    smallStep: ss,
	    largeStep: ls,
	    min: min,
	    max: max,
	    tickPlacement: 'none',
	    decreaseButtonTitle: '',
	    increaseButtonTitle: '' ,
	    value: value,
	    slide: function(e) {
	      $(this.element[0]).closest('td').prev('td').find('input').val(e.value);
	      $(this.element[0]).closest('td').prev('td').find('input').trigger('change');
	    },
	    change: function(e) {
	      $(this.element[0]).closest('td').prev('td').find('input').val(e.value);
	      $(this.element[0]).closest('td').prev('td').find('input').trigger('change');
	    }
	  });
  });

  // Iterate over color pickers
  $('.kcolorPicker').each(function(index,obj) {
  	var value = $(this).attr('value');
  	$(this).kendoColorPicker({
	    value: value,
	    buttons: true
	  });
  });

  var targetArrowShape = $("#target-arrow-shape").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Triangle"           , value: "triangle" },
      { text: "Tee"                , value: "tee" },
      { text: "Triangle-tee"       , value: "triangle-tee" },
      { text: "Triangle-back curve", value: "triangle-backcurve" },
      { text: "Square"             , value: "square" },
      { text: "Circle"             , value: "circle" },
      { text: "Diamond"            , value: "diamond" },
      { text: "None"               , value: "none" }
    ],
    filter: "contains",
    suggest: true,
    index: 3
  }).data('kendoComboBox');

  var nodeShape = $("#shape").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Diamond"          , value: "diamond" },
      { text: "Ellipse"          , value: "ellipse" },
      { text: "Hexagon"          , value: "hexagon" },
      { text: "Heptagon"         , value: "heptagon" },
      { text: "Octagon"          , value: "octagon" },
      { text: "Pentagon"         , value: "pentagon" },
      { text: "Rectangle"        , value: "rectangle" },
      { text: "Rhomboid"         , value: "rhomboid" },
      { text: "Rounded rectangle", value: "roundrectangle" },
      { text: "Star"             , value: "star" },
      { text: "Triangle"         , value: "triangle" },
      { text: "Vee"              , value: "vee" }
    ],
    filter: "contains",
    suggest: true,
    index: 1
  }).data('kendoComboBox');

  var targetArrowFill = $("#target-arrow-fill").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Filled", value: "filled" },
      { text: "Hollow", value: "hollow" }
    ],
    filter: "contains",
    suggest: true,
    index: 0
  }).data('kendoComboBox');

  var selectionType = $("#selectionType").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Single"  , value: "single" },
      { text: "Additive", value: "additive" }
    ],
    filter: "contains",
    suggest: true,
    index: 0
  }).data('kendoComboBox');

  var curveStyle = $("#curve-style").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Bezier"                   , value: "bezier" },
      { text: "Unbundled bezier"         , value: "unbundled-bezier" },
      { text: "Multiple unbundled bezier", value: "multi-unbundled-bezier" },
      { text: "Haystack"                 , value: "haystack" },
      { text: "Segments"                 , value: "segments" }
    ],
    filter: "contains",
    suggest: true,
    index: 2
  }).data('kendoComboBox');

  var lineStyle = $("#line-style").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Solid" , value: "solid" },
      { text: "Dotted", value: "dotted" },
      { text: "Dashed", value: "dashed" }
    ],
    filter: "contains",
    suggest: true,
    index: 0
  }).data('kendoComboBox');

  // Layout selection and settings
  var layoutSelector = $("#layoutSelector").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Arbor"       , value: "arbor" },
      { text: "Breadthfirst", value: "breadthfirst" },
      { text: "Circle"      , value: "circle" },
      { text: "Cola"        , value: "cola" },
      { text: "Cose"        , value: "cose" },
      { text: "Cose-bilkent", value: "cose-bilkent" },
      { text: "Dagre"       , value: "dagre" },
      { text: "Grid"        , value: "grid" },
      // { text: "Hive Plot"   , value: "hiveplot" },
      // { text: "JGraph"      , value: "jgraph" },
      { text: "Random"      , value: "random" },
      { text: "Spread"      , value: "spread" },
      { text: "Springy"     , value: "springy" }
    ],
    filter: "contains",
    suggest: true,
    index: 8,
    change: function(e) {
    	$(".lsettr").addClass("hidden_layout_options");
    	var newselection = this.value();
    	$("#"+newselection).removeClass("hidden_layout_options");
    }
  }).data('kendoComboBox');

  // Combobox to hold all the node properties that are numeric for use in node mass calculations
  var arbornodeMass = $("#arbornodeMass").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    suggest: true
  }).data('kendoComboBox');

  var dagrerankDir = $("#dagrerankDir").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Top to bottom", value: "TB" },
      { text: "Left to right", value: "LR" }
    ],
    filter: "contains",
    suggest: true,
    index: 0
  }).data('kendoComboBox');

  var jgraphshader = $('#jgraphShader').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Basic"  , value: "basic" },
      { text: "Lambert", value: "lambert" },
      { text: "Phong"  , value: "phong" },
      { text: "Toon"   , value: "toon" }
    ],
    index: 1
  }).data('kendoComboBox');

  $('#hiveplothiveplotType').kendoComboBox({
    dataTextField: 'text',
    dataValueField: 'value',
    dataSource: [
      { text: 'Single', value: 'single' },
      { text: 'Panel', value: 'panel' }
    ],
    index: 0
  });

  $('#hiveplotaxisFilterType').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Numeric", value: "numeric" },
      { text: "String" , value: "string" }
    ],
    index: 0
  });

  $('#hiveplotaxisSortDirection').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    dataSource: [
      { text: "Ascending" , value: "asc" },
      { text: "Descending", value: "desc" }
    ],
    index: 0
  });

  $('#hiveplotaxisProperty').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value"
  });

  $('#hiveplotaxisSort').kendoComboBox({
    dataTextField: "text",
    dataValueField: "value"
  });

  // Need to populate the textboxes before each slider with the current value of the slider on the right
  $(".numbox").each(function() {
    var sliderValue = $(this).parent().next('td').find('input').val();
    $(this).val(sliderValue);
  });

  // Now, need to update the slider value if the user types a number in manually
  $(".numbox").on('change', function() {
    $("#" + $(this).parent().next('td').find('input').attr('id')).data('kendoSlider').value($(this).val());
  });

  // Finally, the panelbar itself
  var settingsPanelBar = $("#settingsPanelBar").kendoPanelBar({
    expandMode: 'single'
  }).data('kendoPanelBar');

  // All the widgets for the visualization set up for SELECT query
  var vizChartType = $("#vizChartType").kendoComboBox({
    dataTextField: "text",
    dataValueField: "value",
    filter: "contains",
    suggest: true
  }).data('kendoComboBox');

  // Go ahead and connect the websockets
  websocketConnect();

  // Open dialog to create new database
  $('#new_db').on('click',function(e) {
    new_database_window.center().open();
  });

  // Create new database
  $('#createDB').on('click',function(e) {
    $('#db_name').html($('#new_db_name').val());
    $('#db_status').html('&nbsp;');
    var items = $('#file_browser').data('kendoTreeView').getCheckedItems();
    var files = [];
    $.each(items,function(i,v){
      files.push(v.path);
    });

    kendo.ui.progress($('#spinner_container'),true);
    buildDB(files);
  });

  // query execution button that grabs the query for the most recently focused query source (SPARQL editor, history, or canned)
  $("#querySubmitButton").on("click", function(e) {
    // Let's make sure we are clearing out the work area and the popup contents
    $("#viz_main").empty();

    // Get YASQE to tell us what type of query we are running
    var queryType = editor.getQueryType();

    // refactored so that we can clean up the on-click function and also make other query types in a more modular way
    switch(queryType) {
      case 'SELECT':
        kendo.ui.progress($('#query_progress'),true);
        sparqlSelect();
        break;
      case 'CONSTRUCT':
        kendo.ui.progress($('#query_progress'),true);
        sparqlConstruct();
        break;
      case 'ASK':
        kendo.ui.progress($('#query_progress'),true);
        sparqlAsk();
        break;
      case 'DESCRIBE':
        kendo.ui.progress($('#query_progress'),true);
        sparqlDescribe();
        break;
      case 'INSERT':
        kendo.ui.progress($('#query_progress'),true);
        sparqlInsert();
        break;
      default:
        popup.show("Unrecognized query type.","error");
        break;
    }
  });

  //=========================================================
  //============================ Set up functions
  //=========================================================
  // Functions to do each of the query types (SELECT, CONSTRUCT, ASK, DESCRIBE, INSERT)
  // SELECT
  function sparqlSelect() {
    $.post("sparqlSelect", { current_database: $("#db_name").html(), current_port: $('#db_port').html(),'query': editor.getValue() }).done(function(data, textStatus, xhr) {

			// If the query worked, store it
      storeQueryHistory(query);

			// It would appear we can still get an empty result set...so let's kill it here if we do
			if (data.results.results.bindings.length == 0) {
				popup.show("Error, no results (" + xhr.status + " " + xhr.statusText + ")","error");
				return;
			}

      // Hide the graph search panel
      $("#graphSearch").fadeOut(1400);

      var dataBindings = [];
	    var fieldTypes = {};
	    var columns = [];
      var fields = [];
      var comboboxStringFields = [];
	    var comboboxNumberFields = [];

	    // Process the actual data.
      $.each(data.results.results.bindings, function(index1, value) {
        var tempobj = {};
        $.each(value, function(k1,v1) {
          tempobj[k1] = v1.value;

					// Need to set the type of the field...probably a better way to do this, but it works
					// TODO Need to double check with dates to make sure this displays properly
					if (v1.hasOwnProperty("datatype")) {
						if (/#string/.test(v1.datatype)) {
							fieldTypes[k1] = { type: "string", name: k1 };
						}
						else if(/#date/.test(v1.datatype)) {
							fieldTypes[k1] = { type: "date", name: k1 };
						}
						else  {
							fieldTypes[k1] = { type: "number", name: k1 };
						}
					}
					else {
						fieldTypes[k1] = { type: "string", name: k1 };
					}
        });
        tempobj.id=index1;
        dataBindings.push(tempobj);
      });

			// Create a variable to keep track of how many numeric fields we have
			var numNumericFields = 0;

			// Disable chart types as appropriate
			$.each(fieldTypes, function(index,object) {
				if (object.type == "number") {
					numNumericFields++;
				}
			});

			disableChartTypes(numNumericFields);

  		// Process the column headers
  		$.each(data.results.head.vars, function(index, value) {
        columns.push({'field': value, 'title': value});
        var to = {};
        to[value] = {type: "string"};
        fields.push(to);

        // Let's also populate the two Comboboxes for the Visualization while we are at it
        if (fieldTypes[value].type == "string") {
					comboboxStringFields.push({'text': value, 'value': value});
				}
				else if (fieldTypes[value].type == "number") {
					comboboxNumberFields.push({'text': value, 'value': value});
				}
				else {
					// TODO need to do something with dates to treat them as an axis
					console.log("Got dates!");
				}
      });

      var configuration = {
        dataSource: {
          data: dataBindings,
          pageSize: 25,
					schema: {
						model: {
							fields: fieldTypes
						}
					}
        },
        height: "100%",
        scrollable: true,
        sortable: true,
        filterable: true,
        reorderable: true,
        resizable: true,
        toolbar: ["excel"],
        excel: {
          allPages: true,
          filterable: true,
          proxyURL: "/saveExcel"
        },
        pageable: {
          input: true,
          numeric: false,
          pageSizes: [10,25,50,100, "all"]
        },
        columns: columns
      };

      // Create the popup window
      var gridWindow = $("#resultsPopup").kendoWindow({
        width: "70%",
				height: "60%",
        title: "Query Results",
        actions: [
            "Minimize",
            "Maximize",
            "Close"
        ],
				resize: function() {
					resultsGrid.resize();
				}
      }).data('kendoWindow');

      // Center and show the popup window
      gridWindow.center().open();

      // Create/update/refresh the grid
      resultsGrid.setOptions(configuration);
      resultsGrid.dataSource.page(1);

			// Create the comboboxes for each potential series and value field/Axis depending on the type of chart selected
			vizChartType.bind('select', function(event) {
				var dataItem = this.dataItem(event.item.index());

				// Need to remove all table rows except for the first one
				$("#vizSettingsTable").find("tr:gt(3)").remove();

				// Need to create different setup types depending on the selected type of chart (e.g. series vs X Y axis, bar/column vs. scatter)
				if (/^Area$|^Bar$|^Column$|^Line$|^Radar-Area$|^Radar-Column$|^Vertical-Area$|^Vertical-Line$/.test(dataItem.text)) {
					// Show the distibution row
					$(".hideRow").show();

					// First the series names
					var dropdownNum = 1;
					$.each(fieldTypes, function(index,object) {
						if (object.type == "string") {
							var addedRow = '<tr><td>Series ' + dropdownNum + '</td><td><input id="series' + dropdownNum + '" class="vizCombo vizSeries" placeholder="Select Series ' + dropdownNum + '" /></td></tr>';

							// Append the new row
							$("#vizSettingsTable tbody").append(addedRow);

							// After it has been appended, initialize the combobox
							$("#series" + dropdownNum).kendoComboBox({
								dataTextField: "text",
								dataValueField: "value",
								dataSource: comboboxStringFields,
								filter: "contains",
								suggest: true
							});
							dropdownNum++;
						}
					});

					// Now, the numeric fields
					var addedRow = '<tr><td>Value Axis</td><td><input id="valueAxis" class="vizCombo vizValues" placeholder="Select Value Axis" /></td></tr>';

					// Append the new row
					$("#vizSettingsTable tbody").append(addedRow);

					// After it has been appended, initialize the combobox
					$("#valueAxis").kendoComboBox({
						dataTextField: "text",
						dataValueField: "value",
						dataSource: comboboxNumberFields,
						filter: "contains",
						suggest: true
					});
				}
				else if (/^Bubble$|^Polar-Area$|^Polar-Line$|^Polar-Scatter$|^Scatter$|^Scatter-Line$/.test(dataItem.text)) {
					// Hide the distribution row
					$(".hideRow").hide();

					// First the series names
					var dropdownNum = 1;
					$.each(fieldTypes, function(index,object) {
						if (object.type == "string") {
							var addedRow = '<tr><td>Series ' + dropdownNum + '</td><td><input id="series' + dropdownNum + '" class="vizCombo vizSeries" placeholder="Select Series ' + dropdownNum + '" /></td></tr>';

							// Append the new row
							$("#vizSettingsTable tbody").append(addedRow);

							// After it has been appended, initialize the combobox
							$("#series" + dropdownNum).kendoComboBox({
								dataTextField: "text",
								dataValueField: "value",
								dataSource: comboboxStringFields,
								filter: "contains",
								suggest: true
							});
							dropdownNum++;
						}
					});

					// Add two value axis comboboxes
					addedRow = '<tr><td>X Axis</td><td><input id="XAxis" class="vizCombo" placeholder="Select X Axis" /></td></tr>';
					$("#vizSettingsTable tbody").append(addedRow);

					addedRow = '<tr><td>Y Axis</td><td><input id="YAxis" class="vizCombo" placeholder="Select Y Axis" /></td></tr>';
					$("#vizSettingsTable tbody").append(addedRow);

					// After it has been appended, initialize the combobox
					$("#XAxis").kendoComboBox({
						dataTextField: "text",
						dataValueField: "value",
						dataSource: comboboxNumberFields,
						filter: "contains",
						suggest: true
					});

					$("#YAxis").kendoComboBox({
						dataTextField: "text",
						dataValueField: "value",
						dataSource: comboboxNumberFields,
						filter: "contains",
						suggest: true
					});
				}
			});

      // Visualize SELECT results
      $("#chart_display_button").on('click',function() {
        // empty the viz area
        $("#viz_main").empty();

        // add a dummy container that we can destroy later
        $("#viz_main").html('<div id="chartContainer"></div>');

        // Loop through the result set to create the appropriate arrays
        var chartData = [];
        var catAxis = $("#vizCategoryAxis").val();
        var valAxis = $("#vizValueAxis").val();

				// Figure out if we want a log scale or not
				var wantLogScale = $('input[name=logScale]:checked', '#vizSettings').val();
				if (wantLogScale == "true") {
					wantLogScale = "log";
				}
				else {
					wantLogScale = "numeric";
				}

				// We need to know what chart type we are dealing with
				var chartType = vizChartType.value();

				// Figure out if we want a value distribution or not
				var wantDistribution = $('input[name=distributionRadioButton]:checked', '#vizSettings').val();
				if (/^polarArea$|^polarLine$|^polarScatter$|^scatter$|^scatterLine$/.test(chartType)) {
					var seriesWanted = [];
					var seriesData = {};
					var seriesArray = [];
					var xAxis = $("#XAxis").data('kendoComboBox').value();
					var yAxis = $("#YAxis").data('kendoComboBox').value();

					$(".vizSeries input").each(function(index,object) {
						if ($(object).attr('id')) {
							if ($("#" + $(object).attr('id')).data('kendoComboBox').value() != '') {
								var seriesName = $("#" + $(object).attr('id')).data('kendoComboBox').value();
								seriesWanted.push(seriesName);
								seriesData[seriesName] = [];
							}
						}
					});

					// Now, iterate over the results and push them to the appropriate data arrays
					$.each(data.results.results.bindings, function(index1,object1) {
						$.each(seriesWanted, function(index2,object2) {
							var XX = parseFloat(object1[xAxis].value) || 0;
							var YY = parseFloat(object1[yAxis].value) || 0;
							var category = object1[object2].value || '0';

							var tmpObj = {x: XX, y: YY, category: category };
							seriesData[object2].push(tmpObj);
						});
					});

					// Finally, get the series data into the appropriate array
					$.each(seriesData, function(key,objt) {
						var toj = {name: key, data: objt};
						seriesArray.push(toj);
					});

					// create the desired chart
					$("#chartContainer").kendoChart({
						theme: "Material",
						title: {
							align: "left",
							text: "Result Set Visualization",
							color: "black"
						},
						legend: {
							visible: false
						},
						seriesDefaults: {
							type: $("#vizChartType").val(),
							tooltip: {
								visible: true,
								template: "#: dataItem.category #: #: value.x #,#: value.y #"
							}
						},
						series: seriesArray,
						xAxis: {
							field: 'x',
							title: {
								text: xAxis
							}
						},
						yAxis: {
							field: 'y',
							title:  {
								text: yAxis
							}
						},
						categoryAxis: {
							field: 'category',
							majorGridLines: {
								visible: false
							},
							labels: {
								visible: false,
								step: 2,
								rotation: 90
							}
						}
					});
				}
				else if (/^area$|^bar$|^column$|^line$|^radarArea$|^radarColumn$|^verticalArea$|^verticalLine$/.test(chartType)) {
					if (wantDistribution == 'true') {
						// iterate over each of the selected series fields and push onto an array
						var seriesWanted = [];
						var seriesData = {};
						var seriesArray = [];
						var tempValueObj = {};

						var measureName = $("#valueAxis").data('kendoComboBox').value();

						$(".vizSeries input").each(function(i,object) {
							if ($(object).attr('id')) {
								if ($("#" + $(object).attr('id')).data('kendoComboBox').value() != '') {
									var seriesName = $("#" + $(object).attr('id')).data('kendoComboBox').value();
									seriesWanted.push(seriesName);
									tempValueObj[seriesName] = {};
								}
							}
						});

						// Now, iterate over the results and push them to the appropriate data arrays
						$.each(data.results.results.bindings, function(index1,object1) {
							$.each(seriesWanted, function(index2,object2) {
								var number = parseFloat(object1[measureName].value) || 0;
								var roundedNumberString = parseFloat(number.toFixed(1));

								if (tempValueObj[object2].hasOwnProperty(roundedNumberString)) {
									tempValueObj[object2][roundedNumberString]++;
								}
								else {
									tempValueObj[object2][roundedNumberString] = 1;
								}
							});
						});

						// Finally, get the series data into the appropriate array
						$.each(tempValueObj, function(key,objt) {
							var toj = { name: key, tooltip: { visible: true, template: "#: dataItem.category #: #: value #" }};
							toj.data = [];
							$.each(objt, function(key1,value) {
								var toj1 = {category: key1, value: value};
								toj.data.push(toj1);
							});
							seriesArray.push(toj);
						});

						// create the desired chart
						$("#chartContainer").kendoChart({
							theme: "Material",
							title: {
								align: "left",
								text: "Result Set Visualization",
								color: "black"
							},
							legend: {
								visible: false
							},
							seriesDefaults: {
								type: $("#vizChartType").val()
							},
							series: seriesArray,
							valueAxis: {
								field: 'value',
								type: wantLogScale,
								majorGridLines: {
										visible: false
								}
							},
							categoryAxis: {
								field: 'category',
								majorGridLines: {
									visible: false
								},
								labels: {
									visible: false,
									step: 2,
									rotation: 90
								}
							}
						});
					}
					else {
						console.log("got to the else, even though the distribution is wanted");
						// iterate over each of the selected series fields and push onto an array
						var seriesWanted = [];
						var seriesData = {};
						var seriesArray = [];

						var measureName = $("#valueAxis").data('kendoComboBox').value();

						$(".vizSeries input").each(function(i,object) {
							if ($(object).attr('id')) {
								if ($("#" + $(object).attr('id')).data('kendoComboBox').value() != '') {
									var seriesName = $("#" + $(object).attr('id')).data('kendoComboBox').value();
									seriesWanted.push(seriesName);
									seriesData[seriesName] = [];
								}
							}
						});

						// Now, iterate over the results and push them to the appropriate data arrays
						$.each(data.results.results.bindings, function(index1,object1) {
							$.each(seriesWanted, function(index2,object2) {
								var value = parseFloat(object1[measureName].value) || 0;
								var category = object1[object2].value || '0';

								var tmpObj = {value: value, category: category };
								seriesData[object2].push(tmpObj);
							});
						});

						// Finally, get the series data into the appropriate array
						$.each(seriesData, function(key,objt) {
							var toj = {name: key, data: objt};
							seriesArray.push(toj);
						});

						// create the desired chart
						$("#chartContainer").kendoChart({
							theme: "Material",
							title: {
								align: "left",
								text: "Result Set Visualization",
								color: "black"
							},
							legend: {
								visible: false
							},
							seriesDefaults: {
								type: $("#vizChartType").val(),
								tooltip: {
									visible: true,
									template: "#: dataItem.category #: #: value #"
								}
							},
							series: seriesArray,
							valueAxis: {
								field: 'value',
								type: wantLogScale,
								majorGridLines: {
										visible: false
								}
							},
							categoryAxis: {
								field: 'category',
								majorGridLines: {
									visible: false
								},
								labels: {
									visible: false,
									step: 2,
									rotation: 90
								}
							}
						});
					}
				}
				return;

				// Create object to hold min and max values
				var minMaxObject = {};

				if (wantDistribution == "true") {
					// First create a temp object to aggregate the values
					var tempValueObj = {};
					$.each(data.results.results.bindings, function(index1,object1) {
						var number = parseFloat(object1[valAxis].value) || 0;
						var roundedNumberString = parseFloat(number.toFixed(1));
						if (tempValueObj.hasOwnProperty(roundedNumberString)) {
							tempValueObj[roundedNumberString]++;
						}
						else {
							tempValueObj[roundedNumberString] = 1;
						}
					});

					// Now create the array for the chart
					$.each(tempValueObj, function(index1,object1) {
						var tempObj = {};
						tempObj[catAxis] = parseFloat(index1);
						tempObj[valAxis] = object1;

						chartData.push(tempObj);

						if (minMaxObject.hasOwnProperty(valAxis)) {
							if (tempObj[valAxis] > minMaxObject[valAxis].max) {
								minMaxObject[valAxis].max = tempObj[valAxis];
							}
							if (tempObj[valAxis] < minMaxObject[valAxis].min) {
								minMaxObject[valAxis].min = tempObj[valAxis];
							}
						}
						else {
							minMaxObject[valAxis] = {};
							minMaxObject[valAxis].min = tempObj[valAxis];
							minMaxObject[valAxis].max = tempObj[valAxis];
						}
					});
				}
				else {
					$.each(data.results.results.bindings, function(index1,object1) {
						var tempObj = {};
						tempObj[catAxis] = object1[catAxis].value || 0;
						tempObj[valAxis] = object1[valAxis].value || 0;
						chartData.push(tempObj);

						if (minMaxObject.hasOwnProperty(valAxis)) {
							if (tempObj[valAxis] > minMaxObject[valAxis].max) {
								minMaxObject[valAxis].max = tempObj[valAxis];
							}
							if (tempObj[valAxis] < minMaxObject[valAxis].min) {
								minMaxObject[valAxis].min = tempObj[valAxis];
							}
						}
						else {
							minMaxObject[valAxis] = {};
							minMaxObject[valAxis].min = tempObj[valAxis];
							minMaxObject[valAxis].max = tempObj[valAxis];
						}
					});
				}

        // create the desired chart
        var chartDS = new kendo.data.DataSource({
          data: chartData,
          sort: { field: $("#vizCategoryAxis").val(), dir: "asc" }
        });

        $("#chartContainer").kendoChart({
          dataSource : chartDS,
          theme: "Material",
          tooltip: {
            visible: true,
            template: "#: category #: #: value #"
          },
          title: {
            align: "left",
            text: "Result Set Visualization",
            color: "black"
          },
          legend: {
            visible: false
          },
          seriesDefaults: {
            type: $("#vizChartType").val()
          },
          series: [{
            field: valAxis
          }],
          valueAxis: {
            field: valAxis,
						type: wantLogScale,
            majorGridLines: {
                visible: false
            }
          },
          categoryAxis: {
            field: catAxis,
            majorGridLines: {
              visible: false
            },
            labels: {
              visible: false,
              step: 2,
              rotation: 90
            }
          }
        });

				// Change function for log scale radio button.  We set it initially, but need to be able to change dynamically
				$('input[name=logScale]').on('change',function() {
					var wls = $('input[name=logScale]:checked', '#vizSettings').val();
					if (wls == "true") {
						$("#chartContainer").data('kendoChart').setOptions({ valueAxis: { type: "log" }});
					}
					else {
						$("#chartContainer").data('kendoChart').setOptions({ valueAxis: { type: "numeric" }});
					}
				});

        // Need to resize the chart when the window is resized
        $(window).resize(function(){
          kendo.resize($(".k-chart"));
        });
      });
      kendo.ui.progress($('#query_progress'),false);
      $('.c-hamburger').trigger('click');
    }).fail(function(xhr) {
      kendo.ui.progress($('#query_progress'),false);
      popup.show("Error, no results (" + xhr.status + " " + xhr.statusText + ")","error");
    });
  }

  // CONSTRUCT
  function sparqlConstruct() {
    $.post("sparqlConstruct", { current_database: $("#db_name").html(),'query': editor.getValue() }).done(function(data, textStatus, xhr) {

      // If the query worked, store it
      storeQueryHistory(query);
      $('.c-hamburger').trigger('click');
      // Draw the graph
      drawGraph(data.elements);
    }).fail(function(xhr) {
      kendo.ui.progress($('#query_progress'),false);
      popup.show("Error, no results (" + xhr.status + " " + xhr.statusText + ")","error");
    });
  }

  // ASK
  function sparqlAsk() { popup.show("Not implemented yet.  Hold your horses!","info"); }

  // DESCRIBE
  function sparqlDescribe() { popup.show("Not implemented yet.  Hold your horses!","info"); }

  // INSERT/INSERT DATA
  function sparqlInsert() {
		$.post("sparqlInsert", { current_database: $("#db_name").html(),'query': editor.getValue() }).done(function(data, textStatus, xhr) {
			popup.show("Update executed successfully.","success");
		}).fail(function(xhr) {
      kendo.ui.progress($('#query_progress'),false);
      popup.show("Error, no results (" + xhr.status + " " + xhr.statusText + ")","error");
    });
	}

  // Function to start a database
  function startDB() {
    var dataDir       = $('#selectDB').data('kendoComboBox').value();
    var imagesPerNode = $('#instances').val();
    var nodeCount     = $('#nodes').val();
    var timeout       = $('#timeout').val();
    var nvps          = $('#nvps').val();

    $.post('start_db',{ dataDir: dataDir, imagesPerNode: imagesPerNode, nodeCount: nodeCount, startupTimeout: timeout, nvps: nvps }).done(function(res, textStatus, xhr) {
      // Assuming the startup works, set the current database
      $('#db_status').text('RUNNING');
      $('#startDB').prop('value','Stop');
      $('#db_port').html(res.port);
      localStorage.setItem('current_pid',res.pid);
      localStorage.setItem('current_port',res.port);
      localStorage.setItem('current_database',dataDir);
      kendo.ui.progress($('#spinner_container'), false);
    }).fail(function(xhr) {
      kendo.ui.progress($('#spinner_container'), false);
      popup.show("Failed to start the requested database (" + xhr.status + " " + xhr.statusText + ")" ,"error");
    });
  };

  function buildDB(files) {
    var name          = $('#new_db_name').val();
    var imagesPerNode = $('#new_instances').val();
    var nodeCount     = $('#new_nodes').val();
    var timeout       = $('#new_timeout').val();
    var nvps          = $('#new_nvps').val();

    $.post('build_db',{ name: name, imagesPerNode: imagesPerNode, nodeCount: nodeCount, startupTimeout: timeout, nvps: nvps, files: files }).done(function(res, textStatus, xhr) {
      // Assuming the startup works, set the current database
      $('#db_name').html(res.current_database);
      $('#db_port').html(res.port);
      $('#db_status').text('RUNNING');
      $('#startDB').prop('value','Stop');
      localStorage.setItem('current_pid',res.pid);
      localStorage.setItem('current_port',res.port);
      localStorage.setItem('current_database',res.current_database);
      kendo.ui.progress($('#spinner_container'), false);
    }).fail(function(xhr) {
      kendo.ui.progress('#startDB',false);
      popup.show("Failed to start the requested database (" + xhr.status + " " + xhr.statusText + ")" ,"error");
    });
  }

  // Function to search and filter the treeview of available N-triples files
  function InitSearch(treeViewId, searchInputId) {
    var tv = $(treeViewId).data('kendoTreeView');
    $(searchInputId).on('keyup', function () {
        $(treeViewId + ' li.k-item').show();
        $('span.k-in > span.highlight').each(function () {
            $(this).parent().text($(this).parent().text());
        });
        // ignore if no search term
        if ($.trim($(this).val()) === '') {
            return;
        }
        var term = this.value.toUpperCase();
        var tlen = term.length;
        $(treeViewId + ' span.k-in').each(function (index) {
            var text = $(this).text();
            var html = '';
            var q = 0;
            var p;
            while ((p = text.toUpperCase().indexOf(term, q)) >= 0) {
                html += text.substring(q, p) + '<span class="highlight">' + text.substr(p, tlen) + '</span>';
                q = p + tlen;
            }
            if (q > 0) {
                html += text.substring(q);
                $(this).html(html);
                $(this).parentsUntil('.k-treeview').filter('.k-item').each(function (index, element) {
                    //tv.expand($(this));
                    $(this).data('SearchTerm', term);
                });
            }
        });
        $(treeViewId + ' li.k-item:not(:has(".highlight"))').hide();
    });
  }

  function escapeHtml(string) {
    // Perhaps there is another way to do this, but need to escape the queries
	  var entityMap = {
	    "&": "&amp;",
	    "<": "&lt;",
	    ">": "&gt;",
	    '"': '&quot;',
	    "'": '&#39;',
	    "/": '&#x2F;',
	    " ": '&nbsp;',
	    "\n": '<br />'
	  };

    return String(string).replace(/[&<>"'\/\s\n]/g, function (s) {
      return entityMap[s];
    });
  }

	// Create a map of visualization types and function to return those that need to be disabled based on how many numeric inputs we have
	var vizTypeMap = {
		area: 1,
		column: 1,
		line: 1,
		radarArea: 1,
		radarColumn: 1,
		rararLine: 1,
		verticalArea: 1,
		verticalLine: 1,
		bar: 2,
		bubble: 3,
		polarArea: 2,
		polarLine: 2,
		polarScatter: 2,
		scatter: 2,
		scatterLine: 2
	};

	var vizCharts = [
		{ text: "Area"         , value: "area" },
		{ text: "Bar"          , value: "bar" },
		{ text: "Bubble"       , value: "bubble" },
		{ text: "Column"       , value: "column" },
		{ text: "Line"         , value: "line" },
		{ text: "Polar-Area"   , value: "polarArea" },
		{ text: "Polar-Line"   , value: "polarLine" },
		{ text: "Polar-Scatter", value: "polarScatter" },
		{ text: "Radar-Area"   , value: "radarArea" },
		{ text: "Radar-Column" , value: "radarColumn" },
		{ text: "Radar-Line"   , value: "radarLine" },
		{ text: "Scatter"      , value: "scatter" },
		{ text: "Scatter-Line" , value: "scatterLine" },
		{ text: "Vertical-Area", value: "verticalArea" },
		{ text: "Vertical-Line", value: "verticalLine" }
	];

	function disableChartTypes(numNumeric) {
		// Iterate over all visualization types and disable those for which there are not enough numeric values
		var currentVizCharts = [];

		$.each(vizCharts, function(index,object) {
			if (numNumeric >= vizTypeMap[object.value]) {
				currentVizCharts.push(object);
			}
		});
		var vizChartTypeDS = new kendo.data.DataSource({
			data: currentVizCharts
		});

		vizChartType.setDataSource(vizChartTypeDS);
	}

  // Function to retrieve related nodes
  function retrieveAssociates(cy,node,nodeType,eleid) {
    var sparql = '';

    if(nodeType == 'URI') {
	    sparql = "CONSTRUCT { <" + node + "> ?p ?o . ?s ?p <" + node + "> . } WHERE { { ?s ?p <" + node + "> .} UNION { <" + node + "> ?p ?o . } } LIMIT "+$('#limitAssociates').val();
    }
    else if(nodeType == 'BNODE') {
      sparql = "CONSTRUCT { " + node + " ?p ?o . } WHERE { " + node + " ?p ?o . } LIMIT "+$('#limitAssociates').val();
    }
    else {
    	sparql = "CONSTRUCT { ?s ?p \"" + node + "\" . } WHERE { ?s ?p \"" + node + "\" . } LIMIT "+$('#limitAssociates').val();
    }

    $.post("sparqlConstruct", { database: $("#DB_label").html(),'query': sparql }, function(data) {
      // Need to make sure we actually got some results
      if (data.elements.nodes.length == 0) {
        popup.show("No connected nodes","error");
        return true;
      }
      else {
      	$.each(data.elements.nodes,function(index,obj) {
      		if(typeof cy.$('#'+obj.data.id).id() === 'undefined') {
      			cy.add(obj);
      		}
      	});
      	$.each(data.elements.edges,function(index,obj) {
      		if(typeof cy.$('#'+obj.data.id).id() === 'undefined') {
      			cy.add(obj);
      		}
      		else {
      		  console.log(obj);
      		}
      	});


    		// Calculate centralities if selected
		    var calculateCentrality = $('input[name=calculateCentrality]:checked').val();

		    if(calculateCentrality == 'true') {
		    	popup.show('Calculating normalized degree centrality',"info");
			    var dcn = cy.$().degreeCentralityNormalized();

			    popup.show('Calculating normalized closeness centrality',"info");
			    var ccn = cy.$().closenessCentralityNormalized({directed: true});

			    popup.show('Calculating normalized betweenness centrality',"info");
			    var bcn = cy.$().betweennessCentrality({directed: true});
		    }

    		cy.nodes().each(function(index,node) {
		    	var json = node.json();

		    	node.data('degree',node.degree());
		    	// If user selected to calculate centrality
		    	if(calculateCentrality == 'true') {
		    		node.data('inDegree',node.indegree());
		    		node.data('outDegree',node.outdegree());
		    		node.data('degreeCentrality',dcn.degree('#'+node.id()));
		    		node.data('closenessCentrality',ccn.closeness('#'+node.id()));
		    		node.data('betweennessCentrality',bcn.betweenness('#'+node.id()));
		    	}
	    	});

        popup.show("Returned " + data.elements.nodes.length + " nodes and " + data.elements.edges.length + " edges.");

        var layoutS = {};
        layoutS = getLayoutSettings(layoutSelector.value());
        cy.layout(layoutS);
      }
    }).fail(function(xhr) {
      popup.show("Error, no results (" + xhr.status + " " + xhr.statusText + ")","error");
    });
  }

  // Function to retrieve layout settings
  function getLayoutSettings(id) {
  	var ls = {};

  	$('#'+id+'LayoutTable [data-layoutsetting]').each(function(index,item) {
  		if($(this).attr('type') == 'radio' && !$(this).is(':checked')) {
  			return true;
  		}
  		else if($(this).attr('data-layoutsetting') == 'nodeMass') {
  			ls.nodeMass = function(node) {
  				var zero = cy.$('#'+node.id).data($('#arbornodeMass').val());
  				if(zero == 0) {
  					zero = 1;
  				}
  				return zero;
  		  };
  		}
  		else if($(this).val() == 'true' || $(this).val() == 'false') {
  			ls[$(this).attr('data-layoutsetting')] = $(this).val() == 'true';
  		}
  		else if($.isNumeric($(this).val())) {
  			ls[$(this).attr('data-layoutsetting')] = Number($(this).val());
  		}
  		else {
  			ls[$(this).attr('data-layoutsetting')] = $(this).val();
  		}
  	});
  	ls['name']=id;
  	ls['padding'] = 10;
  	// ls['stop'] = function() { $("#spinnerWrapper").fadeOut(800); };
		return ls;
  }

  function drawGraph(data) {
    $("#viz_main").empty();

    // Show the graph search panel
    $("#graphSearch").fadeIn(1400);

    if($("#layoutSelector").data('kendoComboBox').value() == 'jgraph') {
      drawJgraph(data);
    }
    else {
      drawCytoscape(data);
    }

    popup.show("Returned " + data.nodes.length + " nodes and " + data.edges.length + " edges.");
  }

  function drawCytoscape(data) {
    var testNumeric = {};
    testNumeric.fields = {};
    testNumeric.isDecimal = {};
    testNumeric.maxValues = {};
    testNumeric.minValues = {};
    var finalNumericArray = {};
    finalNumericArray.numeric = [];
    finalNumericArray.string = [];

    var cy = window.cy = cytoscape({
      container: document.getElementById('viz_main'),
      elements: data,
      pixelRatio: 'auto',
      boxSelectionEnabled: ($('input:radio[name=boxSelectionEnabled]:checked').val() === 'true'),
      hideEdgesOnViewport: ($('input:radio[name=hideEdgesOnViewport]:checked').val() === 'true'),
      hideLabelsOnViewport: ($('input:radio[name=hideLabelsOnViewport]:checked').val() === 'true'),
      textureOnViewport: ($('input:radio[name=textureOnViewport]:checked').val() === 'true'),
      motionBlur: ($('input:radio[name=motionBlur]:checked').val() === 'true'),
      selectionType: $("#selectionType").val(),
      wheelSensitivity: $('#wheelSensitivityBox').val()
    });

    cy.ready(function() {
      // Add the pan/zoom widget
      cy.panzoom({
        zoomFactor: 0.05, // zoom factor per zoom tick
        zoomDelay: 45, // how many ms between zoom ticks
        minZoom: 0.1, // min zoom level
        maxZoom: 10, // max zoom level
        fitPadding: 50, // padding when fitting
        panSpeed: 10, // how many ms in between pan ticks
        panDistance: 10, // max pan distance per tick
        panDragAreaSize: 75, // the length of the pan drag box in which the vector for panning is calculated (bigger = finer control of pan speed and direction)
        panMinPercentSpeed: 0.25, // the slowest speed we can pan by (as a percent of panSpeed)
        panInactiveArea: 8, // radius of inactive area in pan drag box
        panIndicatorMinOpacity: 0.5, // min opacity of pan indicator (the draggable nib); scales from this to 1.0
        zoomOnly: false, // a minimal version of the ui only with zooming (useful on systems with bad mousewheel resolution)

        // icon class names
        sliderHandleIcon: 'fa fa-minus',
        zoomInIcon: 'fa fa-plus',
        zoomOutIcon: 'fa fa-minus',
        resetIcon: 'fa fa-expand'
      });

      cy.style().fromJson([
        {
          selector: 'edge',
          style: {
            'width': 1,
            'line-color': $("#line-color").val(),
            'line-style': $("#line-style").val(),
            'target-arrow-color': $("#target-arrow-color").val(),
            'target-arrow-shape': $("#target-arrow-shape").val(),
            'target-arrow-fill': $("#target-arrow-fill").val(),
            'label': 'data(label)','min-zoomed-font-size': function() { if($('input[name=\'showLabelOnHoverOnly\']:checked').val() == 'true') { return 100; } else { return $("#min-zoomed-font-size").val(); } },
            'font-size': ($("#font-size").val() - 4),
            'text-wrap': 'wrap',
            'text-max-width': '20px',
            'edge-test-rotation': 'autorotate'
          }
        },
        {
          selector: 'node',
          style: {
            content:"data(label)",
            shape: $("#shape").val(),
            'background-color': $("#background-color").val(),
            'min-zoomed-font-size': function() { if($('input[name=\'showLabelOnHoverOnly\']:checked').val() == 'true') { return 100; } else { return $("#min-zoomed-font-size").val(); } },
            'font-size': $("#font-size").val(),
            'text-wrap': 'wrap',
            'text-max-width': '20px',
            'transition-property': 'border-width,border-color,background-color',
            'transition-duration': '200ms'
          }
        },
        {
          selector: '.highlight_connected_nodes',
          style: {
            'line-color': $("#graphSearchColorPicker").val(),
            'background-color': $("#graphSearchColorPicker").val(),
            'target-arrow-color': $("#graphSearchColorPicker").val(),
            'border-color': $("#graphSearchColorPicker").val(),
            'transition-property': 'border-width,border-color,background-color',
            'transition-duration': '400ms'
          }
        },
        {
          selector: '.flash_glow',
          style: {
            'border-width':6,
            'border-color': $("#graphSearchColorPicker").val(),
            'transition-property': 'border-width,border-color,background-color',
            'transition-duration': '400ms'
          }
        },
        {
          selector: '.selected_outline',
          style: {
            'border-width':3,
            'border-color': 'black',
            'background-color': 'black',
            'opacity': 0.567,
            'line-color': 'black',
            'target-arrow-color': 'black',
            'transition-property': 'border-width,border-color,background-color,line-color,target-arrow-color,opacity',
            'transition-duration': '400ms'
          }
        },
        {
          selector: '.faded_nodes',
          style: {
            'opacity': 0.1
          }
        },
        {
          selector: 'edge.bezier',
          style: {
            'curve-style': 'bezier',
            'control-point-step-size': 40
          }
        },
        {
          selector: 'edge.unbundled-bezier',
          style: {
            'curve-style': 'unbundled-bezier',
            'control-point-distances': 120,
            'control-point-weights': 0.1
          }
        },
        {
          selector: 'edge.multi-unbundled-bezier',
          style: {
            'curve-style': 'unbundled-bezier',
            'control-point-distances': '40 -40',
            'control-point-weights': '0.25 0.75'
          }
        },
        {
          selector: 'edge.haystack',
          style: {
            'curve-style': 'haystack',
            'haystack-radius': 0.5
          }
        },
        {
          selector: 'edge.segments',
          style: {
            'curve-style': 'segments',
            'segment-distances': '40 -40',
            'segment-weights': '0.25 0.75'
          }
        }
      ]).update();

      // While we are at it, set edges to the selected edge type
      cy.edges().addClass($('#curve-style').val());

      // Calculate centralities if selected
      // TODO: Want to paralelize this chunk using webworkers
      var calculateCentrality = $('input[name=calculateCentrality]:checked').val();

      if(calculateCentrality == 'true') {
        popup.show('Calculating normalized degree centrality',"info");
        var dcn = cy.$().degreeCentralityNormalized();

        popup.show('Calculating normalized closeness centrality',"info");
        var ccn = cy.$().closenessCentralityNormalized({directed: true});

        popup.show('Calculating normalized betweenness centrality',"info");
        var bcn = cy.$().betweennessCentrality({directed: true});
      }

      // Need to figure out which node properties are numeric and also calculate a few other metrics while we are at it
      cy.nodes().each(function(index,element) {
        // If user selected to calculate centrality
        cy.$('#'+element.id()).data('degree',element.degree());
        if(calculateCentrality == 'true') {
          cy.$('#'+element.id()).data('inDegree',element.indegree());
          cy.$('#'+element.id()).data('outDegree',element.outdegree());
          cy.$('#'+element.id()).data('degreeCentrality',dcn.degree('#'+element.id()));
          cy.$('#'+element.id()).data('closenessCentrality',ccn.closeness('#'+element.id()));
          cy.$('#'+element.id()).data('betweennessCentrality',bcn.betweenness('#'+element.id()));
        }

        $.each(element.json().data,function(k,v) {
          // Test if the field is numeric
          var isNum = $.isNumeric(v);

          if(testNumeric.fields[k] == true  || !testNumeric.fields.hasOwnProperty(k)) {
            testNumeric.fields[k] = isNum;
          }

          // Now determine if it is an integer or decimal
          if(isNum == true) {
            var id = parseInt(v) !== v;
            if(!testNumeric.isDecimal.hasOwnProperty(k)) {
              if(id == true) {
                testNumeric.isDecimal[k] = true;
              }
              else {
                testNumeric.isDecimal[k] = false;
              }
            }
            else if(testNumeric.isDecimal[k] == false) {
              if(id == true) {
                testNumeric.isDecimal[k] = true;
              }
            }
          }
        });
      });

      // Find min and max node degree to use for node sizing
      var min = cy.nodes().minDegree();
      var max = cy.nodes().maxDegree();

      // Some functions really don't like the min and max values to be the same...they can malfunction in a very non-obvious way
      if(min == max) {
        max += 1;
      }

      cy.style().selector('node').style({
        width:  "mapData(degree,"+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")",
        height: "mapData(degree,"+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")"
      }).update();

      // Add min and max values for all numeric properties
      $.each(testNumeric.fields, function(k,v) {
        if(testNumeric.fields[k] == true) {
          var maxval = cy.nodes().max(function(ele,i){
            return ele.data(k);
          });
          var minval = cy.nodes().min(function(ele,i){
            return ele.data(k);
          });
          testNumeric.maxValues[k] = maxval.value;
          testNumeric.minValues[k] = minval.value;
        }
      });

      // populate the nodeMass and hiveplot(if numeric filter type is currently selected) property combobox for Arbor
      $.each(testNumeric.fields,function(kk,vv) {
        if(vv == true) {
          finalNumericArray.numeric.push({ text: kk, value: kk });
        }
        else {
          finalNumericArray.string.push({ text: kk, value: kk });
        }
      });

      var testNumericDatasource = new kendo.data.DataSource({
        data: finalNumericArray.numeric
      });

      var allFieldsArray = finalNumericArray.numeric.concat(finalNumericArray.string);
      var allFieldsDatasource = new kendo.data.DataSource({
        data: allFieldsArray
      });

      arbornodeMass.setDataSource(testNumericDatasource);
      arbornodeMass.select(0);

      // $('#hiveplotaxisSort').data('kendoComboBox').setDataSource(testNumericDatasource);
      // $('#hiveplotaxisSort').data('kendoComboBox').select(0);
      //
      // if ($('#hiveplotaxisFilterType').val() === 'numeric') {
      //   $('#hiveplotaxisProperty').data('kendoComboBox').setDataSource(testNumericDatasource);
      //   $('#hiveplotaxisProperty').data('kendoComboBox').select(0);
      // }
      // else {
      //   $('#hiveplotaxisProperty').data('kendoComboBox').setDataSource(allFieldsDatasource);
      //   $('#hiveplotaxisProperty').data('kendoComboBox').select(0);
      // }
      //
      //
      // // Change event handler for the type of axis for hiveplot layouts
      // $('#hiveplotaxisFilterType').data('kendoComboBox').bind('change',function(event) {
      //   if ($('#hiveplotaxisFilterType').val() === 'numeric') {
      //     $('#hiveplotaxisProperty').data('kendoComboBox').setDataSource(testNumericDatasource);
      //   }
      //   else {
      //     $('#hiveplotaxisProperty').data('kendoComboBox').setDataSource(allFieldsDatasource);
      //   }
      // });

      // Now that we have the arbor numeric fields, draw the graph
      var layoutSettings = {};
      layoutSettings = getLayoutSettings(layoutSelector.value());
      cy.layout(layoutSettings);
    });

    // Bind change event for layout algorithm picker
    $('#layoutSubmit').on("click", function() {
      if(layoutSelector.value() == 'jgraph') {
        drawJgraph(data);
      }
      else {
        var Ls = {};
        Ls = getLayoutSettings(layoutSelector.value());
        cy.layout(Ls);
        cy.fit(cy.$());
        cy.center();
      }
    });

    // bind a change event to update the highlight color class
    $("#graphSearchColorPicker").on('change', function() {
      cy.style().selector('.highlight_connected_nodes').style({
        'line-color': $("#graphSearchColorPicker").val(),
        'background-color': $("#graphSearchColorPicker").val(),
        'target-arrow-color': $("#graphSearchColorPicker").val()
      });
    });

    // Bind change event for graph settings input only
    $("#graphSettings :input").on('change',function(event) {
      var k,v;

      // First, retrieve the changed setting and value
      if($(this).attr('type') == 'radio') {
        k = $(this).attr('name');
        v = ($('input[name=\''+$(this).attr('name')+'\']:checked').val() === 'true');
      }
      else if($(this).attr('data-cysetting') !== undefined) {
        k = $(this).attr('data-cysetting');
        v = $(this).val();
      }
      else {
        k = $(this).attr('id');
        v = $(this).val();
      }

      // Then, alter the setting based on the type of setting
      if($(this).hasClass('cyOption')) {
        cy._private[k] = v;
      }
      else if($(this).hasClass('cyEdgeType')) {
        var edgeType = $('#curve-style').val();

        cy.edges().removeClass('bezier unbundled-bezier multi-unbundled-bezier haystack segments').addClass(edgeType);
      }
      else if($(this).hasClass('cyNodeStyle')) {
        if($(this).attr('id') == 'min-zoomed-font-size') {
          cy.style().selector('node').style('min-zoomed-font-size',$('#min-zoomed-font-size').val()).update();
        }
        else if($(this).attr('name') == 'showLabelOnHoverOnly') {
          if($('input[name=\'showLabelOnHoverOnly\']:checked').val() == 'true') {
            cy.style().selector('node').style('min-zoomed-font-size',100).update();
          }
          else {
            cy.style().selector('node').style('min-zoomed-font-size',$('#min-zoomed-font-size').val()).update();
          }
        }
        else {
          cy.style().selector('node').style(k,v).update();
        }
      }
      else if($(this).hasClass('cyEdgeStyle')) {
        cy.style().selector('edge').style(k,v).update();
      }
      else if($(this).hasClass('nodeSize')) {
        var min = cy.nodes().minDegree();
        var max = cy.nodes().maxDegree();
        // For now, in case we have a min and max that are the same...we need a better fix later
        if(min == max) {
          max += 1;
        }
        cy.style().selector('node').style({
          'width': "mapData(degree,"+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")",
          'height': "mapData(degree,"+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")"
        }).update();
      }
    });

    // context menus
    cy.cxtmenu({
      selector: 'node',
      commands: [
        {
          content: 'Retrieve connected nodes',
          select: function(ele){
            retrieveAssociates(cy,ele.data('label'),ele.data('nodeType'),ele.id());
          }
        },
        {
          content: 'Reset zoom',
          select: function(ele) {
            cy.fit(cy.$());
          }
        },
        {
          content: 'Alter node/edge properties',
          select: function(ele) {
            alterNodes(cy,testNumeric,finalNumericArray);
          }
        }
      ]
    });

    cy.cxtmenu({
      selector: 'core',
      commands: [
        {
          content: 'Reset zoom',
          select: function(ele) {
            cy.fit(cy.$());
          }
        },
        {
          content: 'Alter node/edge properties',
          select: function(ele) {
            alterNodes(cy,testNumeric,finalNumericArray);
          }
        }
      ]
    });

    // highlight selected nodes/edges when box-selection is used/enabled
    cy.on('tapdrag tap', function(event) {
      cy.batch(function() {
        cy.$(':selected').addClass('selected_outline');
        cy.elements().not(cy.$(':selected')).removeClass('selected_outline');
      });
    });



    // highlight connected nodes on hover and show tooltip
    cy.on('mouseover','node', function(event) {
      var node = event.cyTarget;
      var neighborhood = cy.$('#'+node.id()).closedNeighborhood();
      neighborhood.flashClass('flash_glow',500).addClass('highlight_connected_nodes');
      cy.elements().not(neighborhood).addClass('faded_nodes');

      // Create the html table containing the node data
      $("#graphTooltip").empty();

      var html = '<table>';

      var sortedArray = [];
      $.each(node.data(), function(key,value) {
        if(key != 'id' && key != 'label' && key != 'nodeType') {
          sortedArray.push(key);
        }
      });

      html = html + '<tr><td>label</td><td>' + node.data('label') + '</td></tr>';
      html = html + '<tr><td>nodeType</td><td>' + node.data('nodeType') + '</td></tr>';

      sortedArray.sort();
      $.each(sortedArray,function(index) {
        html = html + '<tr><td>' + sortedArray[index] + '</td><td>' + node.data(sortedArray[index]) + '</td></tr>';
      });

      html = html + '</table>';
      $("#graphTooltip").html(html);

      // A little collision/off-screen detection
      var vdL = $("#viz").offset().left;
      var vdT = $("#viz").offset().top;
      var vdR = vdL + $("#viz_main").width();
      var vdB = vdT + $("#viz_main").height();
      var ttL = event.originalEvent.clientX + 5;
      var ttT = event.originalEvent.clientY + 5;
      var ttH = $("#graphTooltip").height();
      var ttW = $("#graphTooltip").width();
      var ttR = ttL + ttW;
      var ttB = ttT + ttH;

      if(ttR > vdR) {
        ttL = ttL - ttW - 10;
      }
      if(ttB > vdB) {
        ttT = ttT - ttH - 10;
      }

      // create the style
      var style = {
        display: 'inline',
        position: 'fixed',
        'z-index': '99',
        top: ttT + 'px',
        left: ttL + 'px',
        'border-radius': '3px',
        'background-color': 'rgba(0,0,0,0.7)',
        color: 'white',
        'max-width': '500px'
      };

      $("#graphTooltip").css(style);
    });

    cy.on('mouseout cxttapstart','node', function(event) { // Had to add the cxttapstart so that we can hide the tooltip when the context menu is displayed
      var node = event.cyTarget;
      // Remove the highlight and faded classes
      var neighborhood = cy.$('#'+node.id()).closedNeighborhood();
      neighborhood.removeClass('highlight_connected_nodes');
      cy.elements().not(neighborhood).removeClass('faded_nodes');

      // Now, hide the tooltip
      $("#graphTooltip").html('').css('display: none;');
    });

    // show the results tab/button
    $("#nav-trigger-results").fadeIn(1400);

    // Need to unregister previous click handler from SELECT queries
    $("#nav-trigger-results").off('click');
    $("#nav-trigger-results").on('click', function() {
      generateResults(cy);
    });

    // show the histogram tab/button
    $("#nav-trigger-graphStatistics").fadeIn(1400);
    $("#nav-trigger-graphStatistics").on('click', function() {
      generateHistograms(cy,testNumeric);
    });


    // search the graph
    $("#graphSearchTextBox").on('keyup focusin focusout', function(e) {
      var searchTerm = $(this).val().toLowerCase();

      // only start searching if we have 3 or more characters
      if (searchTerm.length >= 3) {
        // TODO: It would be nice to have the search run across all fields, not just the label
        // iterate over all nodes to find matches
        cy.nodes().each(function(idx,ele) {
          var label = ele.data('label');
          if (label.indexOf(searchTerm) >= 0) {
            ele.addClass('highlight_connected_nodes');

          }
        });
      }
      else {
        cy.nodes().removeClass('highlight_connected_nodes');
      }
    });
    kendo.ui.progress($('#query_progress'),false);
  }

  // Functions to change node/edge style (size, shape, and color for now)
  function alterNodes(cy,testNumeric,finalNumericArray) {
    // Hide the elements that should not yet be visible
  	$('#changeNodeSizeNumboxTr').hide();
    $('#CNCStringTr').hide();
    $('#CNCNumericTr').hide();
    $('#CNSStringTr').hide();

  	// Populate the kendo UI widgets
  	$('#changeNodeSizeCombobox').data('kendoComboBox').setDataSource(new kendo.data.DataSource({data: finalNumericArray.numeric}));
  	$('#CNCpropertyCombobox').data('kendoComboBox').setDataSource(new kendo.data.DataSource({data: finalNumericArray.numeric}));
  	$('#CNCstringPropertyCombobox').data('kendoComboBox').setDataSource(new kendo.data.DataSource({data: finalNumericArray.string}));
  	$('#CNSstringPropertyCombobox').data('kendoComboBox').setDataSource(new kendo.data.DataSource({data: finalNumericArray.string}));
  	$('#CNIstringPropertyCombobox').data('kendoComboBox').setDataSource(new kendo.data.DataSource({data: finalNumericArray.string}));

  	// Now that we are here, go ahead and read in the list of available image icons
  	imagesDataSource.fetch();

  	// Start with all fields set to the default and "constant" except for node size
  	// Node size
  	$('input[name=nodeSizeChange]').on('change',function(event) {
  		var newSelection = $('input[name=nodeSizeChange]:checked').val();
  		if(newSelection == 'attribute') {
  			$('#changeNodeSizeNumboxTr').hide();
  			$('#changeNodeSizeComboBoxTr').fadeIn(500);
  		}
  		else {
  			$('#changeNodeSizeComboBoxTr').hide();
  			$('#changeNodeSizeNumboxTr').fadeIn(500);
  		}
  	});

  	$('#changeNodeSizeCombobox').data('kendoComboBox').bind('select',function(event) {
  		var newValue = $('#changeNodeSizeCombobox').val();
  		var min = testNumeric.minValues[newValue];
  		var max = testNumeric.maxValues[newValue];

  		// For now, in case we have a min and max that are the same...we need a better fix later
      if(min == max) {
        max += 1;
      }
  		cy.style().selector('node').style({
        'width': "mapData("+newValue+","+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")",
        'height': "mapData("+newValue+","+min+","+max+", "+$("#minNodeSize").val()+", "+$("#maxNodeSize").val()+")"
      }).update();
  	});

  	$('#changeNodeSizeNumbox').on('change',function(event) {
  		cy.style().selector('node').style({
  		  'width': $('#changeNodeSizeNumbox').val(),
  		  'height': $('#changeNodeSizeNumbox').val()
  		}).update();
  	});

	  // Change color
	  $('#CNCnumericSubmit').on('click',function() {
	  	var newValue = $('#CNCpropertyCombobox').val();
  		var min = testNumeric.minValues[newValue];
  		var max = testNumeric.maxValues[newValue];

  		// For now, in case we have a min and max that are the same...we need a better fix later
  		if(min == max) {
  		  max += 1;
  		}

  		// Need to remove the icons if they are there
      cy.nodes().removeClass('.node_icons');

	  	cy.style().selector('node').style('background-color',"mapData("+newValue+","+min+","+max+", "+$("#CNClowNumber").val()+", "+$("#CNChighNumber").val()+")").update();
	  });

	  $('#CNCstringPropertySubmit').on('click',function() {
	  	var colormap = {};
	  	$('.deleteMeCP').each(function() {
	  	  var propLabel = $(this).find('td').eq(0).text();
	  		colormap[propLabel] = $(this).find('input').val();
	  	});

	  	// Need to remove the icons if they are there
      cy.nodes().removeClass('.node_icons');

	  	cy.style().selector('node').style('background-color', function(node) {
	  	  return colormap[node.data($('#CNCstringPropertyCombobox').val())];
	  	}).update();
	  });

	  $('input[name=nodeColorRange]').on('change',function(event) {
	  	var newSelection = $('input[name=nodeColorRange]:checked').val();
	  	if(newSelection == 'numericAttribute') {
	  		$('#CNCStringTr').hide();
	  		$('#CNCColorPickerTr').hide();
	  		$('#CNCNumericTr').fadeIn(500);
	  	}
	  	else if(newSelection == 'stringAttribute') {
	  		$('#CNCColorPickerTr').hide();
	  		$('#CNCNumericTr').hide();
	  		$('#CNCStringTr').fadeIn(500);
	  	}
	  	else {
	  		$('#CNCStringTr').hide();
	  		$('#CNCNumericTr').hide();
	  		$('#CNCColorPickerTr').fadeIn(500);
	  	}
	  });

	  // Shape change
	  $('input[name=nodeShapeChange]').on('change',function(event) {
      var newSelection = $('input[name=nodeShapeChange]:checked').val();
      if(newSelection == 'attribute') {
        $('#CNSShapePickerTr').hide();
        $('#CNSStringTr').fadeIn(500);
      }
      else {
        $('#CNSStringTr').hide();
        $('#CNSShapePickerTr').fadeIn(500);
      }
    });

  	$('#CNSstringPropertySubmit').on('click',function() {
      var shapemap = {};
      $('.deleteMeSP').each(function(index,object) {
        var propLabel = $(this).find('td').eq(0).text();
        shapemap[propLabel] = $('#SP'+index).data('kendoComboBox').value();
      });

      // Need to remove the icons if they are there
      cy.nodes().removeClass('node_icons');

      cy.style().selector('node').style('shape', function(node) {
        return shapemap[node.data($('#CNSstringPropertyCombobox').val())];
      }).update();
    });

  	$('#CNIstringPropertySubmit').on('click',function() {
  	  var iconMap = {};
  	  $('.deleteMeIP').each(function(index,object) {
  	    var propLabel = $(this).find('td').eq(0).text();
  	    iconMap[propLabel] = $('#IP'+index).data('kendoComboBox').value();
  	  });

  	  cy.style().selector('.node_icons').style({
  	    'background-image': function(node) {
  	      return iconMap[node.data($('#CNIstringPropertyCombobox').val())];
  	    },
  	    'background-fit': 'cover',
  	    'background-repeat': 'no-repeat',
  	    'background-clip': 'none',
  	    'background-opacity': 0
  	  }).update();

  	  cy.nodes().addClass('node_icons');
  	});

  	alterNodesWindow.center().open();
  }

  // Function to store queries in localStorage and then update the combobox
  function storeQueryHistory(query) {
    // Maybe not the way to go...but for now, going to keep query history in localStorage
    // If this is the first time, or the user deleted the history
    var qh = [];
    if (localStorage.getItem("queryHistory") !== null) {
      // If there is a history to work with, load it and then modify it
      qh = JSON.parse(localStorage.getItem('queryHistory'));
    }

    // Grab the current timestamp and use it as the name field
    var dts = moment().format('YYYY-MM-DD HH:mm:ss');
    qh.push({ name: dts, query: editor.getValue() });

    var queriesDS = new kendo.data.DataSource({
        data: qh
    });
    queryHistory.setDataSource(queriesDS);
    localStorage.setItem('queryHistory', JSON.stringify(qh));
  }

  // Function to generate results in grid from query
  function generateResults(cy) {
    // Create the popup window
    var gridWindow = $("#resultsPopup").kendoWindow({
        width: "70%",
				height: "60%",
        title: "Query Results",
        actions: [
            "Minimize",
            "Maximize",
            "Close"
        ],
				resize: function() {
					resultsGrid.resize();
				}
    }).data('kendoWindow');

    // Need to convert the graph JSON to an appropriate array of objects
    var dataArray = [];
    cy.edges().forEach(function(edge) {
    	dataArray.push(edge.data());
    });

    gridWindow.center().open();

    // Create the grid
    var configuration = {
      dataSource: {
        data: dataArray,
        schema: {
          model: {
            fields: {
              source_name: { type: "string" },
              label: { type: "string" },
              target_name: { type: "string" }
            }
          }
        },
        pageSize: 25
      },
      height: "100%",
      scrollable: true,
      sortable: true,
      filterable: true,
      reorderable: true,
      resizable: true,
      toolbar: ["excel"],
      excel: {
        allPages: true,
        filterable: true,
        proxyURL: "/saveExcel"
      },
      pageable: {
        input: true,
        numeric: false,
        pageSizes: [10,25,50,100, "all"]
      },
      columns: [
        { field: "source_name", title: "Subject" },
        { field: "label", title: "Predicate" },
        { field: "target_name", title: "Object" }
      ]
    };

    // Create/update/refresh the grid
    resultsGrid.setOptions(configuration);
    resultsGrid.dataSource.page(1);
  }

  // Generate chart for histograms
  function generateHistograms(cy,numericProps) {
    // graphHistogramPopup

    var nodeStats = {};
    // First create arrays for each numeric property populated with an element per value
    console.log(numericProps);
    $.each(numericProps.fields, function(k,v) {
    	if(v == true) {
    		if(!nodeStats.hasOwnProperty(k)) {
	    		nodeStats[k] = [];
	    	}

	    	var incr;
	    	numericProps.isDecimal[k] === true? incr = 0.01 : incr = 1;
	    	var max = numericProps.maxValues[k];

	    	for(index = 0; index <= max; index += incr) {
	    		nodeStats[k].push({name: index.toFixed(2), number: Number(index.toFixed(2)), value: 0});
	    	}
    	}
    });

    // Now count all occurences of each value for the distribution
    cy.nodes().forEach(function(node) {
    	$.each(numericProps.fields, function(k,v) {
    		if(v == true) {
    			var snum = node.data(k);
	    		var num = snum.toFixed(2);

	    		for (var i=0; i < nodeStats[k].length; i++) {
						if (nodeStats[k][i].name == num) nodeStats[k][i].value += 1;
				  }
    		}
    	});
    });

    // Finally, create a chart for each numeric value
    // Clear the popup
    $('#histogramsWrapper').empty();

    // Figure out the step sizes
    var stepSize = setStepSize(nodeStats);

    graphHistogramPopup.center().open();

    // For now, need a hack/workaround to make sure that the popup is fully drawn so that the charts "know" how big to be
    setTimeout(function(){
    	$.each(nodeStats,function(k,v) {
	    	// First, append a div to the popup
	    	$('#histogramsWrapper').append('<div id=\''+k+'Chart\' class=\'graphHistogramCharts\' ></div>');

	    	// Then create the chart
	    	$('#'+k+'Chart').kendoChart({
	    		dataSource: {
	    			data: nodeStats[k]
	    		},
			    theme: "Material",
			    pannable: {
            lock: "y"
          },
          zoomable: {
            mousewheel: {
            	lock: "y"
            },
            selection: {
              lock: "y"
            }
          },
			    tooltip: {
			      visible: true,
			      template: k+" #: category #: #: value #"
			    },
			    title: {
			      align: "left",
			      text: k+" distribution",
			      color: "black"
			    },
			    legend: {
			      visible: false
			    },
			    seriesDefaults: {
			      type: "column",
			      background: "transparent"
			    },
			    series: [{
			      field: "value",
			      gap: 0
			    }],
			    valueAxis: {
			      field: "value",
			      majorGridLines: {
			          visible: false
			      }
			    },
			    categoryAxis: {
	          field: "number",
	          majorGridLines: {
	            visible: false
	          },
	          labels: {
	            step: stepSize[k]
	          },
	          majorTicks: {
	            step: stepSize[k]
	          }
	        }
			  });

	    });
    },500);
  }

  // Function to set the stepsize such that no more than 20 number labels will show...for aesthetic purposes
  function setStepSize(data) {
    var stepSize = {};
    var multiple = 15;

    $.each(data,function(k,v) {
    	if(data[k].length <= 50) {
    		stepSize[k] = 1;
    	}
    	else {
    		stepSize[k] = Math.round(data[k].length / multiple);
    	}
    });

    return stepSize;
  }

  // Function to return a date string for query execution time elapsed
  function timeElapsed(executionTime) {
    var now = Date.now();
    var elapsed = now - executionTime;
    var time = {
      years : Math.round(moment.duration(elapsed, 'milliseconds').years()),
      months : Math.round(moment.duration(elapsed, 'milliseconds').months()),
      days : Math.round(moment.duration(elapsed, 'milliseconds').days()),
      hours : Math.round(moment.duration(elapsed, 'milliseconds').hours()),
      minutes : Math.round(moment.duration(elapsed, 'milliseconds').minutes()),
      seconds : Math.round(moment.duration(elapsed, 'milliseconds').seconds())
    };

    time.years = (time.years < 10) ? ("0" + time.years) : time.years;
    time.months = (time.months < 10) ? ("0" + time.months) : time.months;
    time.days = (time.days < 10) ? ("0" + time.days) : time.days;
    time.hours = (time.hours < 10) ? ("0" + time.hours) : time.hours;
    time.minutes = (time.minutes < 10) ? ("0" + time.minutes) : time.minutes;
    time.seconds = (time.seconds < 10) ? ("0" + time.seconds) : time.seconds;

    if(time.years   > 0){   return time.years   + ' years '     + time.months   + ' months remaining';}
    if(time.months  > 0){   return time.months  + ' months '    + time.days     + ' days remaining';}
    if(time.days    > 0){   return time.days    + ' days '      + time.hours    + ' hours remaining';}
    if(time.hours   > 0){   return time.hours   + ':'     + time.minutes  + ':' + time.seconds;}
    if(time.minutes > 0){   return '00:' + time.minutes + ':'   + time.seconds;}
    if(time.seconds > 0){   return '00:00:' + time.seconds;}
    return "";
  }

  function sortUnique(arr) {
	  arr.sort();
	  var last_i;
	  for (var i=0;i<arr.length;i++)
	      if ((last_i = arr.lastIndexOf(arr[i])) !== i)
	          arr.splice(i+1, last_i-i);
	  return arr;
	}

  function websocketConnect () {
    var filesystem_changes_ws = new WebSocket('wss://'+location.host+'/filesystem_changes');
    filesystem_changes_ws.onopen = function() {
      popup.show('filesystem_changes websocket opened.','info');
    };
    filesystem_changes_ws.onclose = function() {
      popup.show('filesystem_changes websocket closed.','info');
      websocketReconnect.center().open();
      $("#websocketReconnectButtonYes").on('click', function() {
        websocketConnect();
        websocketReconnect.close();
      });
      $("#websocketReconnectButtonNo").on('click', function() {
        websocketReconnect.close();
      });
    };

    filesystem_changes_ws.onmessage = function(msg) {
      if(msg.data == 'nt file changes') {
        filebrowserDS.read();
      }
      else if(msg.data == 'database changes') {
        databasebrowserDS.read();
      }
    };

    var squeue_ws = new WebSocket('wss://'+location.host+'/squeue_ws');
    squeue_ws.onopen = function() {
      popup.show('Squeue websocket opened.','info');
    };
    squeue_ws.onclose = function() {
      popup.show('Squeue websocket closed.','info');
      websocketReconnect.center().open();
      $("#websocketReconnectButtonYes").on('click', function() {
        websocketConnect();
        websocketReconnect.close();
      });
      $("#websocketReconnectButtonNo").on('click', function() {
        websocketReconnect.close();
      });
    };

    squeue_ws.onmessage = function(msg) {
      var res = JSON.parse(msg.data);
      if(res.length >= 1) {
        $('#current_queue > tbody').html('');
        $.each(res,function(i,v) {
          var htmlInsert = '<tr><td>'+v.JOBID+'</td><td>'+v.USER+'</td><td>'+v.STATE+'</td><td>'+v.TIME+'</td><td>'+v.NODES+'</td></tr>';
          $('#current_queue > tbody').append(htmlInsert);

          if(localStorage.getItem('current_pid') !== null &&
             localStorage.getItem('current_pid') == v.JOBID) {
            $('#db_status').text('RUNNING');
            $('#startDB').prop('value','Stop');
            $('#db_name').html(localStorage.getItem('current_database'));
            $('#db_port').html(localStorage.getItem('current_port'));
          }
        });
      }
    };
  }

  // Adding a function to our treeview to retrieve checked nodes
  // Thanks to great docs and support from Kendo UI:
  // http://www.telerik.com/blogs/how-to-get-the-checked-items-from-a-treeview-with-checkboxes
  kendo.ui.TreeView.prototype.getCheckedItems = (function(){
    function getCheckedItems(){
      var nodes = this.dataSource.view();
      return getCheckedNodes(nodes);
    }
    function getCheckedNodes(nodes){
      var node, childCheckedNodes;
      var checkedNodes = [];
      for (var i = 0; i < nodes.length; i++) {
        node = nodes[i];
        if (node.checked) {
          checkedNodes.push(node);
        }
        if (node.hasChildren) {
          childCheckedNodes = getCheckedNodes(node.children.view());
          if (childCheckedNodes.length > 0){
            checkedNodes = checkedNodes.concat(childCheckedNodes);
          }
        }
      }
      return checkedNodes;
    }
    return getCheckedItems;
  })();

  // Also extend treeview to support a check/uncheck all function
  kendo.ui.TreeView.prototype.checkAll = (function(){
    function checkAll() {
      $(this+' .k-checkbox input').prop('checked',true).trigger('change');
    }
  })();

  kendo.ui.TreeView.prototype.uncheckAll = (function(){
    function uncheckAll() {
      $(this+' .k-checkbox input').prop('checked',false).trigger('change');
    }
  })();
});
