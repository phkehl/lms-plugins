########################################################################################################################
#
# flipflip's RatingButtons plugin
#
# Copyright (c) 2021 Philippe Kehl (flipflip at oinkzwurgl dot org)
#
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program. If not, see
# <https://www.gnu.org/licenses/>.
#
########################################################################################################################

package Plugins::RatingButtons::Common;

use strict;
use warnings;

use Data::Dumper;
use Storable;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;

use base 'Exporter';
our %EXPORT_TAGS =
(
    all => [ qw( rating2stars stars2rating stars2text clipInt fmt clone trim buttonNamesAndDescs validateActionStr) ],
);
our @EXPORT_OK =
(
    @{ $EXPORT_TAGS{all} }
);

# Preferences defaults
our $PREF_BUTTONS_EN_DEFAULT = 0;
our $PREF_BUTTONS_DEFAULT    = [
    { name => 'favorites', single => 'rate(5)',    hold => 'rate(0)' },
    { name => 'add',       single => 'show',       hold => 'toggle(0, 5)' },
    { name => 'search',    single => 'inc(1)',     hold => 'dec(1)' },
    { name => 'browse',    single => 'pass',       hold => 'pass' },
];

my $LOG = logger('plugin.ratingbuttons');

# Maximum number of buttons we'll handle
our $MAX_BUTTONS = 20;

# Clip integer value in range, return $min (or $def, if given) if $val is undef or out of range
sub clipInt
{
    my ($val, $min, $max, $def) = @_;
    my $v = defined $val ? int($val) : ($def // $min);
    if ($v < $min)
    {
        $v = $min;
    }
    elsif ($v > $max)
    {
        $v = $max;
    }
    return $v;
}

# Convert rating (undef, 0..100) to stars (0..5)
sub rating2stars
{
    my ($rating) = @_;
    return int( clipInt($rating, 0, 100) / 20);
}

# Convert stars (0..5) to rating (0..100)
sub stars2rating
{
    my ($stars) = @_;
    return int( clipInt($stars, 0, 5) * 20)
}

# Convert stars (0..5) to text ('', 'n', 'n n', 'n n n', ..., 'n n n n n', where 'n' is the note symbol)
sub stars2text
{
    my ($stars, $space, $char) = @_;
    $char  ||= chr(1); # Note symbol (http://localhost:9000/html/docs/fonts.html)
    $space //= ' ';
    return $stars ? (($char . $space) x $stars) : '';
}

# Format a thing or a string like snprintf() but stringify non-scalar and undef things
sub fmt
{
    my ($fmt, @args) = @_;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse = 1;
    if ($#args == -1)
    {
        return _stringify($fmt);
    }
    else
    {
        return sprintf($fmt, map { _stringify($_) } @args);
    }
}

sub _stringify
{
    my ($thing) = @_;
    return ref($thing) ? Data::Dumper::Dumper($thing) : (!defined $thing ? '<undef>' : $thing);
}

# Deep clone an (clonable!) object, such as a hash or array reference
sub clone
{
    my ($thing) = @_;
    my $copy = Storable::dclone($thing);
    return $copy;
}

# Trim leading and trailing whitespace from a string
sub trim
{
    my ($str) = @_;
    $str =~ s{^\s+}{};
    $str =~ s{\s+$}{};
    return $str;
}

# Return a list of button names and their description
sub buttonNamesAndDescs
{
    my $buttonStr = string('PLUGIN_RATINGBUTTONS_BUTTON');
    return
    (
        { name => '0',               desc => $buttonStr . ' 0' },
        { name => '1',               desc => $buttonStr . ' 1' },
        { name => '2',               desc => $buttonStr . ' 2' },
        { name => '3',               desc => $buttonStr . ' 3' },
        { name => '4',               desc => $buttonStr . ' 4' },
        { name => '5',               desc => $buttonStr . ' 5' },
        { name => '6',               desc => $buttonStr . ' 6' },
        { name => '7',               desc => $buttonStr . ' 7' },
        { name => '8',               desc => $buttonStr . ' 8' },
        { name => '9',               desc => $buttonStr . ' 9' },

        { name => 'sleep',           desc => string('SLEEP')                              . ' ' . $buttonStr },
        { name => 'power',           desc => string('POWER')                              . ' ' . $buttonStr },

        { name => 'fwd',             desc => string('FFWD')                               . ' ' . $buttonStr },
        { name => 'pause',           desc => string('PAUSE')                              . ' ' . $buttonStr },
        { name => 'rew',             desc => string('REW')                                . ' ' . $buttonStr },

        { name => 'add',             desc => string('ADD')                                . ' ' . $buttonStr },
        { name => 'play',            desc => string('PLAY')                               . ' ' . $buttonStr },

        { name => 'arrow_up',        desc => string('UP')                                 . ' ' . $buttonStr },
        { name => 'arrow_left',      desc => string('PLUGIN_RATINGBUTTONS_LEFT')          . ' ' . $buttonStr },
        { name => 'arrow_right',     desc => string('PLUGIN_RATINGBUTTONS_RIGHT')         . ' ' . $buttonStr },
        { name => 'arrow_down',      desc => string('DOWN')                               . ' ' . $buttonStr },

        { name => 'voldown',         desc => string('VOLUME') . ' ' . string('DOWN')      . ' ' . $buttonStr },
        { name => 'volup',           desc => string('VOLUME') . ' ' . string('UP')        . ' ' . $buttonStr },

        { name => 'favorites',       desc => string('FAVORITES')                          . ' ' . $buttonStr },
        { name => 'search',          desc => string('SEARCH')                             . ' ' . $buttonStr },

        { name => 'browse',          desc => string('BROWSE')                             . ' ' . $buttonStr },
        { name => 'shuffle',         desc => string('SHUFFLE')                            . ' ' . $buttonStr },
        { name => 'repeat',          desc => string('REPEAT')                             . ' ' . $buttonStr },

        { name => 'now_playing',     desc => string('NOW_PLAYING')                        . ' ' . $buttonStr },
        { name => 'size',            desc => string('PLUGIN_RATINGBUTTONS_SIZE')          . ' ' . $buttonStr },
        { name => 'brightness',      desc => string('SETUP_GROUP_BRIGHTNESS')             . ' ' . $buttonStr },

        { name => 'menu_home',       desc => string('HOME')                               . ' ' . $buttonStr },
        { name => 'muting',          desc => string('MUTE')                               . ' ' . $buttonStr },
        { name => 'stop',            desc => string('STOP')                               . ' ' . $buttonStr },

        # Presets buttons on Boom (and Radio?)
        { name => 'preset_1',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 1' },
        { name => 'preset_2',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 2' },
        { name => 'preset_3',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 3' },
        { name => 'preset_4',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 4' },
        { name => 'preset_5',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 5' },
        { name => 'preset_6',        desc => string('PLUGIN_RATINGBUTTONS_PRESET')        . ' ' . $buttonStr . ' 6' },
    );
}

# Validate a button action string (preference), return '' if okay or a string if error, along with the actions split
# into pieces (action and arguments), also setting default arguments
sub validateActionStr
{
    my ($str) = @_;
    #$LOG->debug("str=$str");

    $str = trim($str);
    my $cmd = '';
    my @args = ();
    if ($str =~ m{^([a-z]+)(?:\((.*)\))?$})
    {
        $cmd = $1;
        if (defined $2)
        {
            @args = split(/\s*,\s*/, $2);
        }
    }
    else
    {
        return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') )
    }

    sub argErr
    {
        my ($n, $v, $e) = @_;
        return sprintf(string('PLUGIN_RATINGBUTTONS_ERROR_ARG_BAD'), $n, $v) . '. ' .
               sprintf(string('PLUGIN_RATINGBUTTONS_ERROR_ARG_EXPECT'), $e);
    }
    sub argMiss
    {
        my ($n) = @_;
        return sprintf(string('PLUGIN_RATINGBUTTONS_ERROR_ARG_MISS'), $n);
    }

    if ($cmd eq 'show')
    {
        my $duration = $args[0] // 2.0;
        if ( ($duration !~ m{^[0-9]+(\.[0-9]|)$}) || ($duration < 0.1) || ($duration > 10.0) )
        {
            return argErr(1, $duration, "0.1 - 10.0");
        }
        return ( '', $cmd, $duration );
    }
    elsif ($cmd eq 'rate')
    {
        if ($#args != 0)
        {
            return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') );
        }
        my $a1 = $args[0] // undef;
        if (!defined $a1)
        {
            return argMiss(1);
        }
        if ($a1 !~ m{^[012345]$})
        {
            return argErr(1, $a1, '0 - 5');
        }
        return ( '', $cmd, $a1 );
    }
    elsif ( ($cmd eq 'inc') || ($cmd eq 'dec') )
    {
        if ($#args > 0)
        {
            return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') );
        }
        my $a1 = $args[0] // 1;
        if (!defined $a1)
        {
            return argMiss(1);
        }
        if ($a1 !~ m{^[12345]$})
        {
            return argErr(1, $a1, '1 - 5');
        }
        return ( '', $cmd, $a1 );
    }
    elsif ($cmd eq 'toggle')
    {
        my $a1 = $args[0] // undef;
        my $a2 = $args[1] // undef;
        if (!defined $a1)
        {
            return argMiss(1)
        }
        if (!defined $a2)
        {
            return argMiss(1)
        }
        if ($a1 !~ m{^[01245]$})
        {
            return argErr(1, $a1, '0 - 5');
        }
        if ($a2 !~ m{^[01245]$})
        {
            return argErr(2, $a2, '0 - 5');
        }
        if ($a2 <= $a1)
        {
            return argErr(2, $a2, "> $a1");
        }
        return ( '', $cmd, $a1, $a2 );
    }
    elsif ($cmd eq 'pass')
    {
        if ($#args != -1)
        {
            return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') );
        }
        return ( '', $cmd );
    }
    elsif ($cmd eq 'exec')
    {
        if ($#args < 2)
        {
            return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') );
        }
        my $a1 = $args[0];
        if ($a1 !~ m{^(this|all|others?|[0-9a-f]{2,2}:[0-9a-f]{2,2}:[0-9a-f]{2,2}:[0-9a-f]{2,2}:[0-9a-f]{2,2}:[0-9a-f]{2,2})$}i)
        {
            return argErr(1, $a1, 'this, all, others or 01:23:45:67:89:ab');
        }
        return ( '', $cmd, @args );
    }
    elsif ($cmd eq 'mode')
    {
        if ($#args > 0)
        {
            return ( string('PLUGIN_RATINGBUTTONS_ERROR_SYNTAX') );
        }
        my $a1 = $args[0] // 1;
        if (!defined $a1)
        {
            return argMiss(1);
        }
        # TODO: check if arg is a valid mode
        return ( '', $cmd, $a1 );
    }
    else
    {
        return sprintf(string('PLUGIN_RATINGBUTTONS_ERROR_UNKNOWN'), $cmd);
    }
}

1;
########################################################################################################################
