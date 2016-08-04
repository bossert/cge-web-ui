;(function(){
  'use strict';
  
  var register = function( cytoscape ){
    var defaults = {
      refreshInterval:       16,
      refreshIterations:     10,
      radius:                25,                              // radius of inner circle from which each axis originates
      hiveplotType:          'single',                        // One of 'single' or 'panel'; if panel is selected, then one hive plot will be created for each distinct predicate value
      numberOfAxes:          3,                               // Number of axes to use, minimum of three with no theoretical maximum
      axisFilterType:        'numeric',                       // Valid values are numeric or string.  For numeric values, use the axisFilters array (one per axis) to provide filters
      axisProperty:          'degree',                        // A single property used to decide which axis each node is placed on
      axisNumericFilter:     [{ operator: 'le', value: 1 },   // for string filterType, axisFilters is ignored and nodes are placed on exactly one axis based on the supplied property
                              { operator: 'le', value: 2 },
                              { operator: 'ge', value: 3 }],
      axisSort:              'degree',                        // default numeric property on which to sort nodes on each axis
      axisSortDirection:     'asc',                           // default axis sort order; one of asc or desc
      hivePanelEdgeProperty: 'label',                         // The edge property used for hive panel separation
      startAngle:            0,
      fit:                   true
    };
    
    var extend = Object.assign || function( tgt ){
      for( var i = 1; i < arguments.length; i++ ){
        var obj = arguments[i];
        
        for( var k in obj ){ tgt[k] = obj[k]; }
      }
      return tgt;
    };
    
    function hiveplotLayout( options ){
      var opts = this.options = {};
      for( var i in defaults ){ opts[i] = defaults[i]; }
      for( var i in options ){ opts[i] = options[i]; }
    }
    
    hiveplotLayout.prototype.run = function(){
      var layout = this;
      var options = this.options;
      var cy = options.cy;
      //var eles = options.eles;
      //var nodes = eles.nodes();
      //var edges = eles.edges();
      
      if (options.hiveplotType === 'single') {
        layout.trigger({type: 'layoutstart', layout: layout});
        
        var centerX = cy.width() / 2;
        var centerY = cy.height() / 2;
        var positions = hivePlot(centerX,centerY,cy.nodes(),options.startAngle);
        
        layout.trigger({type: 'layoutready', layout: layout});
        cy.nodes().layoutPositions(this,options,function(index,element) {
          return positions[element.id()].position;
        });
        
      }
      else if (options.hiveplotType === 'panel') {
        layout.trigger({type: 'layoutstart', layout: layout});
        var distinctPreds = distinctPredicates(cy.edges(),options.hivePanelEdgeProperty);
        
        // Get the center points X Y for each predicate
        var centerPoints = getGrid(distinctPreds.length);
        
        // Clone the nodes that need to be duplicated
        var newElements = cloneNodes(cy,distinctPreds);
        cy.add(newElements);
        // Since we are doing a panel, we need to first iterate over the distinct predicates, then the individual axes
        var nodePositions = {};
        
        for(var pred = 0; pred < distinctPreds.length; pred++) {
          var predicate = distinctPreds[pred];
          
          var snodes = cy.nodes().filter(function(index,element) {
            var connectedEdges = element.connectedEdges();
            for(var c = 0; c < connectedEdges.length; c++) {
              if (connectedEdges.data('label') == predicate) {
                return true;
              }
            }
            return false;
          });
          
          
          
          var positionsToMerge = hivePlot(centerPoints[pred].x,centerPoints[pred].y,snodes,options.startAngle);
          
          $.each(positionsToMerge, function(key,val) {
            nodePositions[key] = val;
          });
        }
        
        layout.trigger({type: 'layoutready', layout: layout});
        cy.nodes().layoutPositions(this,options,function(index,element) {
          if (nodePositions[element.id()]) {
            return nodePositions[element.id()].position;
          }
          else {
            return { x: 100, y: 100 };
          }
        });
      }
      
      // Need a quick function to get distinct predicates from the edges.  Caveat: unless we define some other criteria, edges must have a field that can be used for this purpose...maybe a label would be great...
      function distinctPredicates (edgeArray,predicateField) {
        var distinct = {};
        var distinctA = [];
        for (var i = 0; i < edgeArray.length; i++) {
          var edge = edgeArray[i];
          distinct[edge.data(predicateField)] = 1;
        }
        distinctA = Object.keys(distinct);
        return distinctA;
      }
      
      // Need to clone nodes with degree higher than 1 so that they can be in each individual hiveplot in a panel
      function cloneNodes(graph,predicates) {
        var elementsToAdd = [];
        var edges = graph.edges();
        
        for (var n = 0; n < edges.length; n++) {
          var s = graph.$('#'+edges[n].data('source'));
          var e = graph.$('#'+edges[n].data('id'));
          var t = graph.$('#'+edges[n].data('target'));
          var sj = s.json();
          var ej = e.json();
          var tj = t.json();
          
          s.addClass('hiveHide');
          e.addClass('hiveHide');
          t.addClass('hiveHide');
          sj.classes = 'hiveAdd';
          ej.classes = 'hiveAdd';
          tj.classes = 'hiveAdd';
          
          sj.data.id = sj.data.id+predicates.indexOf(ej.data[options.hivePanelEdgeProperty]);
          tj.data.id = tj.data.id+predicates.indexOf(ej.data[options.hivePanelEdgeProperty]);
          ej.data.id = ej.data.id+n;
          ej.data.source = sj.data.id;
          ej.data.target = tj.data.id;
          
          elementsToAdd.push(sj);
          elementsToAdd.push(ej);
          elementsToAdd.push(tj);
        }
        
        graph.$('.hiveHide').remove();
        return elementsToAdd;
      }
      
      // A function to layout each node based on a starting point X Y
      function hivePlot(cX,cY,sgraph,startAngle) {
        // Set the starting angle for the axes of the hive plot
        var angle = 0;
        // Set the radius around the center point from which the axes will emanate
        var radius = options.radius;
        // Calculate the spacing between axes
        var spacing = 360 / options.numberOfAxes;
        
        var mappings = {};
        
        for (var i = 0; i < options.numberOfAxes; i++) {
          // First, filter out just the nodes we want for this axis based on the filter
          var filteredNodes = sgraph.filter(function(index,ele) {
            if (options.axisFilterType === 'numeric') {
              switch(options.axisNumericFilter[i].operator) {
                case 'gt':
                  return ele.data(options.axisProperty) > options.axisNumericFilter[i].value;
                  break;
                case 'ge':
                  return ele.data(options.axisProperty) >= options.axisNumericFilter[i].value;
                  break;
                case 'lt':
                  return ele.data(options.axisProperty) < options.axisNumericFilter[i].value;
                  break;
                case 'le':
                  return ele.data(options.axisProperty) <= options.axisNumericFilter[i].value;
                  break;
                case 'eq':
                  return ele.data(options.axisProperty) == options.axisNumericFilter[i].value;
                  break;
                case 'ne':
                  return ele.data(options.axisProperty) != options.axisNumericFilter[i].value;
                  break;
              }
            }
            else if (options.axisFilterType === 'string') {
              //code
            }
          });
          
          var sortedNodes = filteredNodes.sort(function(a,b) {
            if (options.axisSortDirection === 'asc') {
              if(a.data(options.axisSort) > b.data(options.axisSort)) {
                return 1;
              }
              else {
                return -1;
              }
            }
            else if (options.axisSortDirection === 'desc') {
              if(a.data(options.axisSort) < b.data(options.axisSort)) {
                return 1;
              }
              else {
                return -1;
              }
            }
          });
          
          // Set the starting X and Y position for this axis
          var startX = cX + radius * Math.cos(startAngle * Math.PI / 180);
          var startY = cY + radius * Math.sin(startAngle * Math.PI / 180);
          var distance = 0;
          var newX = startX;
          var newY = startY;
          
          for(var ii = 0; ii < sortedNodes.length; ii++) {
            var node = sortedNodes[ii];
            if (!mappings.hasOwnProperty(node.id())) {
              newX = newX + ((distance + (node.outerWidth() / 2)) * Math.cos(startAngle * Math.PI / 180));
              newY = newY + ((distance + (node.outerWidth() / 2)) * Math.sin(startAngle * Math.PI / 180));
              distance = node.outerWidth() / 2;
              mappings[node.id()] = { position: { x: newX, y: newY } };
            }
          }
          startAngle += spacing;
          if (startAngle > 360) {
            startAngle -= 360;
          }
        }
        return mappings;
      }
      
      // A function to split the viewport into a grid for hiveplot panels
      function getGrid(integer) {
        var centers = [];
        // If our number is one, we don't really need a grid
        if(integer > 1) {
          var closestRatio = {rows: 1, cols: integer, remainder: 0, ratio: integer};
          var screenWidth = cy.width() * 10;
          var screenHeight = cy.height() * 10;
          var screenRatio = screenWidth/screenHeight;
          
          // First, iterate over all possible combinations and find the one that matches the actual screen ratio most closely.  For now, we will not care if it is over or under...just the closest
          for(var i = 1; i <= Math.ceil(integer/2); i++) {
            var rows = i;
            // We are grabbing the ceiling of this value so as to not need to deal with '+ 1' logic later
            var cols = Math.ceil(integer/i);
            // We need the remainder so we know how many plots are in the last row
            var remainder = integer % cols;
            var ratio = cols/rows;
            
            if(Math.abs(screenRatio - ratio) < Math.abs(screenRatio - closestRatio.ratio)){
              closestRatio.rows = rows;
              closestRatio.cols = cols;
              closestRatio.remainder = remainder;
              closestRatio.ratio = cols/rows;
            }
          }
          
          // Now, find the center X and Y for each plot
          var intervalCol = Math.round(screenWidth / closestRatio.cols);
          var intervalRow = Math.round(screenHeight / closestRatio.rows);
          
          for(var row = 0; row < closestRatio.rows; row++) {
            for(var col = 0; col < closestRatio.cols; col++) {
              var cX = Math.round((intervalCol * (col + 1) - (intervalCol/2)));
              var cY = Math.round((intervalRow * (row + 1) - (intervalRow/2)));
              centers.push({row: row, col: col, x: cX, y: cY});
            }
          }
        }
        else {
          centers.push({row: 1, col: 1, x: Math.round(screenWidth / 2), y: Math.round(screenHeight / 2)});
        }
        return centers;
      }
      
      layout.trigger({type: 'layoutstop', layout: layout});
      return this;
    };
    
    hiveplotLayout.prototype.stop = function(){
      if( this.thread ){
        this.thread.stop();
      }
      
      this.trigger('layoutstop');
      return this;
    };
    
    hiveplotLayout.prototype.destroy = function(){
      if( this.thread ){
        this.thread.stop();
      }
      return this;
    };
    
    // register with cytoscape.js
    cytoscape( 'layout', 'hiveplot', hiveplotLayout );
  };
  
  // expose as a commonjs module
  if( typeof module !== 'undefined' && module.exports ){
    module.exports = register;
  }
  
  // expose as an amd/requirejs module
  if( typeof define !== 'undefined' && define.amd ){
    define('cytoscape-hiveplot', function(){
      return register;
    });
  }
  
  // expose to global cytoscape (i.e. window.cytoscape)
  if( typeof cytoscape !== 'undefined' ){
    register( cytoscape);
  }
})();