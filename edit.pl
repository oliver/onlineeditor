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
    open(IN, "<$htmlFile") or die;
    my $html = '';
    while (<IN>)
    {
        $html .= $_;
    }
    close(IN);

    my $beginTag = '<!-- !begin content! -->';
    my $endTag = '<!-- !end content! -->';

    my $openPos = index($html, $beginTag);
    if (index($html, $beginTag, $openPos+1) != -1)
    {
        die("duplicate Begin tags");
    }
    $openPos += length($beginTag);

    my $closePos = index($html, $endTag);
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
sub textToHtml
{
    my ($text) = @_;
    $text =~ s/\r\n/\n/sg;
    $text =~ s/\n/<br>\n/sg;
    return $text;
}

# Processes HTML content extracted from template so that it can be displayed in textarea.
# This includes:
# - replacing <br> with linebreaks
sub htmlToText
{
    my ($html) = @_;
    $html =~ s/<br>\n/\n/sg;
    $html =~ s/<br>/\n/sg;
    return $html;
}



my $cgi = new CGI;
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

// this function must do exactly the same as the Perl inputToHtml() function (otherwise preview might be incorrect)
function inputToHtml (input)
{
    input = input.replace(/\r\n/g, '\n');
    input = input.replace(/\n/g, '<br>\n');
    return input;
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
        var newHtml = inputToHtml(newContent);
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
    }

    my $contentText = htmlToText($contentHtml);

    print "
<form method='POST' style='height:90%'>

<div style='display:inline-block; width:48%; height:100%; min-width: 15em'>
<div style='min-height:4ex'>
<input type='submit' name='save' id='btn_save' value='".(__ 'Save')."' style='padding-right:2em; padding-left:2em;'>
";

    if ($message)
    {
        print "$message\n";
    }

    print "</div>
<textarea style='width:100%; height:100%;' id='content' name='content' cols='70' rows='10' onchange='updatePreview()' onkeydown='updatePreview()' onkeyup='updatePreview()' oninput='updatePreview()'>$contentText</textarea>
</div>
<div style='display:inline-block; width:50%; height:100%; min-width:15em; padding-left:0.3em; padding-right:0.3em'>
<div style='height:4ex'>".(__ 'Preview:')."</div>
<iframe style='width:100%; height:100%' name='previewwin' id='previewwin' src='edit.pl?preview=1'></iframe>
</form>
";

    print $cgi->end_html();
}

