# Simple web service to power widgets on The Tyee

This is an initial development release.

## Available routes

### /progress.json

Parameters:

* campaign (optional)
* cb (optional, e.g., callback_name)
* date_end (required, e.g., 2013-11-01)
* date_start (required, e.g., 2013-09-01
* goal (required, e.g., 2000)
* multiplier (optional, e.g., 12 or 3 (months))

### /builderlist.json

Parameters: 

* date_start (optional, e.g., 2015-03-01)

### /shares/email.json

Parameters:

* limit (Optional, e.g., 20. Default: 10)
* days (Optional, e.g., 15. Default: 7)

### /shares/email/url.json

Parameters:

* url (Required, e.g,. http://thetyee.ca/Opinion/2013/12/05/Whos-Watching-Our-Money/ or any part thereof to match against)

