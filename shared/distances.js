"use strict"

function DistancesPlot(id){
    var that = this;
    this.id = "#"+id;
    this.setData = function(json){
        var data = JSON.parse(json);
        that.data = data;
        that.clearPlot();
	that.renderPlot(); 
    }
    this.setData = wrap(this.setData);

    this.clearPlot = function(){
        d3.select(that.id).selectAll("svg").remove();
    }

    this.exportJSON = function(filename){
        var json = JSON.stringify(that.data);
        saveFile(json,"application/json",filename);
    }
    this.exportJSON = wrap(this.exportJSON);

    this.clearData = function () {
	that.data = null;
	that.clearPlot();
    }

    this.renderPlot = function () {
	 // set the dimensions of the canvas
  var margin = {top: 20, right: 20, bottom: 70, left: 40},
  width = 600 - margin.left - margin.right,
  height = 300 - margin.top - margin.bottom;

  // set the ranges
  //  var x = d3.scale.ordinal().rangeRoundBands([0, width], .05);
  //  var y = d3.scale.linear().range([height, 0]);
  
  // define the axis
  //  var xAxis = d3.svg.axis()
  //    .scale(x)
  //    .orient("bottom");
  //  var yAxis = d3.svg.axis()
  //    .scale(y)
  //    .orient("left");

// setup x 
var xValue = function(d) { return d.time;}, // data -> value
    xScale = d3.scale.linear().range([0, width]), // value -> display
    xMap = function(d) { return xScale(xValue(d));}, // data -> display
    xAxis = d3.svg.axis().scale(xScale).orient("bottom");

// setup y
var yValue = function(d) { return d.distance;}, // data -> value
    yScale = d3.scale.linear().range([height, 0]), // value -> display
    yMap = function(d) { return yScale(yValue(d));}, // data -> display
    yAxis = d3.svg.axis().scale(yScale).orient("left");


  // add the SVG element
  var svg = d3.select(that.id).append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
    .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  // setup fill color
  var cValue = function(d) { return d.rule;},
  color = d3.scale.category10();

  // add the tooltip area to the webpage
  var tooltip = d3.select("body").append("div")
    .attr("class", "tooltip")
    .style("opacity", 0);

  var data = that.data.map(function (d) { return {rule : d.rule_dist, distance : d.dist, time: d.time_dist}; });
  var toto = that.data.sort(function(a,b){return d3.ascending(a.time, b.time); });

  // scale the range of the data
  //  x.domain(data.map(function(d) { return d.time; }));
  //  y.domain([0, d3.max(data, function(d) { return d.distance; })]);

  // don't want dots overlapping axis, so add in buffer to data domain
  xScale.domain([d3.min(data, xValue)-1, d3.max(data, xValue)+1]);
  yScale.domain([d3.min(data, yValue)-1, d3.max(data, yValue)+1]);

  // add axis
  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + height + ")")
      .call(xAxis)
      .selectAll("text")
      .style("text-anchor", "end")
      .attr("dx", "-.8em")
      .attr("dy", "-.55em")
      .attr("transform", "rotate(-90)" );

  svg.append("g")
      .attr("class", "y axis")
      .call(yAxis)
      .append("text")
      .attr("transform", "rotate(-90)")
      .attr("y", 5)
      .attr("dy", ".71em")
      .style("text-anchor", "end")
      .text("distance");

  // Add circle chart
  svg.selectAll("circle")
      .data(data)
      .enter().append("circle")
      .attr("class", "bar")
      .attr("cx", xMap)
      .attr("cy", yMap)
      .attr("r", 5)
      .style("fill", function(d) { return color(cValue(d));})
      .on("mouseover", function(d) {
          tooltip.transition()
               .duration(200)
               .style("opacity", .9);
          tooltip.html(d.rule + "<br/> (" + xValue(d) 
	        + ", " + yValue(d) + ")")
               .style("left", (d3.event.pageX + 5) + "px")
               .style("top", (d3.event.pageY - 28) + "px");
      })
      .on("mouseout", function(d) {
          tooltip.transition()
               .duration(500)
               .style("opacity", 0);
      });

  // draw legend
  var legend = svg.selectAll(".legend")
      .data(color.domain())
    .enter().append("g")
      .attr("class", "legend")
      .attr("transform", function(d, i) { return "translate(0," + i * 20 + ")"; });

  // draw legend colored rectangles
  legend.append("rect")
      .attr("x", width - 18)
      .attr("width", 18)
      .attr("height", 18)
      .style("fill", color);

  // draw legend text
  legend.append("text")
      .attr("x", width - 24)
      .attr("y", 9)
      .attr("dy", ".35em")
      .style("text-anchor", "end")
      .text(function(d) { return d;})

    };

    this.renderPlot = wrap(this.renderPlot);
    
    return this;
}

