
define(["app/console", "app/view", "app/debug"], function(myconsole, view, debugging){
	"use strict";

	function init() {
		console.log("TODO - Check the use of console here. Is this the mechanism by which app/copnsole gets used by the rest of the app?");
		console.log("TODO - Check why is app/debug being loaded here - probably a leftover from clone origin.");

		// The code for each view is loaded by www/app/view.js
		// Initialize the views:
		view.init();
		// Each view will ensure that the code for its presenter is loaded.
	}
	var pub = {
		init: init
	};
	return pub;
});
