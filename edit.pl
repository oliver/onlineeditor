#!/usr/bin/perl

#
# Simple online editor for modifying part of a web page.
#

use strict;
use warnings FATAL => qw( all );

use Locale::TextDomain ('editor', './locale/');

use CGI;
use CGI::Carp qw(fatalsToBrowser);

$CGI::POST_MAX = 1024 * 100;
$CGI::DISABLE_UPLOADS = 1;


# the HTML file to modify
my $htmlFile = "./page.html";


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
    open(IN, "<$htmlFile") or die("failed to open template file '$htmlFile'");
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

    if ($closePos <= $openPos)
    {
        die("bad ordering of Begin/End tags");
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

# saves the given content HTML to disk; returns undef on success, an error string otherwise
sub saveToTemplate
{
    my ($contentHtml) = @_;
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


# Processes raw textarea content into HTML that can be inserted into the template.
# This includes:
# - sanitizing HTML by escaping unknown/unwanted HTML tags and entities
# - replacing linebreaks with <br>
#
# This function is security-critical because it must prevent insertion of
# unwanted (malicious) code into the HTML page (eg. XSS).
#
# When changing this function, the textToHtml() function in Javascript code below
# must be changed as well, to ensure that preview is correct.
sub textToHtml
{
    my ($text) = @_;

    # all linebreaks are turned to <br>
    $text =~ s/\n/<br>/sg;

    # all non-printable characters are removed
    $text =~ s/[\x00-\x19]//sg;

    # allow <br>, <b>, <i>, <u> (and closing variants)
    # (use nonprintable characters for temporarily "saving" these tags)
    $text =~ s/<(br)>/\x00${1}\x01\n/sg;
    $text =~ s/<(\/?b)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?i)>/\x00${1}\x01/sg;
    $text =~ s/<(\/?u)>/\x00${1}\x01/sg;

    # escape all remaining HTML special characters
    $text =~ s/&/&amp;/sg;
    $text =~ s/</&lt;/sg;
    $text =~ s/>/&gt;/sg;

    # restore "saved" tags from above
    $text =~ s/\x00/</sg;
    $text =~ s/\x01/>/sg;

    return $text;
}

# Processes HTML content extracted from template so that it can be displayed in textarea.
# This includes:
# - replacing <br> with linebreaks
# - restoring escaped HTML special characters
sub htmlToText
{
    my ($html) = @_;
    $html =~ s/[\r\n]//sg;
    $html =~ s/<br>/\n/sg;
    $html =~ s/&lt;/</sg;
    $html =~ s/&gt;/>/sg;
    $html =~ s/&amp;/&/sg;
    return $html;
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

# for additional security, require that HTTP Authentication is in use when calling
# this script (this should help catch accidental installation in unprotected location):
if (!$cgi->remote_user())
{
    die("user is not logged in");
}

setUserLocale($cgi);


my $contentHtml;
{
    my $contentText = $cgi->param('content');
    if (defined($contentText))
    {
        $contentHtml = textToHtml($contentText);
    }
    else
    {
        $contentHtml = extractFromTemplate();
        $contentHtml = textToHtml(htmlToText($contentHtml));
    }
}


if ($cgi->param('preview'))
{
    print $cgi->header(-charset=>'utf-8',);

    $contentHtml = "<span id='editor_content'>$contentHtml</span>";

    print applyTemplate($contentHtml);
}
else
{

    my $cssCode = <<'EOF'

html, body { height: 100%; }
EOF
;


    my $jsCode = <<'EOF'

// this function must do exactly the same as the Perl textToHtml() function (otherwise preview might be incorrect)
function textToHtml (text)
{
    text = text.replace(/\n/g, '<br>');

    text = text.replace(/[\x00-\x19]/g, '');

    text = text.replace(/<(br)>/g, '\x00$1\x01\n');
    text = text.replace(/<(\/?b)>/g, '\x00$1\x01');
    text = text.replace(/<(\/?i)>/g, '\x00$1\x01');
    text = text.replace(/<(\/?u)>/g, '\x00$1\x01');

    text = text.replace(/&/g, '&amp;');
    text = text.replace(/</g, '&lt;');
    text = text.replace(/>/g, '&gt;');

    text = text.replace(/\x00/g, '<');
    text = text.replace(/\x01/g, '>');

    return text;
}


var origContent;
var editSpan;
function updatePreview()
{
    var newContent = $("#content").val();
    var changed = (newContent != origContent);
    $('#btn_save').attr("disabled", !changed);

    if (editSpan)
    {
        var newHtml = textToHtml(newContent);
        editSpan.html(newHtml);
    }
}

$(document).ready(function()
{
    origContent = document.getElementById('content').value;

    editSpan = $("#previewwin").contents().find("#editor_content");
    updatePreview();

    $("#previewwin").load(function()
    {
        editSpan = $("#previewwin").contents().find("#editor_content");
        updatePreview();
    } );

    $('#save_note').delay(3000).fadeOut('slow');
} );

EOF
;

    print $cgi->header(-charset=>'utf-8',),
          $cgi->start_html(-title => 'Online Editor',
                           -script => [ { -src => 'http://code.jquery.com/jquery-1.9.1.min.js' },
                                        { -code => $jsCode } ],
                           -style => { -code => $cssCode } );

    my $message = '';
    if ($cgi->param('save'))
    {
        my $error = saveToTemplate($contentHtml);
        if ($error)
        {
            $message .= "<font color='red'>".(__x 'Saving failed ({error}). Please inform system administrator.', error=>$error)."</font> ";
        }
        else
        {
            $message .= "<span id='save_note'><font color='gray'>".(__x 'changes saved')."</font></span> ";
        }
    }

    my $contentText = htmlToText($contentHtml);

    print "
<form action='edit.pl' method='POST' style='height:90%'>

<div style='display:inline-block; width:48%; height:100%; min-width: 15em'>
<div style='min-height:4ex'>
<input type='submit' name='save' id='btn_save' value='".(__ 'Save')."' style='padding-right:2em; padding-left:2em;'>
";

    if ($message)
    {
        print "$message\n";
    }

    print "</div>
<textarea style='width:100%; height:100%;' id='content' name='content' cols='70' rows='10' onchange='updatePreview()' onkeydown='updatePreview()' onkeyup='updatePreview()' oninput='updatePreview()'>".textToTextarea($contentText)."</textarea>
</div>
<div style='display:inline-block; width:50%; height:100%; min-width:15em; padding-left:0.3em; padding-right:0.3em'>
<div style='height:4ex'>".(__ 'Preview:')."</div>
<iframe style='width:100%; height:100%' name='previewwin' id='previewwin' src='edit.pl?preview=1'></iframe>
</div>
</form>
";

    print $cgi->end_html();
}

