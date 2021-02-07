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

package Plugins::RatingButtons::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Plugins::RatingButtons::Common ':all';
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $LOG   = logger('plugin.ratingbuttons');
my $PREFS = preferences('plugin.ratingbuttons');

sub name
{
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RATINGBUTTONS');
}

sub page
{
    return Slim::Web::HTTP::CSRF->protectURI('plugins/RatingButtons/settings.html');
}

sub prefs
{
    return ( $PREFS, 'buttons_en' );
}

sub handler
{
    my ($class, $client, $params) = @_;

    # Save buttons config
    if ($params->{saveSettings})
    {
        # Make list of buttons from the contents of the html fields
        my @buttons = ();
        my %buttonsSeen = ();
        #$LOG->debug(fmt('save buttons: %s', [ sort keys %{$params} ]));
        for (my $n = 1; defined $params->{"button_name_$n"} && ($n <= $Plugins::RatingButtons::Common::MAX_BUTTONS); $n++)
        {
            my $name   = trim( $params->{"button_name_$n"}   // '' ); 
            my $single = trim( $params->{"button_single_$n"} // '' );
            my $hold   = trim( $params->{"button_hold_$n"}   // '' );
            # Only keep buttons with at least one action
            if ( (length($name) > 0) && !$buttonsSeen{$name} && ($single || $hold) )
            {
                push(@buttons, { name => $name, single => $single, hold => $hold });
                $buttonsSeen{$name} = 1;
                $LOG->debug("Save $name.single = $single, $name.hold = $hold");
            }
        }

        # Update preferences, which will trigger ::Plugin::prefChange()
        $PREFS->set('buttons', \@buttons);
    }

    # Get buttons config to generate html fields, validate it
    my @buttons = ();
    my $n = 0;
    foreach my $button (@{$PREFS->get('buttons') || []})
    {
        push(@buttons, $button);
        $n++;
        foreach my $style (qw(single hold))
        {
            if ($button->{$style})
            {
                my ($err) = validateActionStr($button->{$style});
                if ($err)
                {
                    $LOG->error("Bad action: $button->{name}.$style = $button->{$style}: $err");
                    $params->{"button_${style}_error"}->[$n] = $err;
                }
            }
        }
    }
    
    # Add one empty button, unless the maximum number of buttons has been reached
    if ( ($#buttons + 1) < $Plugins::RatingButtons::Common::MAX_BUTTONS )
    {
        push(@buttons, { name => '', single => '', hold => '' });
    }

    # Add buttons
    $params->{buttons} = \@buttons;
    #$LOG->debug(fmt('prefs buttons=%s', $params->{buttons}));

    # Add list of buttons and their description
    $params->{button_names_descs} = [ buttonNamesAndDescs() ];

    # Handle default stuff (such as the prefs declared by prefs() above)
    return $class->SUPER::handler($client, $params);
}

1;
########################################################################################################################
