#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use XML::LibXML;  # libxml-libxml-perl
use Digest::SHA;  # libdigest-sha-perl
use Path::Tiny;   # libpath-tiny-perl

my $repoXml  = "$FindBin::Bin/repo.xml";
my $repoDoc  = XML::LibXML->load_xml(location => $repoXml);
#my $repoRoot = $repoDoc->documentElement();
#print($repoDoc->toString());

foreach my $pluginName (qw(RatingButtons))
{
    print("----- $pluginName -----\n");

    # ----- Get plugin info -----

    # Plugin spec
    my $installXml  = "$FindBin::Bin/$pluginName/install.xml";
    my $installDoc  = XML::LibXML->load_xml(location => $installXml);
    #my $installRoot = $installDoc->documentElement();
    #print($installDoc->toString());

    # Get plugin version
    my ($versionNode) = $installDoc->findnodes('/extension/version');
    my $pluginVersion = $versionNode->textContent();

    # Get LMS minimal version required
    my ($minVersionNode) = $installDoc->findnodes('/extension/targetApplication/minVersion');
    my $minLmsVersion = $minVersionNode->textContent();

    printf("  pluginVersion:     %s\n", $pluginVersion);
    printf("  minLmsVersion:     %s\n", $minLmsVersion);

    # Get title and description from strings.txt
    my ($nameNode) = $installDoc->findnodes('/extension/name');
    my ($descriptionNode) = $installDoc->findnodes('/extension/description');
    my $pluginTitle = $nameNode->textContent();
    my $pluginDescription = $descriptionNode->textContent();
    $pluginTitle = getString("$FindBin::Bin/$pluginName/strings.txt", $pluginTitle);
    $pluginDescription = getString("$FindBin::Bin/$pluginName/strings.txt", $pluginDescription);
    printf("  pluginTitle:       %s\n", $pluginTitle);
    printf("  pluginDescription: %s\n", $pluginDescription);

    # Create zip file
    my $zipName = "$pluginName-$pluginVersion.zip";
    my $zipFile = "$FindBin::Bin/$zipName";
    if (system("cd $FindBin::Bin && rm -f $zipName && zip -q -r $zipName $pluginName") != 0)
    {
        die("$!");
    }
    my $zipSha1 = Digest::SHA::sha1_hex( path($zipFile)->slurp_raw() );

    printf("  zipName:           %s\n", $zipName);
    printf("  zipSha1:           %s\n", $zipSha1);

    # ----- Update repo.xml -----

    # Set plugin version and minimal required LMS version
    my ($pluginNode) = $repoDoc->findnodes("/extensions/plugins/plugin[\@name='$pluginName']");
    $pluginNode->setAttribute('version', $pluginVersion);
    $pluginNode->setAttribute('minTarget', $minLmsVersion);

    # Set URL
    my ($urlNode) = $pluginNode->findnodes('./url');
    my $url = $urlNode->textContent();
    $url =~ s{$pluginName-.*\.zip}{$zipName};
    printf("  url:               %s\n", $url);
    $urlNode->removeChildNodes();
    $urlNode->appendText($url);

    # Set SHA1
    my ($shaNode) = $pluginNode->findnodes('./sha');
    $shaNode->removeChildNodes();
    $shaNode->appendText($zipSha1);

    # Set title and description
    my ($titleNode) = $pluginNode->findnodes('./title');
    $titleNode->removeChildNodes();
    $titleNode->appendText($pluginTitle);
    my ($descNode) = $pluginNode->findnodes('./desc');
    $descNode->removeChildNodes();
    $descNode->appendText($pluginDescription);

    print("\n");
}

#print($repoDoc->toString());
open(my $fh, '>', $repoXml) || die("$!");
print($fh $repoDoc->toString());
close($fh);

sub getString
{
    my ($txt, $id, $lang) = @_;
    $lang ||= 'EN';
    my $str = $id;
    open(my $fh, '<', $txt) || die("$!");
    my $haveId = 0;
    while (my $line = <$fh>)
    {
        if ($line =~ m{^$id$})
        {
            $haveId = 1;
        }
        elsif ($line =~ m{^$})
        {
            $haveId = 0;
        }
        elsif ($haveId && ($line =~ m{^\t$lang\t(.+)$}))
        {
            $txt = $1;
        }
    }
    close($fh);
    return $txt;
}
