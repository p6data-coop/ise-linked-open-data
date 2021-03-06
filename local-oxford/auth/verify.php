<!DOCTYPE html>
<html lang="en">
    <head>
    <link rel="stylesheet" type="text/css" href="styles.css">
   </head>
    <body>

<?php	
		
		// Include our login information
		include('db_login.php');

		$match = htmlentities($_GET["id"]);  //needs securing
		
		// Check verification code and if present change 'verify' from 0 to 1.
		$getmatch = 'SELECT * FROM users WHERE verification = ?;';

        if ($stmt = mysqli_prepare($conn, $getmatch)) {
            mysqli_stmt_bind_param($stmt, "s", $match);
            mysqli_stmt_execute($stmt);
            $result = mysqli_stmt_get_result($stmt);
        };

		if (mysqli_num_rows($result) == 1){
			$verify = 'UPDATE users SET verified = 1 WHERE verification = ?;';
			        if ($statemt = mysqli_prepare($conn, $verify)) {
            mysqli_stmt_bind_param($statemt, "s", $match);
            mysqli_stmt_execute($statemt);
        };


			echo "<p style='padding:20px;'> Your email has been verified, please <a href='login.php'>log in</a>.</p>";

			//Send an email notification to moderator

			$row = mysqli_fetch_row($result);
			$sendto = "dan@solidarityeconomics.org";
			$subject = "Local Map Notification - New User";
			$msg = "A new user has been verified on the Oxford SE Map, their email is: ".$row[1].", in the database their id = ".$row[0];
 		$headers = 'From: dan@solidarityeconomics.org' . "\r\n" .
    		'X-Mailer: PHP/' . phpversion();
 		mail($sendto,$subject,$msg,$headers);

		};
			
		mysqli_close($conn);
		
?>

    
    </body>
</html>
