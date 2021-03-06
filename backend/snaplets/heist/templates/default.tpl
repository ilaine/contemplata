<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="">
    <meta name="author" content="">
    <!--link rel="shortcut icon" href="../../docs-assets/ico/favicon.png"-->

    <!--base href="http://localhost:8000/"/-->
    <hrefBase/>

    <title>ODIL</title>

    <!-- Bootstrap core CSS -->
    <!--link absHref="/bootstrap/css/bootstrap.css" rel="stylesheet">
    <link absHref="/css/signin.css" rel="stylesheet">
    <link absHref="/css/custom.css" rel="stylesheet"-->
    <link href="public/bootstrap/css/bootstrap.css" rel="stylesheet">
    <link href="public/css/signin.css" rel="stylesheet">
    <link href="public/css/custom.css" rel="stylesheet">

    <!-- Custom styles for this template -->
    <!--link absHref="navbar.css" rel="stylesheet"-->

    <!-- Just for debugging purposes. Don't actually copy this line! -->
    <!--[if lt IE 9]><script src="../../docs-assets/js/ie8-responsive-file-warning.js"></script><![endif]-->

    <!-- HTML5 shim and Respond.js IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/libs/html5shiv/3.7.0/html5shiv.js"></script>
      <script src="https://oss.maxcdn.com/libs/respond.js/1.3.0/respond.min.js"></script>
    <![endif]-->
  </head>

  <body>

    <!-- Bootstrap core JavaScript
    ================================================== -->
    <!-- We could place it at the end of the document so that the page loads faster. -->
    <!-- However, we sometimes rely on the JQuery functionality in our scripts. -->
    <script src="https://code.jquery.com/jquery-1.10.2.min.js"></script>
    <!-- FOR SOME REASONE, THE JS SCRIPT BELOW DID NOT WORK! WE REPLACED IT WITH MAXCDN... -->
    <!--script href="public/bootstrap/js/bootstrap.min.js"/-->
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>

    <div class="container">
      <apply template="nav" />
      <apply-content />
    </div> <!-- /container -->

  </body>
</html>
