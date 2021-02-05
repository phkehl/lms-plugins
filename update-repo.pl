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
    my $installXml  = "$FindBin::Bin/$pluginName/install.xml";
    my $installDoc  = XML::LibXML->load_xml(location => $installXml);
    #my $installRoot = $installDoc->documentElement();
    #print($installDoc->toString());

    my ($versionNode)    = $installDoc->findnodes('/extension/version');
    my ($minVersionNode) = $installDoc->findnodes('/extension/targetApplication/minVersion');
    my $version    = $versionNode->textContent();
    my $minVersion = $minVersionNode->textContent();

    printf("version=%s minVersion=%s\n", $version, $minVersion);

    my $zipName = "$pluginName-$version.zip";
    my $zipFile = "$FindBin::Bin/$zipName";
    if (system("cd $FindBin::Bin && zip -r $zipName $pluginName") != 0)
    {
        die("$!");
    }

    my $sha1 = Digest::SHA::sha1_hex( path($zipFile)->slurp_raw() );

    my ($pluginNode) = $repoDoc->findnodes("/extensions/plugins/plugin[\@name='$pluginName']");
    $pluginNode->setAttribute('version', $version);
    $pluginNode->setAttribute('minTarget', $minVersion);

    my ($urlNode) = $pluginNode->findnodes('./url');
    my $url = $urlNode->textContent();
    $url =~ s{$pluginName-.*\.zip}{$zipName};
    printf("url=%s\n", $url);
    $urlNode->removeChildNodes();
    $urlNode->appendText($url);

    my ($shaNode) = $pluginNode->findnodes('./sha');
    $shaNode->removeChildNodes();
    $shaNode->appendText($sha1);
}

#print($repoDoc->toString());
open(REPOXML, '>', $repoXml) || die("$!");
print(REPOXML $repoDoc->toString());
close(REPOXML);
