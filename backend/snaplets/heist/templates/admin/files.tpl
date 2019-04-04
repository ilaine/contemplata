<apply template="default">

    <div class="well"><em>
        Below you can see the list of files in the ODIL database.
    </em></div>


    <div class="panel panel-default">
      <div class="panel-heading">Files</div>
      <div class="panel-body">

        <ul class="nav nav-tabs">
          <li role="presentation" class="active">
            <a href="admin/files#inprogess"><b>In progress</b></a>
          </li>
          <li role="presentation">
            <a href="admin/files#done"><b>Done</b></a>
          </li>
        </ul>

        <bind tag="fileTable">
          <table class="table table-striped">
            <thead>
              <tr><fileTableCols/></tr>
            </thead>
            <tbody>
              <panelBody/>
            </tbody>
          </table>
        </bind>

        <div class="tab-content">
          <bind tag="fileTableCols">
            <th>Origin</th>
            <th>Syntax</th>
            <th>Semantics</th>
            <th>Done</th>
            <actions/>
          </bind>
          <div class="tab-pane active" id="inprogress">
            <fileTable/>
            <ul class="list-group">
              <fileList/>
            </ul>
            <!-- <apply template="files/inprogress"/>

             need to change the structure of the sites, adding templates "inprogress.tpl"  and "done.tpl" in a newly created "files" folder -->
          </div>
          <div class="tab-pane" id="done">
            <!-- <apply template="files/done"/> -->
            <ul class="list-group">
              <fileList/>
            </ul>
          </div>
        </div>

      </div>
    </div>

    <script>
      $(window).on('hashchange', function(e){
        var url = document.location.toString();
        if (url.match('#')) {
          var tabID = url.split('#')[1];
          var eleID = url.split('#')[2];
          // console.log("tabID: " + tabID.toString());
          $('.nav-tabs a[href="user/guide#' + tabID + '"]').tab('show');
          if (eleID != null) {
            // console.log("eleID: " + eleID.toString());
            document.getElementById(eleID).scrollIntoView();
          }
        }
      });
    </script>

</apply>
