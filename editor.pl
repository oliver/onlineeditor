#!/usr/bin/perl

#
# Simple online editor for modifying part of a web page.
#

use strict;
use warnings FATAL => qw( all );

use Encode;
use Locale::TextDomain ('editor', './locale/');

use CGI;
use CGI::Carp;
#use CGI::Carp qw(fatalsToBrowser);

$CGI::POST_MAX = 1024 * 100;
$CGI::DISABLE_UPLOADS = 1;


# config file to load
my $configPath = 'editor.cfg';


# the HTML file to modify (will be set later from config):
my $htmlFile;


# Returns true if the supplied text can be successfully decoded as UTF-8,
# false if the text contains invalid UTF-8 contents.
sub isValidUtf8
{
    my ($text) = @_;
    return scalar(eval { decode('UTF-8', $text, Encode::FB_CROAK) });
}


# reads the specified config file, and returns an array of hashreferences
sub readConfigFile
{
    my ($path) = @_;

    my @pages = ();
    my $currPageRef;

    open(IN, "<$path") or die("failed to open config file '$path': $!");
    while(<IN>)
    {
        chomp($_);
        next if (/^\s*$/ or /^\s*#/ or /^\s*;/);

        if (/^\[page\]$/)
        {
            my %page;
            $currPageRef = \%page;
            push( @pages, $currPageRef );
        }
        else
        {
            my ($key, $value) = (/^(\w+)=(.*)$/);
            $key || die("syntax error: bad key");
            $value || die("syntax error: bad value");
            $currPageRef->{$key} = $value;
        }
    }
    close(IN);
    return @pages;
}


# Detect and use correct locale for current user.
# Uses HTTP Accept-Language header to detect preferred language.
sub setUserLocale
{
    my ($cgi) = @_;
    my $acceptLang = $cgi->http('accept-language');
    if (!$acceptLang)
    {
        return;
    }

    # Note: this is a very rudimentary Accept-Language parser.
    my @langs = ();
    foreach my $l (split(/,/, $acceptLang))
    {
        my ($langCode) = ($l =~ /^([a-zA-Z]{1,2}(-[a-zA-Z]{1,2})?)/);
        if ($langCode)
        {
            push(@langs, $langCode);

            # also add automatic fallback to less-specific language code:
            my ($countryCode) = ($langCode =~ /^(\w+)-\w+$/);
            if ($countryCode)
            {
                push(@langs, $countryCode);
            }
        }
    }

    my $langVar = join(':', @langs);
    $ENV{'LANGUAGE'} = $langVar;
}


# parses HTML template file, and returns template text and start offset and length of editable area
sub parseTemplate
{
    open(IN, "<$htmlFile") or die("failed to open template file '$htmlFile': $!");
    my $html = '';
    while (<IN>)
    {
        $html .= $_;
    }
    close(IN);

    my $beginTag = '<!-- !begin content! -->';
    my $endTag = '<!-- !end content! -->';

    my $openPos = index($html, $beginTag);
    if ($openPos < 0)
    {
        die("missing Begin tag");
    }
    if (index($html, $beginTag, $openPos+1) != -1)
    {
        die("duplicate Begin tags");
    }
    $openPos += length($beginTag);

    my $closePos = index($html, $endTag);
    if ($closePos < 0)
    {
        die("missing End tag");
    }
    if (index($html, $endTag, $closePos+1) != -1)
    {
        die("duplicate End tags");
    }

    if ($closePos < $openPos)
    {
        die("bad ordering of Begin/End tags ($openPos/$closePos)");
    }

    return ($html, $openPos, $closePos-$openPos);
}

# extracts the current editable content (as HTML) from template
sub extractFromTemplate
{
    my ($html, $startPos, $len) = &parseTemplate();
    return substr($html, $startPos, $len);
}

# inserts the given content HTML into the template text; returns the resulting complete HTML text
sub applyTemplate
{
    my ($newContent) = @_;
    my ($html, $startPos, $len) = &parseTemplate();
    my $preText = substr($html, 0, $startPos);
    my $postText = substr($html, $startPos + $len);
    return $preText . $newContent . $postText;
}

# Checks that the specified file is valid for use as template file.
# These checks are performed for security reasons.
sub isValidTemplateFile
{
    my ($path) = @_;
    return 0 if (! -e $path ); # must exist
    return 0 if (! -f $path ); # must be a plain file (no symlink etc.)
    return 0 if (! -r $path ); # must be readable
    return 0 if (! -w $path ); # must be writable
    return 0 if (-x $path );   # must not be executable (to prevent malicious modification of scripts)
    return 0 if ( $path !~ /\.htm(l?)$/ ); # must have .htm or .html suffix
    return 1;
}


# saves the given content HTML to disk; returns undef on success, an error string otherwise
sub saveToTemplate
{
    my ($contentHtml) = @_;

    if (!isValidTemplateFile($htmlFile))
    {
        return __ "invalid HTML file";
    }

    if (!isValidUtf8($contentHtml))
    {
        return __ "invalid UTF-8 data";
    }

    my $fullHtml = applyTemplate($contentHtml);
    if (!open(OUT, ">$htmlFile"))
    {
        return "$!";
    }
    print OUT $fullHtml;
    close(OUT);

    # extract current text from disk again, to check that saving was really successful:
    my $diskContent = extractFromTemplate();
    if ($diskContent ne $contentHtml)
    {
        return __ "unknown error";
    }
    return undef;
}



# Processes HTML content extracted from template so that it can be displayed in <textarea>.
sub htmlToText
{
    my ($html) = @_;

    # remove existing linebreaks
    $html =~ s/[\r\n]//sg;
    # turn <br> tags into linebreaks
    $html =~ s/<br\s*\/?>/\n/sg;

    return $html;
}


# Processes received <textarea> text results into (unsanitized) HTML code.
sub textToHtml
{
    my ($text) = @_;

    # all linebreaks are turned to <br>
    $text =~ s/\n/<br>/sg;

    return $text;
}


# Sanitizes HTML code.
# Except for a few allowed HTML tags, all opening/closing brackets are escaped.
# Also, any clearly invalid HTML entities (or other invalid uses of ampersand)
# are escaped.
#
# This function is security-critical because it must prevent insertion of
# unwanted (malicious) code into the HTML page (eg. XSS).
#
# Any user-supplied text written to disk must be passed through this function!
sub sanitizeHtml
{
    my ($text) = @_;

    # all non-printable characters are removed
    $text =~ s/[\x00-\x19]//sg;

    # allow <br>, <br/>, <p>, <b>, <i>, <s>, <strong>, <em>, <strike> (and closing variants)
    # (use nonprintable characters for temporarily "saving" these tags)
    $text =~ s/<(br\s*\/?)>/\x00${1}\x01\n/sg;
    $text =~ s/<(\/?p)>/\x00${1}\x01\n/sg;

    $text =~ s/<(\/?b)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?i)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?s)>/\x00${1}\x01/sg;

    $text =~ s/<(\/?strong)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?em)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?strike)>/\x00${1}\x01/sg;

    $text =~ s/<(\/?li)>/\x00${1}\x01\n/sg;
    $text =~ s/<(\/?ul)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?ol)>/\x00${1}\x01/sg;

    # escape all remaining HTML tag characters
    $text =~ s/</&lt;/sg;
    $text =~ s/>/&gt;/sg;
    $text =~ s/"/&quot;/sg;
    $text =~ s/'/&#x27;/sg;

    # restore "saved" tags from above
    $text =~ s/\x00/</sg;
    $text =~ s/\x01/>/sg;


    # use same method to replace invalid entities
    $text =~ s/&([a-zA-Z0-9]{1,8};)/\x00${1}/sg;
    $text =~ s/&/&amp;/sg;
    $text =~ s/\x00/&/sg;

    return $text;
}


# Processes raw text so that it can be included in <textarea> in normal HTML code.
sub textToTextarea
{
    my ($text) = @_;
    $text =~ s/&/&amp;/sg;
    $text =~ s/</&lt;/sg;
    $text =~ s/>/&gt;/sg;
    return $text;
}



my $cgi = new CGI;

my $user = $cgi->remote_user();
if (!$user)
{
    die("user is not logged in");
}

setUserLocale($cgi);

my @pages = readConfigFile($configPath);
for my $pageRef (@pages)
{
    if ($pageRef->{'user'} eq $user)
    {
        if ($htmlFile)
        {
            die("multiple pages configured for user '$user'");
        }
        $htmlFile = $pageRef->{'file'};
    }
}

if (!$htmlFile)
{
    die("no page configured for user '$user'");
}


my $contentHtml;
my $doSave = 0;
{
    my $contentText = $cgi->param('edittext');
    if (defined($contentText))
    {
        my $rawHtml = textToHtml($contentText);
        $contentHtml = sanitizeHtml($rawHtml);
        $doSave = 1;
    }
    elsif (defined($cgi->param('cktext')))
    {
        my $ckHtml = $cgi->param('cktext');
        $contentHtml = sanitizeHtml($ckHtml);
        $doSave = 1;
    }
    else
    {
        my $rawHtml = extractFromTemplate();
        $contentHtml = sanitizeHtml($rawHtml);

        if (!isValidUtf8($contentHtml))
        {
            die("template file contains bad UTF-8");
        }
    }
}


#if ($cgi->param('preview'))
if (1)
{
    my $message = "";
    my $forceDirty = 0;
    if ($doSave)
    {
        my $error = saveToTemplate($contentHtml);
        if ($error)
        {
            $message .= "<font color='red'>".(__x 'Saving failed ({error}). Please inform system administrator.', error=>$error)."</font> ";
            $forceDirty = 1;
        }
        else
        {
            print $cgi->redirect(-url => $cgi->url(-full=>1));
            exit;
        }
    }

    print $cgi->header(-charset=>'utf-8',);

    my $injectedHtml = "<form id='edit_form' action='".$cgi->url(-full=>1)."' method='POST' accept-charset='UTF-8' onsubmit='javascript:saving=true;'>";

    $injectedHtml .= "<span id='basic'><textarea id='edittext' name='edittext' rows='10' cols='80' style='width:95%; height:40ex'>".textToTextarea(htmlToText($contentHtml))."</textarea><br>
<input type='submit' name='save' id='btn_save' value='".(__ 'Save')."' style='padding-right:2em; padding-left:2em;'></span>";

    if ($message)
    {
        $injectedHtml .= " $message\n";
    }

    $injectedHtml .= "<input type='hidden' name='cktext' id='cktext'>
</form>";
    my $fullHtml = applyTemplate($injectedHtml);

    my $headerCode = <<'EOF'

<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />

<style type="text/css">
.cke_button_icon.cke_button__save_icon {
   display: none;
}
.cke_button_label.cke_button__save_label {
   display: inline;
}
</style>

<script src='http://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js'></script>

EOF
;


my $footerCode = '
<script type="text/javascript">//<![CDATA[
var unsavedChangesText = "'.(__ 'There are unsaved changes. Really leave this page?').'";
var forceDirty = '.($forceDirty?'true':'false').';
//]]></script>
';


$footerCode .= <<'EOF'

<script src='http://cdnjs.cloudflare.com/ajax/libs/ckeditor/4.0.1/ckeditor.js'></script>
<script type="text/javascript">//<![CDATA[

var extendedMode = false;
var saving = false;

var saveCommand = { 'exec':function(editor) {
    saving = true;
    $("#cktext").val(editor.getData());
    $("#edittext").remove();
    $('#edit_form').submit();
} };

function checkTextareaDirty()
{
    return ($("#edittext").val() != decodeURIComponent(origTextEsc));
}

$(document).ready(function()
{
    $(window).on('beforeunload', function() {
        if (!saving && (forceDirty || (extendedMode && editor.checkDirty()) || (!extendedMode && checkTextareaDirty())))
            return unsavedChangesText;
    });

    if (CKEDITOR.env.isCompatible)
    {
        extendedMode = true;

        $("#basic").hide();

        CKEDITOR.disableAutoInline = true;

        $("form").prepend('<div id="editarea" contentEditable="true">'+decodeURIComponent(origHtmlEsc)+'</div>');

        var editor = CKEDITOR.inline('editarea', {
            removePlugins: 'tabletools,contextmenu',
            startupFocus: true,
            entities: false,
            toolbarGroups: [
                { name: 'basicstyles', groups: [ 'basicstyles', 'cleanup' ] },
                { name: 'paragraph',   groups: [ 'list' ] },
                { name: 'others' }
            ]
        });

        // TODO: maybe add "allowedContent" config flag to explicitly restrict available tags?
        // See http://docs.ckeditor.com/#!/guide/dev_allowed_content_rules

        editor.addCommand('mysave', saveCommand);
        editor.ui.addButton('save', {label:$("#btn_save").val(), command:'mysave', toolbar:'others,1'});
    }

    CKEDITOR.on('instanceReady', function() {
        editor.element.$.title = '';
    });
});

//]]></script>

EOF
;

$footerCode .= '<script type="text/javascript">//<![CDATA[
var origHtmlEsc = "' . CGI::escape($contentHtml) . '";
var origTextEsc = "' . CGI::escape(htmlToText($contentHtml)) . '";
//]]></script>
';

    $fullHtml =~ s:</head>:$headerCode</head>:sgi;
    $fullHtml =~ s:</body>:$footerCode</body>:sgi;

    print $fullHtml;
}

