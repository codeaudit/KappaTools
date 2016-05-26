"use strict"

/* Mode to render observable.  These codes determine
 * how an observable in a plot is to be rendered.
 */
var MODES = {
    MARKS :  0,  // use marks
    LINE :   1,  // use a continuious line
    HIDDEN : 2,  // hide observable
    XAXIS :  3,  // observable is the x axis
    cycle : function(mode){
        return (mode+1) % 3;
    }
};
// enum for tick marks
var TICKS = {
    CIRCLE : 0,
    PLUS   : 1,
    CROSS  : 2,
    cycle : function(mode){
        return (mode+1) % 3;
    },
    index : function(index){
        return (index+1) % 3;
    },
    xlink : function(index){
        return ["#plot-circle"
               ,"#plot-plus"
               ,"#plot-cross"][index];
    }
};

function observable_plot(configuration){
    var that = this;
    /* plotDivId                - div which plot is rendered on
       plotLabelDivId           - div to place plot interval
       plotStyleId              - style sheet for the plot need to export
                                  plot
       plotShowLegendCheckboxId - checkbox to toggle plot legend
       plotXAxisLogCheckboxId   - checkbox to toggle log on x axis
       plotYAxisLogCheckboxId   - checkbox to toggle log on y axis
     */
    this.configuration = configuration;




    /* This should be a list of objects of the form
       index  - there is an assumption of could be duplicated so
                an index is used.
       label  - label of observable
       values - all values for a given observable
       mode   - mode for observable using the mode enumermation

       Note : An entry for time is placed with the label
       null.  This allows an arbitary axis to serve at the
       x-axis.
     */
    this.state = [];

    /* Return the list of labels for values in the plot.
       The time axis is filtered out as it is null.
     */
    this.getLabels = function(){
        return this.state.filter(function(obs){ return obs.label; })
    };

    /* Given a label return the corresponding label.
     */
    this.getObservable = function(index){
        return this.state[index];
    }
    /* Get all observables.
     */
    this.getObservables = function(){
        return this.state.filter(function(obs){ return obs.mode != MODES.XAXIS; })
    }
    this.getStatesByMode = function(mode){
        return this.state.filter(function(obs){ return obs.mode == mode; })
    }

    this.timeLabel = "Time";

    /* Update the plot data of the graph.  This is called
       when new data is to be displayed in a graph.  Care
       is taken not to reset the state of the plot when
       data is updated.
     */
    this.setPlot = function(plot){
        var legend = plot.legend;

        /* An update new copy over state preserving settings
         * where possible.
         */
        var new_state = [];
        var time_values = []; // store the times values

        /* Initialize new state element with the corresponding
         * observables.
         */
        legend.forEach(function(legend,i){
            var old_observable = that.getObservable(i);
            var mode = MODES.MARKS;
            if(old_observable && old_observable.label == legend){
                mode = old_observable.mode;
            };
            new_state.push({ label : legend ,
                             values : [] ,
                             mode : mode
                           });
        });
        // Switch over for the population
        that.state = new_state;
        var time_observable = that.getObservable(i);
        var time_mode = MODES.XAXIS;
        if(time_observable && time_observable.label == that.timeLabel){
            time_mode = time_observable.mode;
        };
        // make sure there is an xaxis
        if(!new_state.every(function(state){ return state.mode != MODES.XAXIS; })){
            time_mode = MODES.XAXIS;
        }
        that.start_time = null;
        that.end_time = null;
        // Populate observables from data.
        plot.observables.forEach(function(observable){
            that.start_time = that.start_time || observable.time;
            that.end_time = observable.time;
            time_values.push(observable.time);
            var values = observable.values;
            that.state.forEach(function(state_observable,i){
                var current = values[i];
                state_observable.values.push(current);
            });
        });
        // Add time axis
        that.state.push({ label : this.timeLabel ,
                          values : time_values ,
                          mode : time_mode
                        });


        // setup colors
        var color = d3.scale.category10();
        color.domain(that.state.map(function(c,i){ return i; }));
        that.state.forEach(function(s,i){ s.color = color(i);
                                          s.tick = TICKS.index(i);
                                        })
        that.renderPlot();
        that.renderLabel();

    };
    this.setPlot = wrap(this.setPlot);
    this.formatTime = d3.format(".02f");
    this.getXAxis = function(){
        return this.state.find(function(state){ state.mode = MODES.XAXIS });
    }
    this.setPlot = wrap(this.setPlot);
    this.renderPlot = function(){
        // set margin
        var margin = {top: 20, right: 80, bottom: 30, left: 80},
            dimensions = that.getDimensions() ,
            width = dimensions.width - margin.left - margin.right,
            height = dimensions.height - margin.top - margin.bottom;

        // setup x-axis
        var x = (that.getXAxisLog()?d3.scale.log().clamp(true):d3.scale.linear()).range([0, width]);
        var xState = that.getStatesByMode(MODES.XAXIS)[0];
        x.domain(d3.extent(xState.values));
        var xAxis = d3.svg.axis().scale(x).orient("bottom");

        // setup y-axis
        var y = (that.getYAxisLog()?d3.scale.log().clamp(true):d3.scale.linear()).range([height, 0]);
        var yAxis = d3.svg
                      .axis()
                      .scale(y)
                      .orient("left")
                      .tickFormat(d3.format(".3n"));

        var observables = that.getObservables();
        var y_bounds = [d3.min(observables,
                         function(c)
                               { return d3.min(c.values.filter(function(d){return !that.getYAxisLog() || d > 0; })); }),
                        d3.max(observables,function(c) { return d3.max(c.values); })
                       ];
        y.domain(y_bounds);

        // Clear div first
        d3.select("#"+that.configuration.plotDivId).html("");
        // Add svg element
        var svg = d3.select("#"+that.configuration.plotDivId).append("svg")
            .attr("width", width + margin.left + margin.right)
            .attr("height", height + margin.top + margin.bottom)
            .append("g")
            .attr("transform"
                 ,"translate(" + margin.left + "," + margin.top + ")");
        // defs
        var svgDefs = createSVGDefs(svg);
        /* Here the defs for the tick marks it was taken from
           an earlier implementation of plots.
         */
        // defs - plus
        svg.append("defs")
           .append("g")
           .attr("id","plot-plus")
           .append("path")
           .attr("d","M-3.5,0 h7 M0,-3.5 v7")
           .style("stroke", "currentColor");
        // defs - cross
        svg.append('defs')
           .append("g")
           .attr("id","plot-cross")
           .append("path")
           .attr("d","M-3.5,-3.5 L3.5,3.5 M3.5,-3.5 L-3.5,3.5")
           .style("stroke", "currentColor");

        // defs - circles
        svg.append("defs")
           .append("g")
           .attr("id","plot-circle")
           .append("circle")
           .attr("r", 1.5)
           .attr("fill","none")
           .style("stroke", "currentColor");

        // draw axis
        svg.append("g")
            .attr( "class"
                 , "x plot-axis")
            .attr("transform"
                 ,"translate(0," + height + ")")
            .call(xAxis);

        svg.append("g")
            .attr("class","y plot-axis")
            .call(yAxis)
            .append("text")
            .attr("transform"
                 ,"rotate(-90)");

        // render data
        var line = d3.svg.line()
            .interpolate("basis")
            .defined(function(d,i) { return !that.getXAxisLog() || xState.values[i] > 0; })
            .defined(function(d,i) { return !that.getYAxisLog() || d > 0; })
            .x(function(d,i) {
                var value = xState.values[i];
                    value = x(value);
                return value; })
            .y(function(d) {
                var value = d;
                return y(value); });
        /* helper function to map values to
           screen coordinates to */
        var xMap = function(d,i){
            var current = xState.values[i];
            current = x(current);
            return current;
        };
        var yMap = function(d) {
            var current = d;
            current = y(current);
            return current;
        };
        var observables =
            svg.selectAll(".observable")
            .data(that.getObservables())
            .enter().append("g")
            .attr("class", "plot-observable")
            .each(function(d)
                  { switch(d.mode) {
                  case MODES.MARKS:
                      var values = d.values.filter(function(d){var x = xMap(d,i);
                                                               var y = yMap(d);
                                                               return (!isNaN(x) && !isNaN(y)) });
                      var tick =
                          d3.select(this)
                          .selectAll(".plot-tick")
                          .data(values)
                          .enter()
                          .append("g")
                          .attr("class", "plot-tick")
                          .attr("fill",d.color);


                      // add link to definitions
                      tick.append("use")
                          .attr("xlink:href",TICKS.xlink(d.tick))
                          .style("color",d.color)
                          .attr("transform"
                                ,function(d,i){ var x = xMap(d,i);
                                                var y = yMap(d);
                                                var t = "translate(" + x + "," + y + ")";
                                                return t;
                                              });
                      break;
                  case MODES.LINE:
                      d3.select(this)
                          .append("path")
                          .attr("class", "plot-line")
                          .attr("d", function(d) { return line(d.values); })
                          .style("stroke", function(d) { return d.color; });
                      break;
                  case MODES.HIDDEN:
                      break;
                  case MODES.XAXIS:
                      break;
                  default:
                      break;
                  } });

        // render legend
        var legendRectSize = 12;
        var legendSpacing = 4;
        var legend = svg.selectAll('.legend')
            .data(that.getObservables())
            .enter()
            .append('g')
            .attr('class', 'plot-legend')
            .attr('transform',
                  function(d, i) {
                      var height = legendRectSize + legendSpacing;
                      var offset = 0;
                      var horz = legendRectSize;
                      var vert = i * height - offset;
                      return 'translate(' + horz + ',' + vert + ')';
                  });
        // cycle through styles
        var cycle = function(d,i)
                    { d.mode = MODES.cycle(d.mode);
                      that.renderPlot();
                    };
        // legend swatches
        legend.append('rect')
              .attr("class", "plot-legend-swatch")
              .attr('width', legendRectSize)
              .attr('height', legendRectSize)
              .style('fill',
                     function(d){
                         var color = d.color;
                         if(MODES.HIDDEN == d.mode){
                             color = "white";
                         };
                         return color;
                     })
              .style('stroke',
                     function(d){
                         var color = d.color;
                         if(MODES.HIDDEN == d.mode){
                             color = "white";
                         };
                         return color;
                     }) // handle clicking on legend
              .style('opacity',
                     function(d){
                         var opacity = 1.0;
                         if(MODES.HIDDEN == d.mode){
                             opacity = 0.0;
                         };
                         return opacity;
                     })
              .style('stroke-opacity',
                     function(d){
                         var opacity = 1.0;
                         if(MODES.HIDDEN == d.mode){
                             opacity = 0.0;
                         };
                         return opacity;
                     }) // handle clicking on legend
              .on('click', cycle);
        // legend text
        legend.append('text')
            .attr('x', legendRectSize + legendSpacing)
            .attr('y', legendRectSize - legendSpacing)
            .text(function(d) { return d.label; })
            .on('click', cycle);
    }
    this.renderPlot = wrap(this.renderPlot);

    /* add label for plot */
    this.renderLabel = function(){
        var that = this;
        if(configuration.plotLabelDivId){
            if (that.start_time){
                var label =
                    "Plot between t = "
                    +that.formatTime(that.start_time)
                    +"s and t = "
                    +that.formatTime(that.end_time)
                    +"s";
                d3.select("#"+configuration.plotLabelDivId)
                  .html(label);
            }
        }
    }

    this.showLegend = true;
    this.setShowLegend = function(showLegend){
        that.showLegend = showLegend;
    }
    this.getShowLegend = function(){
        return that.showLegend;
    }

    this.xAxisLog = false;
    this.setXAxisLog = function(xAxisLog){
        that.xAxisLog = xAxisLog;
    }
    this.getXAxisLog = function(){
        return that.xAxisLog;
    }

    this.yAxisLog = false;
    this.setYAxisLog = function(yAxisLog){
        that.yAxisLog = yAxisLog;
    }
    this.getYAxisLog = function(){
        return that.yAxisLog;
    }

    this.dimensions = { width : 960 , height : 500 };
    this.setDimensions = function(dimensions) {
        that.dimensions = dimensions;
    }
    this.getDimensions = function(){
        return that.dimensions;
    }

    /* define how to export to tsv */
    this.handlePlotTSV = function(){
        var plot = that.getPlot();
        var header = "'time'\t"+plot["legend"].join("\t");
        var body = plot["observables"].map(function(d) { var row = [d["time"]];
                                                         row = row.concat(d["values"]);
                                                         return row.join("\t") }).join("\n");
        var tsv = header+"\n"+body;
        saveFile(tsv,"text/tab-separated-values",that.getPlotName(".tsv"));
    }
    this.handlePlotTSV = wrap(this.handlePlotTSV);

    /* add checkbox handlers for display options */
    this.addHandlers = function(){
        function checkboxHandler(id,setter){
            if(id){
                setter(document.getElementById(id).checked);
                var handler = function(){ setter(document.getElementById(id).checked);
                                          that.render();};
                d3.select("#"+id).on("change",handler);
            }
        }
        checkboxHandler(configuration.plotShowLegendCheckboxId,that.setShowLegend);
        checkboxHandler(configuration.plotXAxisLogCheckboxId,that.setXAxisLog);
        checkboxHandler(configuration.plotYAxisLogCheckboxId,that.setYAxisLog);
    }
    /* render plot */
    this.render = function(){
        that.renderPlot();
        that.renderLabel();
    };
    this.addHandlers();
}
