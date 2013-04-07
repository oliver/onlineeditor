#!/usr/bin/perl

#
# Simple online editor for modifying part of a web page.
#

use strict;
use warnings FATAL => qw( all );

use CGI;
use CGI::Carp qw(fatalsToBrowser);

$CGI::POST_MAX = 1024 * 100;
$CGI::DISABLE_UPLOADS = 1;


# the HTML file to modify
my $htmlFile = "./page.html";


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
        return "unknown error";
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
    print $cgi->header(-charset=>'utf-8',),
          $cgi->start_html(-title => 'Online Editor',
                           -style => { -code => '
html, body, form { height: 100%; }'
                            } );

    my $message = '';
    if ($cgi->param('save'))
    {
        my $error = saveToTemplate($contentHtml);
        if ($error)
        {
            $message .= "<font color='red'>Saving failed ($error). Please inform system administrator.</font> ";
        }
    }

    my $contentText = htmlToText($contentHtml);

    print "
<form method='POST'>

<input type='submit' name='save' id='btn_save' value='Save'>
";

    if ($message)
    {
        print "$message\n";
    }

    print "
<br>
<textarea style='width:48%; height:90%' id='content' name='content' cols='70' rows='10' onchange='updatePreview()' onkeydown='updatePreview()' onkeyup='updatePreview()' oninput='updatePreview()'>$contentText</textarea>
<iframe style='width:50%; height:90%' name='previewwin' id='previewwin' src='edit.pl?preview=1'></iframe>
</form>
";

print "
<script type='text/javascript'>

var origContent = document.getElementById('content').value;

// this function must do exactly the same as the Perl inputToHtml() function (otherwise preview might be incorrect)
function inputToHtml (input)
{
    input = input.replace(/\\r\\n/g, '\\n');
    input = input.replace(/\\n/g, '<br>\\n');
    return input;
}

function iframeRef(frameRef) {
    return frameRef.contentWindow ? frameRef.contentWindow.document : frameRef.contentDocument
}

function updatePreview()
{
    var newContent = document.getElementById('content').value;

    var changed = (newContent != origContent);
    document.getElementById('btn_save').disabled = !changed;

    var iframe = document.getElementById('previewwin');
    var idoc = iframeRef(iframe);
    //console.log(idoc);
    var editSpan = idoc.getElementById('editor_content');
    //console.log(editSpan);
    if (editSpan)
    {
        var newHtml = inputToHtml(newContent);
        editSpan.innerHTML = newHtml;
    }
}

// initial update:
updatePreview();
</script>
";

    print $cgi->end_html();
}

