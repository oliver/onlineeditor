Online Editor
=============
This is a Perl CGI script for easily editing a website through the browser.
It is intended to allow website owners to edit selected parts of their site in the browser, without requiring installation of additional software.

To specify the editable parts of a page, the website designer has to place special template marker comments in the source code of a page, and configure that page in the Online Editor configuration file.

The editor uses [CKEditor](http://ckeditor.com/) if supported by browser, and falls back to a textarea otherwise.

Installation
------------
* unpack tgz in cgi-bin directory of the server
* setup password protection (with HTTP authentication) for the onlineeditor
  CGI directory, eg. by adding a .htaccess file


Setting Up an Editable Page
---------------------------
* add `<!-- !begin content! -->` and `<!-- !end content! -->` marker tags around editable content
 * for best results, use a `<div>` tag around the editable content (outside the template marker comments); this will allow to use lists and paragraphs when editing
* add a `<base href>` tag to the page, to ensure that images and scripts are found during editing
* add user account for the new page (with unique user name and strong password)
 * eg. use `pwgen 10 3` to generate passwords
* edit editor.cfg config file and add a section for the new page, specifying path to new page and user name
* open the editor.pl script in browser (eg. http://myserver.com/cgi-bin/onlineeditor/editor.pl), log in as the new user, and you should see the new page with editable content

