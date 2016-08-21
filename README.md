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

## Shares by URL

### /shares/url/all.json

Parameters:

* url (Required, e.g,. http://thetyee.ca/Opinion/2013/12/05/Whos-Watching-Our-Money/)

Returns:

* JSON object with shares for Facebook, Twitter, and E-mail
* The `total` property contains a sum of all shares for that URL across services

### /shares/url/email.json

E-mail shares (via The Tyee's bespoke article e-mail tool).

* url (Required, e.g,. http://thetyee.ca/Opinion/2013/12/05/Whos-Watching-Our-Money/ or any part thereof to match against)

### /shares/url/facebook.json

Facebook shares (via the Facebook Object Graph API using an [App Access Token](https://developers.facebook.com/docs/facebook-login/access-tokens#apptokens)).

* url (Required, e.g,. http://thetyee.ca/Opinion/2013/12/05/Whos-Watching-Our-Money/)

### /shares/url/twitter.json

Twitter shares (via the [NewShareCounts](http://newsharecounts.com/) API). Will eventually be replaced with in-house data.

* url (Required, e.g,. http://thetyee.ca/Opinion/2013/12/05/Whos-Watching-Our-Money/)
