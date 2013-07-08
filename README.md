eTimeSheetsDriver
=================

Selenium script to parse a CSV file of timesheet data and fill in the eTimeSheets web application automagically.

You will need:
* A fairly recent java binary to run Selenium (the Selenium .jar file is included in this repository for convenience)
* Windows (other OSes may work, but are unsupported)
* ruby 1.9+ (This is easiest if you simply grab the RubyInstaller for Windows from http://rubyinstaller.org/downloads, including the [DevKit](http://rubyforge.org/frs/download.php/76808/DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe))
* selenium-webdriver (If you're using RubyInstaller for Windows, you'll have the gem package, so just run 'gem install selenium-webdriver' at the command prompt)
* Firefox (as the webdriver is somewhat variable on other browsers)
* Three environment variables:
    * ETIMESHEETS_URL set to the root url (plus port if required) of the eTimeSheets web application.
    * ETIMESHEETS_USER set to the user name (possibly full email address) of the user to automate.
    * ETIMESHEETS_PW set to the plain text password of the user to automate. Yes this is a bad practice. Tell eTimeSheets to support https or OAuth tokens. (Actually don't, because they'll break this script when they do...)

See example-data.csv for the data file format.

Please log support requests as github issues on this repository. Feel free to clone, patch, and pull request!
