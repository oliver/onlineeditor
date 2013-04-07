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

sub extractFromTemplate
{
    my ($html, $startPos, $len) = &parseTemplate();
    return substr($html, $startPos, $len);
}

# inserts the given content text into the HTML template; returns the resulting complete HTML text
sub applyTemplate
{
    my ($newContent) = @_;
    my ($html, $startPos, $len) = &parseTemplate();
    my $preText = substr($html, 0, $startPos);
    my $postText = substr($html, $startPos + $len);
    return $preText . $newContent . $postText;
}

# Processes raw textarea input into HTML that can be inserted into the template.
# This includes:
# - sanitizing HTML by escaping unknown/unwanted HTML tags
# - replacing linebreaks with <br>
sub inputToHtml
{
    my ($input) = @_;
    $input =~ s/\r\n/\n/sg;
    $input =~ s/\n/<br>\n/sg;
    return $input;
}

# TODO: fix name...
# Processes HTML content extracted from template so that it can be displayed in textarea.
# This includes:
# - replacing <br> with linebreaks
sub htmlToInput
{
    my ($html) = @_;
    $html =~ s/<br>\n/\n/sg;
    $html =~ s/<br>/\n/sg;
    return $html;
}



my $cgi = new CGI;

my $content = $cgi->param('content');
if (defined($content))
{
    $content = inputToHtml($content);
}
else
{
    $content = extractFromTemplate();
}


if ($cgi->param('preview'))
{
    print $cgi->header(-charset=>'utf-8',);

    $content = "<span id='editor_content'>$content</span>";

    print applyTemplate($content);
}
else
{
    print $cgi->header(-charset=>'utf-8',),
          $cgi->start_html();

    if ($cgi->param('save'))
    {
        #print "<p>saving...</p>\n";
        my $fullHtml = applyTemplate($content);
        open(OUT, ">$htmlFile") or die;
        print OUT $fullHtml;
        close(OUT);

        # extract current text from disk again, to check that saving was really successful:
        my $diskContent = extractFromTemplate();
        if ($diskContent ne $content)
        {
            # TODO: test this, and handle it so that drafted text is not lost
            print "<h3><font color='red'>saving failed</font></h3>\n";
        }
    }

    my $text = htmlToInput($content);

    print "<h3>Preview:</h3>
<iframe width='60%' height='40%' name='previewwin' id='previewwin' src='edit.pl?preview=1'></iframe>
";

    print "<form method='POST'><textarea id='content' name='content' cols='80' rows='10' onchange='updatePreview()' onkeydown='updatePreview()' onkeyup='updatePreview()' oninput='updatePreview()'>$text</textarea><br>
<input type='submit' name='save' id='btn_save' value='Save'>
<!-- <input type='submit' name='preview' value='Preview' onclick='win = window.open(\"about:blank\", \"previewwin\", \"width=500,height=250,resizable=yes\"); this.form.target = \"previewwin\"; win.focus();'> -->
<!-- <input type='submit' name='preview' value='Preview' onclick='this.form.target = \"previewwin\";'> -->
<!-- <input type='button' name='preview' value='Preview' onclick='updatePreview();'> -->
</form>\n";


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
#else
#{
#    die("unknown action '$action'");
#}


