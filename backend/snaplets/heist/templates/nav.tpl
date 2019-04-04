<div class="navbar navbar-default" role="navigation">
  <div class="navbar-header">
    <!--button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".navbar-collapse">
      <span class="sr-only">Toggle navigation</span>
      <span class="icon-bar"></span>
      <span class="icon-bar"></span>
      <span class="icon-bar"></span>
    </button-->
    <a class="navbar-brand" href="">ODIL</a>
  </div>
  <div class="navbar-collapse collapse">
    <ul class="nav navbar-nav navbar-right">
      <!--li>
        <a href="contact">Contact</a>
      </li-->
      <ifLoggedIn>
        <ifAdmin>
          <li>
            <a href="admin/files">Files</a>
          </li>
          <li>
            <a href="admin/upload">Upload</a>
          </li>
          <li>
            <a href="admin/users">Users</a>
          </li>
        </ifAdmin>
        <ifNotAdmin>
          <li>
            <a href="user/files">Files</a>
          </li>
        </ifNotAdmin>

        <li>
          <a href="user/guide">Guide</a>
        </li>

        <ifNotGuest>
          <li>
            <a href="user/password">Password</a>
          </li>
        </ifNotGuest>
        <li>
          <a href="logout">Sign Out</a>
        </li>
        <li>
          <a href=".">(<currentLogin/>)</a>
        </li>
      </ifLoggedIn>

      <ifLoggedOut>
        <li>
          <a href="login">Sign In</a>
        </li>
      </ifLoggedOut>
    </ul>
  </div>
</div>

<script>
  $(document).ready(function() {
    // get current URL path and assign 'active' class
  	var pathname = window.location.pathname; // returns /user/guide
    var link = pathname.slice(1) // returns user/guide
  	$('.nav > li > a[href="'+link+'"]').parent().addClass('active');
  })
</script>
