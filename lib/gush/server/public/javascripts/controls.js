function debug(str){
  console.log(str);
};

var requestJobsList = function() {
  var jobs_list = $('#jobs-list');
  if (jobs_list.length > 0) {
    ws.send("jobs.list." + jobs_list.data('workflow-id'));
  }
}
var showWorkflows = function(data) {
  var list = $('#workflows-list');
  list.empty();

  $.each(data["workflows"], function () {
    list.append("<li><a href='/workflow?id=" + this["name"] + "'>"+ this["json_class"] + "</a></li>");
  })
};

var showJobs = function(data) {
  var list = $('#jobs-list');
  list.empty();
  $.each(data["jobs"], function () {
    var status = "<span class='label round secondary'>waiting</span>";

    if (this["enqueued"]) {
      status = "<span class='label round'>enqueued</span>";
    }

    if (this["finished"]) {
      status = "<span class='label round success'>finished</span>";
    }

    if (this["failed"]) {
      status = "<span class='label round alert'>failed</span>";
      status += " <a class='button alert round tiny rerun-job' data-workflow-id='" + this["workflow_id"] + "' data-job='" + this["name"] +"'>rerun</a>";
    }
    list.append("<li>"+ this["name"] + " " + status + "</li>");
  })
};

var ws;

  $(document).ready(function() {
    if (!("WebSocket" in window)) {
      alert("Sorry, WebSockets unavailable.");
      return;
    }


    ws = new WebSocket("ws://localhost:9000/ws");
    ws.onmessage = function(evt) {
      var data = JSON.parse(evt.data);
      debug(data);
      if (data["type"] == "jobs.list") {
        showJobs(data);
      }
      if (data["type"] == "workflows.list") {
        showWorkflows(data);
      }
      if (data["type"] == "workflows.add") {
        ws.send("workflows.list");
      }
      if (data["type"] == "jobs.status") {
        requestJobsList();
      }
    };
    ws.onclose = function() { debug("socket closed"); };
    ws.onopen = function() {
      ws.send("workflows.list");
      requestJobsList();
    };

  });

$(document).on('click', '#workflows-list', function(){
  ws.send("workflows.list");
});

$(document).on('click', '#workflows-add', function(){
  ws.send("workflows.add");
});

$(document).on('click', '#workflow-start', function(){
  ws.send("workflows.start." + $(this).data('workflow-id'));
});

$(document).on('click', '.rerun-job', function(){
  ws.send("jobs.run." + $(this).data("workflow-id") + "." + $(this).data("job"));
});
